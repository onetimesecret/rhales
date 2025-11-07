# lib/rhales/middleware/schema_validator.rb
# frozen_string_literal: true

require 'json_schemer'
require_relative '../utils/json_serializer'

module Rhales
  module Middleware
    # Rack middleware that validates hydration data against JSON Schemas
    #
    # This middleware extracts hydration JSON from HTML responses and validates
    # it against the JSON Schema for the template. In development, it fails
    # loudly on mismatches. In production, it logs warnings but continues serving.
    #
    # @example Basic usage with Rack
    #   use Rhales::Middleware::SchemaValidator,
    #     schemas_dir: './public/schemas',
    #     fail_on_error: ENV['RACK_ENV'] == 'development'
    #
    # @example With Roda
    #   use Rhales::Middleware::SchemaValidator,
    #     schemas_dir: File.expand_path('../public/schemas', __dir__),
    #     fail_on_error: ENV['RACK_ENV'] == 'development',
    #     enabled: true
    #
    # @example Accessing statistics
    #   validator = app.middleware.find { |m| m.is_a?(Rhales::Middleware::SchemaValidator) }
    #   puts validator.stats
    class SchemaValidator
      # Raised when schema validation fails in development mode
      class ValidationError < StandardError; end

      # Initialize the middleware
      #
      # @param app [#call] The Rack application
      # @param options [Hash] Configuration options
      # @option options [String] :schemas_dir Path to JSON schemas directory
      # @option options [Boolean] :fail_on_error Whether to raise on validation errors
      # @option options [Boolean] :enabled Whether validation is enabled
      # @option options [Array<String>] :skip_paths Additional paths to skip validation
      def initialize(app, options = {})
        @app = app
        # Default to public/schemas in implementing project's directory
        @schemas_dir = options.fetch(:schemas_dir, './public/schemas')
        @fail_on_error = options.fetch(:fail_on_error, false)
        @enabled = options.fetch(:enabled, true)
        @skip_paths = options.fetch(:skip_paths, [])
        @schema_cache = {}
        @stats = {
          total_validations: 0,
          total_time_ms: 0,
          failures: 0
        }
      end

      # Process the Rack request
      #
      # @param env [Hash] The Rack environment
      # @return [Array] Rack response tuple [status, headers, body]
      def call(env)
        return @app.call(env) unless @enabled
        return @app.call(env) if skip_validation?(env)

        status, headers, body = @app.call(env)

        # Only validate HTML responses
        content_type = headers['Content-Type']
        return [status, headers, body] unless content_type&.include?('text/html')

        # Get template name from env (set by View)
        template_name = env['rhales.template_name']
        return [status, headers, body] unless template_name

        # Get template path if available (for better error messages)
        template_path = env['rhales.template_path']

        # Load schema for template
        schema = load_schema_cached(template_name)
        return [status, headers, body] unless schema

        # Extract hydration data from response
        html_body = extract_body(body)
        hydration_data = extract_hydration_data(html_body)
        return [status, headers, body] if hydration_data.empty?

        # Validate each hydration block
        start_time = Time.now
        errors = validate_hydration_data(hydration_data, schema, template_name)
        elapsed_ms = ((Time.now - start_time) * 1000).round(2)

        # Update stats
        @stats[:total_validations] += 1
        @stats[:total_time_ms] += elapsed_ms
        @stats[:failures] += 1 if errors.any?

        # Handle errors
        handle_errors(errors, template_name, template_path, elapsed_ms) if errors.any?

        [status, headers, body]
      end

      # Get validation statistics
      #
      # @return [Hash] Statistics including avg_time_ms and success_rate
      def stats
        avg_time = @stats[:total_validations] > 0 ?
          (@stats[:total_time_ms] / @stats[:total_validations]).round(2) : 0

        @stats.merge(
          avg_time_ms: avg_time,
          success_rate: @stats[:total_validations] > 0 ?
            ((@stats[:total_validations] - @stats[:failures]).to_f / @stats[:total_validations] * 100).round(2) : 0
        )
      end

      private

      # Check if validation should be skipped for this request
      def skip_validation?(env)
        path = env['PATH_INFO']

        # Skip static assets, APIs, public files
        return true if path.start_with?('/assets', '/api', '/public')

        # Skip configured custom paths
        return true if @skip_paths.any? { |skip_path| path.start_with?(skip_path) }

        # Skip files with extensions typically not rendered by templates
        return true if path.match?(/\.(css|js|png|jpg|jpeg|gif|svg|ico|woff|woff2|ttf|eot)\z/i)

        false
      end

      # Load and cache JSON schema for template
      def load_schema_cached(template_name)
        @schema_cache[template_name] ||= begin
          schema_path = File.join(@schemas_dir, "#{template_name}.json")

          return nil unless File.exist?(schema_path)

          schema_json = File.read(schema_path)
          schema_hash = JSONSerializer.parse(schema_json)

          # Create JSONSchemer validator
          # Note: json_schemer handles $schema and $id properly
          JSONSchemer.schema(schema_hash)
        rescue JSON::ParserError => e
          warn "Rhales::SchemaValidator: Failed to parse schema for #{template_name}: #{e.message}"
          nil
        rescue StandardError => e
          warn "Rhales::SchemaValidator: Failed to load schema for #{template_name}: #{e.message}"
          nil
        end
      end

      # Extract response body as string
      def extract_body(body)
        if body.respond_to?(:each)
          body.each.to_a.join
        elsif body.respond_to?(:read)
          body.read
        else
          body.to_s
        end
      end

      # Extract hydration JSON blocks from HTML
      #
      # Looks for <script type="application/json" data-window="varName"> tags
      def extract_hydration_data(html)
        hydration_blocks = {}

        # Match script tags with data-window attribute
        html.scan(/<script[^>]*type=["']application\/json["'][^>]*data-window=["']([^"']+)["'][^>]*>(.*?)<\/script>/m) do |window_var, json_content|
          begin
            hydration_blocks[window_var] = JSONSerializer.parse(json_content.strip)
          rescue JSON::ParserError => e
            warn "Rhales::SchemaValidator: Failed to parse hydration JSON for window.#{window_var}: #{e.message}"
          end
        end

        hydration_blocks
      end

      # Validate hydration data against schema
      def validate_hydration_data(hydration_data, schema, template_name)
        errors = []

        hydration_data.each do |window_var, data|
          # Validate data against schema using json_schemer
          begin
            validation_errors = schema.validate(data).to_a

            if validation_errors.any?
              errors << {
                window: window_var,
                template: template_name,
                errors: format_errors(validation_errors)
              }
            end
          rescue StandardError => e
            warn "Rhales::SchemaValidator: Schema validation error for #{template_name}: #{e.message}"
            # Don't add to errors array - this is a schema definition problem, not data problem
          end
        end

        errors
      end

      # Format json_schemer errors for display
      def format_errors(validation_errors)
        validation_errors.map do |error|
          # json_schemer provides detailed error hash
          # Example: { "data" => value, "data_pointer" => "/user/id", "schema" => {...}, "type" => "required", "error" => "..." }

          path = error['data_pointer'] || '/'
          type = error['type']
          schema = error['schema'] || {}
          data = error['data']

          # For type validation errors, format like json-schema did
          # "The property '#/count' of type string did not match the following type: number"
          if schema['type'] && data
            expected = schema['type']
            actual = case data
                     when String then 'string'
                     when Integer, Float then 'number'
                     when TrueClass, FalseClass then 'boolean'
                     when Array then 'array'
                     when Hash then 'object'
                     when NilClass then 'null'
                     else data.class.name.downcase
                     end

            "The property '#{path}' of type #{actual} did not match the following type: #{expected}"
          elsif type == 'required'
            details = error['details'] || {}
            missing = details['missing_keys']&.join(', ') || 'unknown'
            "The property '#{path}' is missing required field(s): #{missing}"
          elsif schema['enum']
            expected = schema['enum'].join(', ')
            "The property '#{path}' must be one of: #{expected}"
          elsif schema['minimum']
            min = schema['minimum']
            "The property '#{path}' must be >= #{min}"
          elsif schema['maximum']
            max = schema['maximum']
            "The property '#{path}' must be <= #{max}"
          elsif type == 'additionalProperties'
            "The property '#{path}' is not defined in the schema and the schema does not allow additional properties"
          else
            # Fallback: use json_schemer's built-in error message
            error['error'] || "The property '#{path}' failed '#{type}' validation"
          end
        end
      end

      # Handle validation errors
      def handle_errors(errors, template_name, template_path, elapsed_ms)
        error_message = build_error_message(errors, template_name, template_path, elapsed_ms)

        if @fail_on_error
          # Development: Fail loudly
          raise ValidationError, error_message
        else
          # Production: Log warning
          warn error_message
        end
      end

      # Build detailed error message
      def build_error_message(errors, template_name, template_path, elapsed_ms)
        msg = ["Schema validation failed for template: #{template_name}"]
        msg << "Template path: #{template_path}" if template_path
        msg << "Validation time: #{elapsed_ms}ms"
        msg << ""

        errors.each do |error|
          msg << "Window variable: #{error[:window]}"
          msg << "Errors:"
          error[:errors].each do |err|
            msg << "  - #{err}"
          end
          msg << ""
        end

        msg << "This means your backend is sending data that doesn't match the contract"
        msg << "defined in the <schema> section of #{template_name}.rue"
        msg << ""
        msg << "To fix:"
        msg << "1. Check the schema definition in #{template_name}.rue"
        msg << "2. Verify the data passed to render('#{template_name}', ...)"
        msg << "3. Ensure types match (string vs number, required fields, etc.)"

        msg.join("\n")
      end
    end
  end
end
