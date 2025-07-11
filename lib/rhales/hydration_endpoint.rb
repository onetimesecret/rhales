require 'json'
require 'digest'

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
        content: JSON.generate(merged_data),
        content_type: 'application/json',
        headers: json_headers(merged_data)
      }
    rescue JSON::NestingError, JSON::GeneratorError => e
      # Handle JSON serialization errors
      error_data = {
        error: {
          message: "Failed to serialize data to JSON: #{e.message}",
          template: template_name,
          timestamp: Time.now.iso8601
        }
      }

      {
        content: JSON.generate(error_data),
        content_type: 'application/json',
        headers: json_headers(error_data)
      }
    end

    # Render ES module response for modulepreload strategy
    def render_module(template_name, additional_context = {})
      merged_data = process_template_data(template_name, additional_context)

      {
        content: "export default #{JSON.generate(merged_data)};",
        content_type: 'text/javascript',
        headers: module_headers(merged_data)
      }
    end

    # Render JSONP response with callback
    def render_jsonp(template_name, callback_name, additional_context = {})
      merged_data = process_template_data(template_name, additional_context)

      {
        content: "#{callback_name}(#{JSON.generate(merged_data)});",
        content_type: 'application/javascript',
        headers: jsonp_headers(merged_data)
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
      Digest::MD5.hexdigest(JSON.generate(merged_data))
    end

    private

    def process_template_data(template_name, additional_context)
      # Create a minimal context for data processing
      template_context = create_template_context(additional_context)

      # Process template to extract hydration data
      view = View.new(template_name, @config, template_context)
      aggregator = HydrationDataAggregator.new(template_context)

      # Collect data from template and its dependencies
      view.collect_template_dependencies.each do |template_path|
        aggregator.collect_from_template(template_path)
      end

      aggregator.merged_data
    rescue => e
      # Return error structure that can be serialized
      {
        error: {
          message: "Failed to process template data: #{e.message}",
          template: template_name,
          timestamp: Time.now.iso8601
        }
      }
    end

    def create_template_context(additional_context)
      if @context
        # Merge additional context into existing context
        @context.class.new(@context.to_h.merge(additional_context))
      else
        # Create minimal context with just the additional data
        Context.new(additional_context)
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
      headers['ETag'] = %("#{Digest::MD5.hexdigest(JSON.generate(data))}")

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
