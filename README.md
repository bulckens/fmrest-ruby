# fmrest-ruby

<a href="https://rubygems.org/gems/fmrest"><img src="https://badge.fury.io/rb/fmrest.svg?style=flat" alt="Gem Version"></a>

A Ruby client for
[FileMaker 18 and 19's Data API](https://help.claris.com/en/data-api-guide)
using
[Faraday](https://github.com/lostisland/faraday) and with optional
[Spyke](https://github.com/balvig/spyke) support (ActiveRecord-ish models).

If you're looking for a Ruby client for the legacy XML/Custom Web Publishing
API try the fabulous [ginjo-rfm gem](https://github.com/ginjo/rfm) instead.

fmrest-ruby only partially implements FileMaker 18's Data API.
See the [implementation completeness table](#api-implementation-completeness-table)
to see if a feature you need is natively supported by the gem.

## Installation

Add this line to your Gemfile:

```ruby
gem 'fmrest'

# Optional but recommended (for ORM features)
gem 'spyke'
```

## Basic usage (without ORM)

To get a Faraday connection that can handle FM's Data API auth workflow:

```ruby
connection = FmRest::V1.build_connection(
  host:     "example.com",
  database: "database name",
  username: "username",
  password: "password"
)
```

The returned connection will prefix any non-absolute paths with
`"/fmi/data/v1/databases/:database/"`, so you only need to supply the
meaningful part of the path.

To send a request to the Data API use Faraday's standard methods, e.g.:

```ruby
# Get all records
connection.get("layouts/MyFancyLayout/records")

# Create new record
connection.post do |req|
  req.url "layouts/MyFancyLayout/records"

  # You can just pass a hash for the JSON body
  req.body = { ... }
end
```

For each request fmrest-ruby will first request a session token (using the
provided username and password) if it doesn't yet have one in store.

### Logging out of the database session

The Data API requires sending a DELETE request to
`/fmi/data/:version/databases/:database_name/sessions/:session_token`
in order to log out from the session
([see docs](https://fmhelp.filemaker.com/docs/18/en/dataapi/#connect-database_log-out)).

Since fmrest-ruby handles the storage of session tokens internally, and the
token is required to build the logout URL, this becomes a non-trivial action.

To remedy this, fmrest-ruby connections recognize when you're trying to logout
and substitute whatever is in the `:session_token` section of the logout path
with the actual session token:

```ruby
# Logout from the database session
connection.delete "sessions/this-will-be-replaced-with-the-actual-token"
```

If you're using the ORM features this becomes much easier, see
[Model.logout](#modellogout) below.

## Connection settings

In addition to the required `:host`, `:database`, `:username` and `:password`
connection options, you can also pass `:ssl` and `:proxy`, which are passed to
the underlying [Faraday](https://github.com/lostisland/faraday) connection.

You can use this to, for instance, disable SSL verification:

```ruby
FmRest::V1.build_connection(
  host:     "example.com",
  ...
  ssl:      { verify: false }
)
```

You can also pass a `:log` option for basic request logging, see the section on
[Logging](#Logging) below.

`:username` is also aliased as `:account_name` to provide cross-compatibility
with the ginjo-rfm gem.

### Full list of available options

Option              | Description                                | Format                      | Default
--------------------|--------------------------------------------|-----------------------------|--------
`:host`             | Hostname with optional port, e.g. `"example.com:9000"` | String          | None
`:database`         |                                            | String                      | None
`:username`         |                                            | String                      | None
`:password`         |                                            | String                      | None
`:ssl`              | SSL options to be forwarded to Faraday     | Faraday SSL options         | None
`:proxy`            | Proxy options to be forwarded to Faraday   | Faraday proxy options       | None
`:log`              | Log JSON responses to STDOUT               | Boolean                     | `false`
`:coerce_dates`     | See section on [date fields](#date-fields) | Boolean \| `:hybrid` \| `:full` | `false`
`:date_format`      | Date parsing format                        | String (FM date format)     | `"MM/dd/yyyy"`
`:timestamp_format` | Timestmap parsing format                   | String (FM date format)     | `"MM/dd/yyyy HH:mm:ss"`
`:time_format`      | Time parsing format                        | String (FM date format)     | `"HH:mm:ss"`
`:timezone`         | The timezone for the FM server             | `:local` \| `:utc` \| `nil` | `nil`

### Default connection settings

If you're only connecting to a single FM database you can configure it globally
through `FmRest.default_connection_settings=`. E.g.:

```ruby
FmRest.default_connection_settings = {
  host:     "example.com",
  database: "database name",
  username: "username",
  password: "password"
}
```

This configuration will be used by default by `FmRest::V1.build_connection` as
well as your models whenever you don't pass a configuration hash explicitly.


## Session token store

By default fmrest-ruby will use a memory-based store for the session tokens.
This is generally good enough for development, but not good enough for
production, as in-memory tokens aren't shared across threads/processes.

Besides the default token store the following token stores are bundled with fmrest-ruby:

### ActiveRecord

On Rails apps already using ActiveRecord setting up this token store should be
dead simple:

```ruby
# config/initializers/fmrest.rb
require "fmrest/token_store/active_record"

FmRest.token_store = FmRest::TokenStore::ActiveRecord
```

No migrations are needed, the token store table will be created automatically
when needed, defaulting to the table name "fmrest_session_tokens". If you want
to change the table name you can do so by initializing the token store and
passing it the `:table_name` option:

```ruby
FmRest.token_store = FmRest::TokenStore::ActiveRecord.new(table_name: "my_token_store")
```

### Redis

To use the Redis token store do:

```ruby
require "fmrest/token_store/redis"

FmRest.token_store = FmRest::TokenStore::Redis
```

You can also initialize it with the following options:

* `:redis` - A `Redis` object to use as connection, if ommited a new `Redis`
  object will be created with remaining options
* `:prefix` - The prefix to use for token keys, by default `"fmrest-token:"`
* Any other options will be passed to `Redis.new` if `:redis` isn't provided

Examples:

```ruby
# Passing a Redis connection explicitly
FmRest.token_store = FmRest::TokenStore::Redis.new(redis: Redis.new, prefix: "my-fancy-prefix:")

# Passing options for Redis.new
FmRest.token_store = FmRest::TokenStore::Redis.new(prefix: "my-fancy-prefix:", host: "10.0.1.1", port: 6380, db: 15)
```

NOTE: redis-rb is not included as a gem dependency of fmrest-ruby, so you'll
have to add it to your Gemfile.

### Moneta

[Moneta](https://github.com/moneta-rb/moneta) is a key/value store wrapper
around many different storage backends. If ActiveRecord or Redis don't suit
your needs, chances are Moneta will.

To use it:

```ruby
# config/initializers/fmrest.rb
require "fmrest/token_store/moneta"

FmRest.token_store = FmRest::TokenStore::Moneta
```

By default the `:Memory` moneta backend will be used.

You can also initialize it with the following options:

* `:backend` - The moneta backend to initialize the store with
* `:prefix` - The prefix to use for token keys, by default `"fmrest-token:"`
* Any other options will be passed to `Moneta.new`

Examples:

```ruby
# Using YAML as a backend with a custom prefix
FmRest.token_store = FmRest::TokenStore::Moneta.new(
  backend: :YAML,
  file:    "tmp/tokens.yml",
  prefix:  "my-tokens"
)
```

NOTE: the moneta gem is not included as a dependency of fmrest-ruby, so
you'll have to add it to your Gemfile.


## Date fields

Since the Data API uses JSON (wich doesn't provide a native date/time object),
dates and timestamps are received in string format. By default fmrest-ruby
leaves those string fields untouched, but it provides an opt-in feature to try
to automatically "coerce" them into Ruby date objects.

The connection option `:coerce_dates` controls this feature. Possible values
are:

* `:full` - whenever a string matches the given date/timestamp/time format,
  convert them to `Date` or `DateTime` objects as appropriate
* `:hybrid` or `true` - similar as above, but instead of converting to regular
  `Date`/`DateTime` it converts strings to `FmRest::StringDate` and
  `FmRest::StringDateTime`, "hybrid" classes provided by fmrest-ruby that
  retain the functionality of `String` while also providing most the
  functionality of `Date`/`DateTime` (more on this below)
* `false` - disable date coercion entirely (default), leave original string
  values untouched

Enabling date coercion works with both basic fmrest-ruby connections and Spyke
models (ORM).

The connection options `:date_format`, `:timestamp_format` and `:time_format`
control how to match and parse dates. You only need to provide these if you use
a date/time localization different from American format (the default).

Future versions of fmrest-ruby will provide better (and less heuristic) ways of
specifying and/or detecting date fields (e.g. by requesting layout metadata or
a DSL in model classes).

### Hybrid string/date objects

`FmRest::StringDate` and `FmRest::StringDateTime` are special classes that
inherit from `String`, but internally parse and store a `Date` or `DateTime`,
and delegate any methods not provided by `String` to those objects. In other
words, they quack like a duck *and* bark like a dog.

You can use these when you want fmrest-ruby to provide you with date objects,
but you don't want to worry about date coercion of false positives (i.e. a
string field that gets converted to `Date` because it just so matched the given
date format).

Be warned however that these classes come with a fair share of known gotchas
(see GitHub wiki for more info). Some of those gothas can be removed by calling

```ruby
FmRest::StringDateAwareness.enable
```

Which will extend the core `Date` and `DateTime` classes to be aware of
`FmRest::StringDate`, especially when calling `Date.===`, `Date.parse` or
`Date._parse`.

If you're working with ActiveRecord models this will also make them accept
`FmRest::StringDate` values for date fields.

### Timezones

fmrest-ruby has basic timezone support. You can set the `:timezone` option in
your connection settings to one of the following values:

* `:local` - dates will be converted to your system local time offset (as
  defined by `ENV["TZ"]`), or the timezone set by `Time.zone` if you're using
  ActiveSupport
* `:utc` - dates will be converted to UTC offset
* `nil` - (default) ignore timezones altogether


## Spyke support (ActiveRecord-like ORM)

[Spyke](https://github.com/balvig/spyke) is an ActiveRecord-like gem for
building REST models. fmrest-ruby has Spyke support out of the box, although
Spyke itself is not a dependency of fmrest-ruby, so you'll need to add it to
your Gemfile yourself:

```ruby
gem 'spyke'
```

Then require fmrest-ruby's Spyke support:

```ruby
# Put this in config/initializers/fmrest.rb if it's a Rails project
require "fmrest/spyke"
```

And finally extend your Spyke models with `FmRest::Spyke`:

```ruby
class Honeybee < Spyke::Base
  include FmRest::Spyke
end
```

This will make your Spyke model send all its requests in Data API format, with
token session auth. Find, create, update and destroy actions should all work
as expected.

Alternatively you can inherit directly from the shorthand
`FmRest::Spyke::Base`, which is in itself a subclass of `Spyke::Base` with
`FmRest::Spyke` already included:

```ruby
class Honeybee < FmRest::Spyke::Base
end
```

All of Spyke's basic ORM operations work:

```ruby
bee = Honeybee.new

bee.name = "Hutch"
bee.save # POST request

bee.name = "ハッチ"
bee.save # PATCH request

bee.reload # GET request

bee.destroy # DELETE request

bee = Honeybee.find(9) # GET request
```

Read Spyke's documentation for more information on these basic features.

In addition `FmRest::Spyke` extends `Spyke::Base` subclasses with the following
features:

### Model.fmrest_config=

Usually to tell a Spyke object to use a certain Faraday connection you'd use:

```ruby
class Honeybee < Spyke::Base
  self.connection = Faraday.new(...)
end
```

fmrest-ruby simplfies the process of setting up your Spyke model with a Faraday
connection by allowing you to just set your Data API connection settings:

```ruby
class Honeybee < Spyke::Base
  include FmRest::Spyke

  self.fmrest_config = {
    host:     "example.com",
    database: "My Database",
    username: "...",
    password: "..."
  }
end
```

This will automatically create a proper Faraday connection for those connection
settings.

Note that these settings are inheritable, so you could create a base class that
does the initial connection setup and then inherit from it in models using that
same connection. E.g.:

```ruby
class BeeBase < Spyke::Base
  include FmRest::Spyke

  self.fmrest_config = {
    host:     "example.com",
    database: "My Database",
    username: "...",
    password: "..."
  }
end

class Honeybee < BeeBase
  # This model will use the same connection as BeeBase
end
```

### Model.layout

Use `layout` to set the `:layout` part of API URLs, e.g.:

```ruby
class Honeybee < FmRest::Spyke::Base
  layout "Honeybees Web" # uri path will be "layouts/Honeybees%20Web/records(/:id)"
end
```

This is much preferred over using Spyke's `uri` to set custom URLs for your
Data API models.

Note that you only need to set this if the name of the model and the name of
the layout differ, otherwise the default will just work.

### Model.logout

Use `logout` to log out from the database session (you may call it on any model
that uses the database session you want to log out from).

```ruby
Honeybee.logout
```

### Mapped Model.attributes

Spyke allows you to define your model's attributes using `attributes`, however
sometimes FileMaker's field names aren't very Ruby-ORM-friendly, especially
since they may sometimes contain spaces and other special characters, so
fmrest-ruby extends `attributes`' functionality to allow you to map
Ruby-friendly attribute names to FileMaker field names. E.g.:

```ruby
class Honeybee < FmRest::Spyke::Base
  attributes first_name: "First Name", last_name: "Last Name"
end
```

You can then simply use the pretty attribute names whenever working with your
model and they will get mapped to their FileMaker fields:

```ruby
bee = Honeybee.find(1)

bee.first_name # => "Princess"
bee.last_name  # => "Buzz"

bee.first_name = "Queen"

bee.attributes # => { "First Name": "Queen", "Last Name": "Buzz" }
```

### Model.has_portal

You can define portal associations on your model as such:

```ruby
class Honeybee < FmRest::Spyke::Base
  has_portal :flowers
end

class Flower < FmRest::Spyke::Base
  attributes :color, :species
end
```

In this case fmrest-ruby will expect the portal table name and portal object
name to be both "flowers", i.e. the expected portal JSON portion should look
like this:

```json
...
"portalData": {
  "flowers": [
    {
      "flowers::color": "red",
      "flowers::species": "rose"
    }
  ]
}
```

If you need to specify different values for them you can do so with
`portal_key` for the portal table name, and `attribute_prefix` for the portal
object name, and `class_name`, e.g.:

```ruby
class Honeybee < FmRest::Spyke::Base
  has_portal :pollinated_flowers, portal_key: "Bee Flowers",
                                  attribute_prefix: "Flower",
                                  class_name: "Flower"
end
```

The above will use the `Flower` model class and expects the following portal JSON
portion:

```json
...
"portalData": {
  "Bee Flowers": [
    {
      "Flower::color": "white",
      "Flower::species": "rose"
    }
  ]
}
```

### Dirty attributes

fmrest-ruby includes support for ActiveModel's Dirty mixin out of the box,
providing methods like:

```ruby
bee = Honeybee.new

bee.changed? # => false

bee.name = "Maya"

bee.changed? # => true

bee.name_changed? # => true
```

fmrest-ruby uses the Dirty functionality to only send changed attributes back
to the server on save.

You can read more about [ActiveModel's Dirty in Rails
Guides](https://guides.rubyonrails.org/active_model_basics.html#dirty).

### Query API

Since Spyke is API-agnostic it only provides a wide-purpose `.where` method for
passing arbitrary parameters to the REST backend. fmrest-ruby however is well
aware of its backend API, so it extends Spkye models with a bunch of useful
querying methods.

#### .limit

`.limit` sets the limit for get and find request:

```ruby
Honeybee.limit(10)
```

NOTE: You can also set a default limit value for a model class, see
[other notes on querying](#other-notes-on-querying).

You can also use `.limit` to set limits on portals:

```ruby
Honeybee.limit(hives: 3, flowers: 2)
```

To remove the limit on a portal set it to `nil`:

```ruby
Honeybee.limit(flowers: nil)
```

#### .offset

`.offset` sets the offset for get and find requests:

```ruby
Honeybee.offset(10)
```

You can also use `.offset` to set offsets on portals:

```ruby
Honeybee.offset(hives: 3, flowers: 2)
```

To remove the offset on a portal set it to `nil`:

```ruby
Honeybee.offset(flowers: nil)
```

#### .sort

`.sort` (or `.order`) sets sorting options for get and find requests:

```ruby
Honeybee.sort(:name, :age)
Honeybee.order(:name, :age) # alias method
```

You can set descending sort order by appending either `!` or `__desc` to a sort
attribute (defaults to ascending order):

```ruby
Honeybee.sort(:name, :age!)
Honeybee.sort(:name, :age__desc)
```

NOTE: You can also set default sort values for a model class, see
[Other notes on querying](#other-notes-on-querying).

#### .portal

`.portal` (aliased as `.includes` and `.portals`) sets which portals to fetch
(if any) for get and find requests (this recognizes portals defined with
`has_portal`):

```ruby
Honeybee.portal(:hives)   # include just the :hives portal
Honeybee.includes(:hives) # alias method
Honeybee.portals(:hives, :flowers) # alias for pluralization fundamentalists
```

Chaining calls to `.portal` will add portals to the existing included list:

```ruby
Honeybee.portal(:flowers).portal(:hives) # include both portals
```

If you want to disable portals for the scope call `.portal(false)`:

```ruby
Honeybee.portal(false) # disable portals for this scope
```

If you want to include all portals call `.portal(true)`:

```ruby
Honeybee.portal(true) # include all portals
```

For convenience you can also use `.with_all_portals` and `.without_portals`,
which behave just as calling `.portal(true)` and `portal(false)` respectively.

NOTE: By default all portals are included.

#### .query

`.query` sets query conditions for a find request (and supports attributes as
defined with `attributes`):

```ruby
Honeybee.query(name: "Hutch")
# JSON -> {"query": [{"Bee Name": "Hutch"}]}
```

Passing multiple attributes to `.query` will group them in the same JSON object:

```ruby
Honeybee.query(name: "Hutch", age: 4)
# JSON -> {"query": [{"Bee Name": "Hutch", "Bee Age": 4}]}
```

Calling `.query` multiple times or passing it multiple hashes creates separate
JSON objects (so you can define OR queries):

```ruby
Honeybee.query(name: "Hutch").query(name: "Maya")
Honeybee.query({ name: "Hutch" }, { name: "Maya" })
# JSON -> {"query": [{"Bee Name": "Hutch"}, {"Bee Name": "Maya"}]}
```

#### .omit

`.omit` works like `.query` but excludes matches:

```ruby
Honeybee.omit(name: "Hutch")
# JSON -> {"query": [{"Bee Name": "Hutch", "omit": "true"}]}
```

You can get the same effect by passing `omit: true` to `.query`:

```ruby
Honeybee.query(name: "Hutch", omit: true)
# JSON -> {"query": [{"Bee Name": "Hutch", "omit": "true"}]}
```

#### .script

`.script` enables the execution of scripts during query requests.

```ruby
Honeybee.script("My script").find_some # Fetch records and execute a script
```

See section on [script execution](#script-execution) below for more info.

#### Other notes on querying

You can chain all query methods together:

```ruby
Honeybee.limit(10).offset(20).sort(:name, :age!).portal(:hives).query(name: "Hutch")
```

You can also set default values for limit and sort on the class:

```ruby
class Honeybee < FmRest::Spyke::Base
  self.default_limit = 1000
  self.default_sort = [:name, :age!]
end
```

Calling any `Enumerable` method on the resulting scope object will trigger a
server request, so you can treat the scope as a collection:

```ruby
Honeybee.limit(10).sort(:name).each { |bee| ... }
```

If you want to explicitly run the request instead you can use `.find_some` on
the scope object:

```ruby
Honeybee.limit(10).sort(:name).find_some # => [<Honeybee...>, ...]
```

If you want just a single result you can use `.first` instead (this will
force `.limit(1)`):

```ruby
Honeybee.query(name: "Hutch").first # => <Honeybee...>
```

If you know the id of the record you should use `.find(id)` instead of
`.query(id: id).first` (so that the sent request is
`GET ../:layout/records/:id` instead of `POST ../:layout/_find`).

```ruby
Honeybee.find(89) # => <Honeybee...>
```

Note also that if you use `.find(id)` your `.query()` parameters (as well as
limit, offset and sort parameters) will be discarded as they're not supported
by the single record endpoint.


### Finding records in batches

Sometimes you want to iterate over a very large number of records to do some
processing, but requesting them all at once would result in one huge request to
the Data API, and loading too many records in memory all at once.

To mitigate this problem you can use `.find_in_batches` and `.find_each`. If
you've used ActiveRecord you're probably familiar with how they operate:

```ruby
# Find records in batches of 100 each
Honeybee.query(hive: "Queensville").find_in_batches(batch_size: 100) do |batch|
  dispatch_bees(batch)
end

# Iterate over all records using batches
Honeybee.query(hive: "Queensville").find_each(batch_size: 100) do |bee|
  bee.dispatch
end
```

`.find_in_batches` yields collections of records (batches), while `.find_each`
yields individual records, but using batches behind the scenes.

Both methods accept a block-less form in which case they return an
`Enumerator`:

```ruby
batch_enum = Honeybee.find_in_batches

batch = batch_enum.next # => Spyke::Collection

batch_enum.each do |batch|
  process_batch(batch)
end

record_enum = Honeybee.find_each

record_enum.next # => Honeybee
```

NOTE: By its nature, batch processing is subject to race conditions if other
processes are modifying the database.


### Container fields

You can define container fields on your model class with `container`:

```ruby
class Honeybee < FmRest::Spyke::Base
  container :photo, field_name: "Beehive Photo ID"
end
```

`:field_name` specifies the original field in the FM layout and is optional, if
not given it will default to the name of your attribute (just `:photo` in this
example).

(Note that you don't need to define container fields with `attributes` in
addition to the `container` definition.)

This will provide you with the following instance methods:

```ruby
bee = Honeybee.new

bee.photo.url # The URL of the container file on the FileMaker server

bee.photo.download # Download the contents of the container as an IO object

bee.photo.upload(filename_or_io) # Upload a file to the container
```

`upload` also accepts an options hash with the following options:

* `:repetition` - Sets the field repetition
* `:filename` - The filename to use when uploading (defaults to
  `filename_or_io.original_filename` if available)
* `:content_type` - The MIME content type to use (defaults to
  `application/octet-stream`)


### Script execution

The Data API allows running scripts as part of many types of requests.

#### Model.execute_script
As of FM18 you can execute scripts directly. To do that for a specific model
use `Model.execute_script`:

```ruby
result = Honeybee.execute_script("My Script", param: "optional parameter")
```

This will return a `Spyke::Result` object containing among other things the
result of the script execution:

```ruby
result.metadata[:script][:after]
# => { result: "oh hi", error: "0" }
```

#### Script options object format

All other script-capable requests take one or more of three possible script
execution options: `script.prerequest`, `script.presort` and plain `script`
(which fmrest-ruby dubs `after` for convenience).

Because of that fmrest-ruby uses a common object format for specifying script options
across multiple methods. That object format is as follows:

```ruby
# Just a string means to execute that `after' script without a parameter
"My Script"

# A 2-elemnent array means [script name, script parameter]
["My Script", "parameter"]

# A hash with keys :prerequest, :presort and/or :after sets those scripts for
{
  prerequest: "My Prerequest Script",
  presort: "My Presort Script",
  after: "My Script"
}

# Using 2-element arrays as objects in the hash allows specifying parameters
{
  prerequest: ["My Prerequest Script", "parameter"],
  presort: ["My Presort Script", "parameter"],
  after: ["My Script", "parameter"]
}
```

#### Script execution on record save, destroy and reload

A record instance's `.save` and `.destroy` methods both accept a `script:`
option to which you can pass a script options object with
[the above format](#script-options-object-format):

```ruby
# Save the record and execute an `after' script called "My Script"
bee.save(script: "My Script")

# Same as above but with an added parameter
bee.save(script: ["My Script", "parameter"])

# Save the record and execute a presort script and an `after' script
bee.save(script: { presort: "My Presort Script", after: "My Script" })

# Destroy the record and execute a prerequest script with a parameter
bee.destroy(script: { prerequest: ["My Prerequest Script", "parameter"] })

# Reload the record and execute a prerequest script with a parameter
bee.reload(script: { prerequest: ["My Prerequest Script", "parameter"] })
```

#### Retrieving script execution results

Every time a request is ran on a model or record instance of a model, a
thread-local `Model.last_request_metadata` attribute is set on that model,
which is a hash containing the results of script executions, if any were
performed, among other metadata.

The results for `:after`, `:prerequest` and `:presort` scripts are stored
separately, under their matching key.

```ruby
bee.save(script: { presort: "My Presort Script", after: "My Script" })

Honeybee.last_request_metadata.script
# => { after: { result: "oh hi", error: "0" }, presort: { result: "lo", error: "0" } }
```

#### Executing scripts through query requests

As mentioned under the [Query API](#query-api) section, you can use the
`.script` query method to specify that you want scripts executed when a query
is performed on that scope.

`.script` takes the same options object specified [above](#script-options-object-format):

```ruby
# Find one Honeybee record executing a presort and after script
Honeybee.script(presort: ["My Presort Script", "parameter"], after: "My Script").first
```

The model class' `.last_request_metadata` will be set in case you need to get the result.

In the case of retrieving multiple results (i.e. via `.find_some`) the
resulting collection will have a `.metadata` attribute method containing the
same metadata hash with script execution results. Note that this does not apply
to retrieving single records, in that case you'll have to use
`.last_request_metadata`.


### Setting global field values

You can call `.set_globals` on any `FmRest::Spyke::Base` model to set glabal
field values on the database that model is configured for.

You can pass it either a hash of fully qualified field names
(table_name::field_name), or 1-level-deep nested hashes, with the outer being a
table name and the inner keys being the field names:

```ruby
Honeybee.set_globals(
  "beeTable::myVar"      => "value",
  "beeTable::myOtherVar" => "also a value"
)

# Equivalent to the above example
Honeybee.set_globals(beeTable: { myVar: "value", myOtherVar: "also a value" })

# Combined
Honeybee.set_globals(
  "beeTable::myVar" => "value",
  beeTable: { myOtherVar: "also a value" }
)
```


## Logging

If using fmrest-ruby + Spyke in a Rails app pretty log output will be set up
for you automatically by Spyke (see [their
README](https://github.com/balvig/spyke#log-output)).

You can also enable simple STDOUT logging (useful for debugging) by passing
`log: true` in the options hash for either
`FmRest.default_connection_settings=` or your models' `fmrest_config=`, e.g.:

```ruby
FmRest.default_connection_settings = {
  host:     "example.com",
  database: "My Database",
  username: "z3r0c00l",
  password: "abc123",
  log:      true
}

# Or in your model
class LoggyBee < FmRest::Spyke::Base
  self.fmrest_config = {
    host:     "example.com",
    database: "My Database",
    username: "...",
    password: "...",
    log:      true
  }
end
```

If you need to set up more complex logging for your models can use the
`faraday` block inside your class to inject your own logger middleware into the
Faraday connection, e.g.:

```ruby
class LoggyBee < FmRest::Spyke::Base
  faraday do |conn|
    conn.response :logger, MyApp.logger, bodies: true
  end
end
```

## API implementation completeness table

FM Data API reference: https://fmhelp.filemaker.com/docs/18/en/dataapi/

| FM 18 Data API feature              | Supported by basic connection | Supported by FmRest::Spyke::Base |
|-------------------------------------|-------------------------------|----------------------------------|
| Log in using HTTP Basic Auth        | Yes                           | Yes                              |
| Log in using OAuth                  | No                            | No                               |
| Log in to an external data source   | No                            | No                               |
| Log in using a FileMaker ID account | No                            | No                               |
| Log out                             | Yes                           | Yes                              |
| Get product information             | Manual*                       | No                               |
| Get database names                  | Manual*                       | No                               |
| Get script names                    | Manual*                       | No                               |
| Get layout names                    | Manual*                       | No                               |
| Get layout metadata                 | Manual*                       | No                               |
| Create a record                     | Manual*                       | Yes                              |
| Edit a record                       | Manual*                       | Yes                              |
| Duplicate a record                  | Manual*                       | No                               |
| Delete a record                     | Manual*                       | Yes                              |
| Get a single record                 | Manual*                       | Yes                              |
| Get a range of records              | Manual*                       | Yes                              |
| Get container data                  | Manual*                       | Yes                              |
| Upload container data               | Manual*                       | Yes                              |
| Perform a find request              | Manual*                       | Yes                              |
| Set global field values             | Manual*                       | Yes
| Run a script                        | Manual*                       | Yes                              |
| Run a script with another request   | Manual*                       | Yes                              |

\* You can manually supply the URL and JSON to a `FmRest` connection.


## Gem development

After checking out the repo, run `bin/setup` to install dependencies. Then, run
`rake spec` to run the tests. You can also run `bin/console` for an interactive
prompt that will allow you to experiment (it will auto-load all fixtures in
spec/fixtures).

To install this gem onto your local machine, run `bundle exec rake install`. To
release a new version, update the version number in `version.rb`, and then run
`bundle exec rake release`, which will create a git tag for the version, push
git commits and tags, and push the `.gem` file to
[rubygems.org](https://rubygems.org).


## Contributing

Bug reports and pull requests are welcome. This project is intended to be a
safe, welcoming space for collaboration, and contributors are expected to
adhere to the [Contributor Covenant](http://contributor-covenant.org) code of
conduct.


## License

The gem is available as open source under the terms of the
[MIT License](https://opensource.org/licenses/MIT).
See [LICENSE.txt](LICENSE.txt).


## Disclaimer

This project is not sponsored by or otherwise affiliated with FileMaker, Inc,
an Apple subsidiary. FileMaker is a trademark of FileMaker, Inc., registered in
the U.S. and other countries.
