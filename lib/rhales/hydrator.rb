# lib/rhales/hydrator.rb

require 'json'
require 'securerandom'

module Rhales
    # Data Hydrator for RSFC client-side data injection
    #
    # ## RSFC Security Model: Server-to-Client Security Boundary
    #
    # The Hydrator enforces a critical security boundary between server and client:
    #
    # ### Server Side (Template Rendering)
    # - Templates have FULL server context access (like ERB/HAML)
    # - Can access user objects, database connections, internal APIs
    # - Can access secrets, configuration, authentication state
    # - Can process sensitive business logic
    #
    # ### Client Side (Data Hydration)
    # - Only data declared in <schema> sections reaches the browser
    # - Creates explicit allowlist like designing a REST API
    # - For <schema>: Direct props serialization (no interpolation)
    # - JSON serialization validates data structure
    #
    # ### Process Flow (Schema-based, preferred)
    # 1. Backend provides fully-resolved props to render call
    # 2. Props are directly serialized as JSON
    # 3. Client receives only the declared props
    #
    # ### Example (Schema-based)
    # ```rue
    # <schema lang="js-zod" window="appData">
    # const schema = z.object({
    #   user_name: z.string(),
    #   theme: z.string()
    # });
    # </schema>
    # ```
    # Backend: render('template', user_name: user.name, theme: user.theme_preference)
    #
    #
    # Server template can access {{user.admin?}} and {{internal_config}},
    # but client only gets the declared user_name and theme values.
    #
    # This creates an API-like boundary where data is serialized once and
    # parsed once, enforcing the same security model as REST endpoints.
    #
    # Note: With the new two-pass architecture, the Hydrator's role is
    # greatly simplified. All data merging happens server-side in the
    # HydrationDataAggregator, so this class only handles JSON generation
    # for individual templates (used during the aggregation phase).
    class Hydrator
      class HydrationError < StandardError; end
      class JSONSerializationError < HydrationError; end

      attr_reader :parser, :context, :window_attribute

      def initialize(parser, context)
        @parser           = parser
        @context          = context
        @window_attribute = parser.window_attribute || 'data'
      end

# Process <schema> section and return JSON string
      def process_data_section
        # Check for schema section
        if @parser.schema_lang
          # Schema section: Direct props serialization
          JSON.generate(@context.client)
        else
          # No hydration section
          '{}'
        end
      rescue JSON::ParserError => ex
        raise JSONSerializationError, "Invalid JSON in schema section: #{ex.message}"
      end

      # Get processed data as Ruby hash (for internal use)
      def processed_data_hash
        json_string = process_data_section
        JSON.parse(json_string)
      rescue JSON::ParserError => ex
        raise JSONSerializationError, "Cannot parse processed data as JSON: #{ex.message}"
      end

      private

class << self
# Generate only JSON data (for testing or API endpoints)
        def generate_json(parser, context)
          new(parser, context).process_data_section
        end

        # Generate data hash (for internal processing)
        def generate_data_hash(parser, context)
          new(parser, context).processed_data_hash
        end
      end
    end
end
