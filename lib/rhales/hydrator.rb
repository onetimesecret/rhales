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
    # - Only data declared in <data> or <schema> sections reaches the browser
    # - Creates explicit allowlist like designing a REST API
    # - For <data>: Server-side variable interpolation processes secrets safely
    # - For <schema>: Direct props serialization (no interpolation)
    # - JSON serialization validates data structure
    #
    # ### Process Flow (Schema-based, preferred)
    # 1. Backend provides fully-resolved props to render call
    # 2. Props are directly serialized as JSON
    # 3. Client receives only the declared props
    #
    # ### Process Flow (Data-based, deprecated)
    # 1. Server processes <data> section with full context access
    # 2. Variables like {{user.name}} are interpolated server-side
    # 3. Result is serialized as JSON and sent to client
    # 4. Client receives only the processed, safe data
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
    # ### Example (Data-based, deprecated)
    # ```rue
    # <data window="appData">
    # {
    #   "user_name": "{{user.name}}",           // Safe: just the name
    #   "theme": "{{user.theme_preference}}"    // Safe: just the theme
    # }
    # </data>
    # ```
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

# Process <data> or <schema> section and return JSON string
      def process_data_section
        # Check for schema section first (preferred)
        if @parser.schema_lang
          # Schema section: Direct props serialization
          JSON.generate(@context.client)
        elsif @parser.section('data')
          # Data section: Template interpolation (deprecated)
          data_content = @parser.section('data')

          # Process variable interpolations in the data section
          processed_content = process_data_variables(data_content)

          # Validate and return JSON
          validate_json(processed_content)
          processed_content
        else
          # No hydration section
          '{}'
        end
      rescue JSON::ParserError => ex
        raise JSONSerializationError, "Invalid JSON in data/schema section: #{ex.message}"
      end

      # Get processed data as Ruby hash (for internal use)
      def processed_data_hash
        json_string = process_data_section
        JSON.parse(json_string)
      rescue JSON::ParserError => ex
        raise JSONSerializationError, "Cannot parse processed data as JSON: #{ex.message}"
      end

      private

      # Process variable interpolations in data section
      # Uses Rhales consistently for all template processing
      # Wraps context in JsonAwareContext to auto-convert Ruby objects to JSON
      def process_data_variables(data_content)
        json_context = JsonAwareContext.new(@context)
        rhales = TemplateEngine.new(data_content, json_context)
        rhales.render
      end

      # Context wrapper that automatically converts Ruby objects to JSON in data sections
      class JsonAwareContext
        def initialize(context)
          @context = context
        end

        # Delegate all methods to the wrapped context
        def method_missing(method, *, &)
          @context.send(method, *, &)
        end

        def respond_to_missing?(method, include_private = false)
          @context.respond_to?(method, include_private)
        end

        # Override get method to return JSON-serialized objects
        def get(variable_path)
          value = @context.get(variable_path)

          # Convert Ruby objects to JSON for data sections
          case value
          when Hash, Array
            begin
              value.to_json
            rescue JSON::GeneratorError, SystemStackError => ex
              # Handle serialization errors (circular references, unsupported types, etc.)
              raise JSONSerializationError,
                "Failed to serialize Ruby object to JSON: #{ex.message}. " \
                "Object type: #{value.class}, var path: #{variable_path}..."
            end
          else
            value
          end
        end

        # Alias for compatibility with template engine
        alias resolve_variable get
      end

      # Validate that processed content is valid JSON
      def validate_json(json_string)
        JSON.parse(json_string)
      rescue JSON::ParserError => ex
        raise JSONSerializationError, "Processed data section is not valid JSON: #{ex.message}"
      end

      # Build template path with line number for error reporting
      # (Used by HydrationDataAggregator)
      def build_template_path
        data_node   = @parser.section_node('data')
        line_number = data_node ? data_node.location.start_line : 1

        if @parser.file_path
          "#{@parser.file_path}:#{line_number}"
        else
          "<inline>:#{line_number}"
        end
      end

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
