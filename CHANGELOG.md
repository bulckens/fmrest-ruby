## Changelog

### 0.10.0

* Added `FmRest::StringDateAwareness` module to correct some issues when using
  `FmRest::StringDate`
* Added basic timezones support
* Deprecated `class < FmRest::Spyke::Base(config_hash)` syntax in favor of
  using `self.fmrest_config=`

### 0.9.0

* Added `FmRest::Spyke::Base.set_globals`

### 0.8.0

* Improved metadata when using `FmRest::Spyke::Model`. Metadata now uses
  Struct/OpenStruct, so properties are accessible through `.property`, as well
  as `[:property]`
* Added batch-finders `.find_in_batches` and `.find_each` for
* `FmRest::Spyke::Base`

### 0.7.1

* Made sure `Model.find_one` and `Model.find_some` work without needing to call
  `Model.all` in between

### 0.7.0

* Added date coercion feature

### 0.6.0

* Implemented session logout
  ([#16](https://github.com/beezwax/fmrest-ruby/issues/16))

### 0.5.2

* Improved support for legacy ActiveModel 4.x

### 0.5.1

* Alias `:username` option as `:account_name` for ginjo-rfm gem
  cross-compatibility

### 0.5.0

* Much improved script execution support
  ([#20](https://github.com/beezwax/fmrest-ruby/issues/20))
* Fixed bug when setting `default_limi` and trying to find a record
  ([35](https://github.com/beezwax/fmrest-ruby/issues/35))

### 0.4.1

* Prevent raising an exception when a /\_find request yields no results
  ([#33](https://github.com/beezwax/fmrest-ruby/issues/33) and
  [#34](https://github.com/beezwax/fmrest-ruby/issues/34))

### 0.4.0

* Implement ability to set limit and offset for portals
* Implement disabling and requesting all portals

### 0.3.3

* Fix encoding of paths for layouts with brackets in them (e.g. `"\[Very Ugly\]
  Layout"`)
* Raise an error if `"id"` is assigned as an attribute on a model, as it's
  currently a reserved method name by Spyke

### 0.3.2

* Fix support for ActiveSupport < 5.2
  ([#27](https://github.com/beezwax/fmrest-ruby/issues/27))

### 0.3.0

* Add Moneta token store

### 0.2.5

* Fix crash in `fetch_container_data` when no proxy options were set

### 0.2.4

* Use `String#=~` instead of `String#match?` for Ruby <2.4 compatibility (Fixes
  [#26](https://github.com/beezwax/fmrest-ruby/issues/26))
* Deprecate `FmRest.config` in favor of `FmRest.default_connection_settings`
* Honor Faraday SSL and proxy settings when fetching container files
