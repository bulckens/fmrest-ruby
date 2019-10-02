# frozen_string_literal: true

module FmRest
  module V1
    module Paths
      def session_path(token = nil)
        url = "sessions"
        url += "/#{token}" if token
        url
      end

      def record_path(layout, id = nil)
        url = "layouts/#{ERB::Util.url_encode(layout.to_s)}/records"
        url += "/#{id}" if id
        url
      end

      def container_field_path(layout, id, field_name, field_repetition = 1)
        url = record_path(layout, id)
        url += "/containers/#{ERB::Util.url_encode(field_name.to_s)}"
        url += "/#{field_repetition}" if field_repetition
        url
      end

      def find_path(layout)
        "layouts/#{ERB::Util.url_encode(layout.to_s)}/_find"
      end

      def globals_path
        "globals"
      end
    end
  end
end
