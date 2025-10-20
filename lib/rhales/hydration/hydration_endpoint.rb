require 'digest'
require_relative '../utils/json_serializer'

module Rhales
  # Handles API endpoint responses for link-based hydration strategies
  #
  # Provides JSON and ES module endpoints that serve hydration data
  # separately from HTML templates, enabling better caching, parallel
  # loading, and reduced HTML payload sizes.
  #
  # ## Supported Response Formats
  #
  # ### JSON Response (application/json)
  # ```json
  # {
  #   "myData": { "user": "john", "theme": "dark" },
  #   "config": { "apiUrl": "https://api.example.com" }
  # }
  # ```
  #
  # ### ES Module Response (text/javascript)
  # ```javascript
  # export default {
  #   "myData": { "user": "john", "theme": "dark" },
  #   "config": { "apiUrl": "https://api.example.com" }
  # };
  # ```
  #
  # ## Usage
  #
  # ```ruby
  # endpoint = HydrationEndpoint.new(config, context)
  #
  # # JSON response
  # json_response = endpoint.render_json('template_name')
  #
  # # ES Module response
  # module_response = endpoint.render_module('template_name')
  # ```
  class HydrationEndpoint
    def initialize(config, context = nil)
      @config = config
      @context = context
    end

    # Render JSON response for API endpoints
    def render_json(template_name, additional_context = {})
      merged_data = process_template_data(template_name, additional_context)

      {
        content: JSONSerializer.dump(merged_data),
        content_type: 'application/json',
        headers: json_headers(merged_data)
      }
    rescue JSON::NestingError, JSON::GeneratorError, ArgumentError, Encoding::UndefinedConversionError => e
      # Handle JSON serialization errors and encoding issues
      error_data = {
        error: {
          message: "Failed to serialize data to JSON: #{e.message}",
          template: template_name,
          timestamp: Time.now.iso8601
        }
      }

      {
        content: JSONSerializer.dump(error_data),
        content_type: 'application/json',
        headers: json_headers(error_data)
      }
    rescue StandardError => e
      # Handle any other unexpected errors during JSON generation
      error_data = {
        error: {
          message: "Unexpected error during JSON generation: #{e.message}",
          template: template_name,
          timestamp: Time.now.iso8601
        }
      }

      {
        content: JSONSerializer.dump(error_data),
        content_type: 'application/json',
        headers: json_headers(error_data)
      }
    end

    # Render ES module response for modulepreload strategy
    def render_module(template_name, additional_context = {})
      merged_data = process_template_data(template_name, additional_context)

      {
        content: "export default #{JSONSerializer.dump(merged_data)};",
        content_type: 'text/javascript',
        headers: module_headers(merged_data)
      }
    end

    # Render JSONP response with callback
    def render_jsonp(template_name, callback_name, additional_context = {})
      merged_data = process_template_data(template_name, additional_context)

      {
        content: "#{callback_name}(#{JSONSerializer.dump(merged_data)});",
        content_type: 'application/javascript',
        headers: jsonp_headers(merged_data),
      }
    end

    # Check if template data has changed (for ETags)
    def data_changed?(template_name, etag, additional_context = {})
      current_etag = calculate_etag(template_name, additional_context)
      current_etag != etag
    end

    # Get ETag for current template data
    def calculate_etag(template_name, additional_context = {})
      merged_data = process_template_data(template_name, additional_context)
      # Simple ETag based on data hash
      Digest::MD5.hexdigest(JSONSerializer.dump(merged_data))
    end

    private

    def process_template_data(template_name, additional_context)
      # Create a minimal context for data processing
      template_context = create_template_context(additional_context)

      # Process template to extract hydration data
      view = View.new(@context.req, client: {})
      aggregator = HydrationDataAggregator.new(template_context)

      # Build composition to get template dependencies
      composition = view.send(:build_view_composition, template_name)
      composition.resolve!

      # Aggregate data from all templates in the composition
      aggregator.aggregate(composition)
    rescue StandardError => ex
      # Return error structure that can be serialized
      {
        error: {
          message: "Failed to process template data: #{ex.message}",
          template: template_name,
          timestamp: Time.now.iso8601,
        }
      }
    end

    def create_template_context(additional_context)
      if @context
        # Merge additional context into existing context by reconstructing with merged props
        merged_props = @context.client.merge(additional_context)
        @context.class.for_view(@context.req, @context.locale, **merged_props)
      else
        # Create minimal context with just the additional data
        Context.minimal(client: additional_context)
      end
    end

    def json_headers(data)
      headers = {
        'Content-Type' => 'application/json',
        'Cache-Control' => cache_control_header,
        'Vary' => 'Accept, Accept-Encoding'
      }

      # Add CORS headers if enabled
      if cors_enabled?
        headers.merge!(cors_headers)
      end

      # Add ETag for caching
      headers['ETag'] = %("#{Digest::MD5.hexdigest(JSONSerializer.dump(data))}")

      headers
    end

    def module_headers(data)
      headers = json_headers(data)
      headers['Content-Type'] = 'text/javascript'
      headers
    end

    def jsonp_headers(data)
      headers = json_headers(data)
      headers['Content-Type'] = 'application/javascript'
      headers
    end

    def cache_control_header
      if @config.hydration.api_cache_enabled
        "public, max-age=#{@config.hydration.api_cache_ttl || 300}"
      else
        "no-cache, no-store, must-revalidate"
      end
    end

    def cors_enabled?
      @config.hydration.cors_enabled || false
    end

    def cors_headers
      {
        'Access-Control-Allow-Origin' => @config.hydration.cors_origin || '*',
        'Access-Control-Allow-Methods' => 'GET, HEAD, OPTIONS',
        'Access-Control-Allow-Headers' => 'Accept, Accept-Encoding, Authorization',
        'Access-Control-Max-Age' => '86400'
      }
    end
  end
end
