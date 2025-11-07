# lib/rhales/middleware/json_responder.rb
#
# frozen_string_literal: true

require_relative '../utils/json_serializer'

module Rhales
  module Middleware
    # Rack middleware that returns hydration data as JSON when Accept: application/json
    #
    # When a request has Accept: application/json header, this middleware
    # intercepts the response and returns just the hydration data as JSON
    # instead of rendering the full HTML template.
    #
    # This enables:
    # - API clients to fetch data from the same endpoints
    # - Testing hydration data without parsing HTML
    # - Development inspection of data flow
    # - Mobile/native clients using the same routes
    #
    # @example Basic usage with Rack
    #   use Rhales::Middleware::JsonResponder,
    #     enabled: true,
    #     include_metadata: false
    #
    # @example With Roda
    #   use Rhales::Middleware::JsonResponder,
    #     enabled: ENV['RACK_ENV'] != 'production',
    #     include_metadata: ENV['RACK_ENV'] == 'development'
    #
    # @example Response format (single window)
    #   GET /dashboard
    #   Accept: application/json
    #
    #   {
    #     "user": {"id": 1, "name": "Alice"},
    #     "authenticated": true
    #   }
    #
    # @example Response format (multiple windows)
    #   {
    #     "appData": {"user": {...}},
    #     "config": {"theme": "dark"}
    #   }
    #
    # @example Response with metadata (development)
    #   {
    #     "template": "dashboard",
    #     "data": {"user": {...}}
    #   }
    class JsonResponder
      # Initialize the middleware
      #
      # @param app [#call] The Rack application
      # @param options [Hash] Configuration options
      # @option options [Boolean] :enabled Whether JSON responses are enabled (default: true)
      # @option options [Boolean] :include_metadata Whether to include metadata in responses (default: false)
      def initialize(app, options = {})
        @app = app
        @enabled = options.fetch(:enabled, true)
        @include_metadata = options.fetch(:include_metadata, false)
      end

      # Process the Rack request
      #
      # @param env [Hash] The Rack environment
      # @return [Array] Rack response tuple [status, headers, body]
      def call(env)
        return @app.call(env) unless @enabled
        return @app.call(env) unless accepts_json?(env)

        # Get the response from the app
        status, headers, body = @app.call(env)

        # Only process successful HTML responses
        return [status, headers, body] unless status == 200
        return [status, headers, body] unless html_response?(headers)

        # Extract hydration data from HTML
        html_body = extract_body(body)
        hydration_data = extract_hydration_data(html_body)

        # Return empty object if no hydration data found
        if hydration_data.empty?
          return json_response({}, env)
        end

        # Build response data
        response_data = if @include_metadata
          {
            template: env['rhales.template_name'],
            data: hydration_data
          }
        else
          # Flatten if single window, or return all windows
          hydration_data.size == 1 ? hydration_data.values.first : hydration_data
        end

        json_response(response_data, env)
      end

      private

      # Check if request accepts JSON
      #
      # Parses Accept header and checks for application/json.
      # Handles weighted preferences (e.g., "application/json;q=0.9")
      #
      # @param env [Hash] Rack environment
      # @return [Boolean] true if application/json is accepted
      def accepts_json?(env)
        accept = env['HTTP_ACCEPT']
        return false unless accept

        # Check if application/json is requested
        # Handle weighted preferences (e.g., "application/json;q=0.9")
        accept.split(',').any? do |type|
          type.strip.start_with?('application/json')
        end
      end

      # Check if response is HTML
      #
      # @param headers [Hash] Response headers
      # @return [Boolean] true if Content-Type is text/html
      def html_response?(headers)
        # Support both uppercase and lowercase header names for compatibility
        content_type = headers['content-type'] || headers['Content-Type']
        content_type && content_type.include?('text/html')
      end

      # Extract response body as string
      #
      # Handles different Rack body types (Array, IO, String)
      #
      # @param body [Array, IO, String] Rack response body
      # @return [String] Body content as string
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
      # and parses their JSON content. Returns a hash keyed by window variable name.
      #
      # @param html [String] HTML response body
      # @return [Hash] Hydration data keyed by window variable name
      def extract_hydration_data(html)
        hydration_blocks = {}

        # Match script tags with data-window attribute
        html.scan(/<script[^>]*type=["']application\/json["'][^>]*data-window=["']([^"']+)["'][^>]*>(.*?)<\/script>/m) do |window_var, json_content|
          begin
            hydration_blocks[window_var] = JSONSerializer.parse(json_content.strip)
          rescue JSON::ParserError => e
            # Skip malformed JSON blocks
            warn "Rhales::JsonResponder: Failed to parse hydration JSON for window.#{window_var}: #{e.message}"
          end
        end

        hydration_blocks
      end

      # Build JSON response
      #
      # @param data [Hash, Array, Object] Response data
      # @param env [Hash] Rack environment
      # @return [Array] Rack response tuple
      def json_response(data, env)
        json_body = JSONSerializer.dump(data)

        [
          200,
          {
            'content-type' => 'application/json',
            'content-length' => json_body.bytesize.to_s,
            'cache-control' => 'no-cache'
          },
          [json_body]
        ]
      end
    end
  end
end
