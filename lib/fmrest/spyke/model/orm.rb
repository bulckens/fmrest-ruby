require "fmrest/spyke/relation"

module FmRest
  module Spyke
    module Model
      module Orm
        extend ::ActiveSupport::Concern

        included do
          # Allow overriding FM's default limit (by default it's 100)
          class_attribute :default_limit, instance_accessor: false, instance_predicate: false

          class_attribute :default_sort, instance_accessor: false, instance_predicate: false

          alias :original_save :save
          private :original_save
          include SaveMethods
        end

        class_methods do
          # Methods delegated to FmRest::Spyke::Relation
          delegate :limit, :offset, :sort, :query, :portal, to: :all

          def all
            # Use FmRest's Relation insdead of Spyke's vanilla one
            current_scope || Relation.new(self, uri: uri)
          end

          # Extended fetch to allow properly setting limit, offset and other
          # options, as well as using the appropriate HTTP method/URL depending
          # on whether there's a query present in the current scope, e.g.:
          #
          #     Person.query(first_name: "Stefan").fetch # POST .../_find
          #
          def fetch
            if current_scope.has_query?
              scope = extend_scope_with_fm_params(current_scope, prefixed: false)
              scope = scope.where(query: scope.query_params)
              scope = scope.with(FmRest::V1::find_path(layout))
            else
              scope = extend_scope_with_fm_params(current_scope, prefixed: true)
            end

            previous, self.current_scope = current_scope, scope
            current_scope.has_query? ? scoped_request(:post) : super
          ensure
            self.current_scope = previous
          end

          # API-error-raising version of #create
          #
          def create!(attributes = {})
            new(attributes).tap(&:save!)
          end

          private

          def extend_scope_with_fm_params(scope, prefixed: false)
            prefix = prefixed ? "_" : nil

            where_options = {}

            where_options["#{prefix}limit"] = scope.limit_value if scope.limit_value
            where_options["#{prefix}offset"] = scope.offset_value if scope.offset_value

            if scope.sort_params.present? && scope.limit_value != 1
              where_options["#{prefix}sort"] =
                prefixed ? scope.sort_params.to_json : scope.sort_params
            end

            if scope.portal_params.present?
              where_options["portal"] =
                prefixed ? scope.portal_params.to_json : scope.portal_params
            end

            scope.where(where_options)
          end
        end

        # We want #save and #save! included after the #original_save alias is
        # defined, so we put them in their own separate mixin
        #
        module SaveMethods
          # Saves the model but raises an exception if there's an API error
          # (raised by FmRest::V1::RaiseErrors)
          #
          def save!(options = {})
            if options[:validate] == false || valid?
              original_save
              return true
            end

            false
          end

          def save(options = {})
            save!(options)
          rescue APIError::ValidationError
            false
          end
        end

        # API-error-raising version of #update
        #
        def update!(new_attributes)
          self.attributes = new_attributes
          save!
        end
      end
    end
  end
end
