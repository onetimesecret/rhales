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
    # - Only data declared in <data> section reaches the browser
    # - Creates explicit allowlist like designing a REST API
    # - Server-side variable interpolation processes secrets safely
    # - JSON serialization validates data structure
    #
    # ### Process Flow
    # 1. Server processes <data> section with full context access
    # 2. Variables like {{user.name}} are interpolated server-side
    # 3. Result is serialized as JSON and sent to client
    # 4. Client receives only the processed, safe data
    #
    # ### Example
    # ```rue
    # <data>
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
    class Hydrator
      class HydrationError < StandardError; end
      class JSONSerializationError < HydrationError; end

      attr_reader :parser, :context, :window_attribute, :unique_id

      def initialize(parser, context)
        @parser           = parser
        @context          = context
        @window_attribute = parser.window_attribute || 'data'
        @unique_id        = generate_unique_id
      end

      # Generate the complete hydration HTML (JSON script + hydration script)
      def generate_hydration_html
        register_window_attribute
        json_script + "\n" + hydration_script
      end

      # Generate just the JSON script element
      def json_script
        json_data = process_data_section

        <<~HTML.strip
          <script id="#{script_element_id}" type="application/json">#{json_data}</script>
        HTML
      end

      # Generate just the hydration script
      def hydration_script
        nonce_attr     = nonce_attribute
        merge_strategy = @parser.merge_strategy

        if merge_strategy
          <<~HTML.strip
            <script#{nonce_attr}>
            #{merge_functions_js}
            var newData = JSON.parse(document.getElementById('#{script_element_id}').textContent);
            window.#{@window_attribute} = #{merge_strategy}_merge(window.#{@window_attribute} || {}, newData);
            </script>
          HTML
        else
          <<~HTML.strip
            <script#{nonce_attr}>
            window.#{@window_attribute} = JSON.parse(document.getElementById('#{script_element_id}').textContent);
            </script>
          HTML
        end
      end

      # Process <data> section and return JSON string
      def process_data_section
        data_content = @parser.section('data')
        return '{}' unless data_content

        # Process variable interpolations in the data section
        processed_content = process_data_variables(data_content)

        # Validate and return JSON
        validate_json(processed_content)
        processed_content
      rescue JSON::ParserError => ex
        raise JSONSerializationError, "Invalid JSON in data section: #{ex.message}"
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
      def process_data_variables(data_content)
        rhales = TemplateEngine.new(data_content, @context)
        rhales.render
      end

      # Validate that processed content is valid JSON
      def validate_json(json_string)
        JSON.parse(json_string)
      rescue JSON::ParserError => ex
        raise JSONSerializationError, "Processed data section is not valid JSON: #{ex.message}"
      end

      # Generate unique ID for script element
      def generate_unique_id
        "rsfc-data-#{SecureRandom.hex(8)}"
      end

      # Get script element ID
      def script_element_id
        @unique_id
      end

      # Get nonce attribute if available
      def nonce_attribute
        nonce = @context.get('nonce')
        nonce ? " nonce=\"#{nonce}\"" : ''
      end

      # Register window attribute with collision detection
      def register_window_attribute
        # Only register if we have a data section
        return unless @parser.section('data')

        # Get template path with line number where data tag is defined
        template_path = build_template_path

        # Get merge strategy from parser
        merge_strategy = @parser.merge_strategy

        # Register with HydrationRegistry - will raise on collision
        HydrationRegistry.register(@window_attribute, template_path, merge_strategy)
      end

      # Build template path with line number for error reporting
      def build_template_path
        data_node   = @parser.section_node('data')
        line_number = data_node ? data_node.location.start_line : 1

        if @parser.file_path
          "#{@parser.file_path}:#{line_number}"
        else
          "<inline>:#{line_number}"
        end
      end

      # JavaScript merge functions for different strategies
      def merge_functions_js
        <<~JS.strip
          function shallow_merge(target, source) {
            var result = {};
            for (var key in target) {
              if (target.hasOwnProperty(key)) {
                result[key] = target[key];
              }
            }
            for (var key in source) {
              if (source.hasOwnProperty(key)) {
                if (target.hasOwnProperty(key)) {
                  throw new Error('Shallow merge conflict: key "' + key + '" exists in both objects');
                }
                result[key] = source[key];
              }
            }
            return result;
          }

          function deep_merge(target, source) {
            var result = {};
            for (var key in target) {
              if (target.hasOwnProperty(key)) {
                result[key] = target[key];
              }
            }
            for (var key in source) {
              if (source.hasOwnProperty(key)) {
                if (target.hasOwnProperty(key)) {
                  if (typeof target[key] === 'object' && target[key] !== null &&
                      typeof source[key] === 'object' && source[key] !== null &&
                      !Array.isArray(target[key]) && !Array.isArray(source[key])) {
                    result[key] = deep_merge(target[key], source[key]);
                  } else {
                    result[key] = source[key]; // Last wins
                  }
                } else {
                  result[key] = source[key];
                }
              }
            }
            return result;
          }

          function strict_merge(target, source) {
            var result = {};
            for (var key in target) {
              if (target.hasOwnProperty(key)) {
                result[key] = target[key];
              }
            }
            for (var key in source) {
              if (source.hasOwnProperty(key)) {
                if (target.hasOwnProperty(key)) {
                  if (typeof target[key] === 'object' && target[key] !== null &&
                      typeof source[key] === 'object' && source[key] !== null &&
                      !Array.isArray(target[key]) && !Array.isArray(source[key])) {
                    result[key] = strict_merge(target[key], source[key]);
                  } else {
                    throw new Error('Strict merge conflict: key "' + key + '" exists in both objects');
                  }
                } else {
                  result[key] = source[key];
                }
              }
            }
            return result;
          }
        JS
      end

      class << self
        # Convenience method to generate hydration HTML
        def generate(parser, context)
          new(parser, context).generate_hydration_html
        end

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
