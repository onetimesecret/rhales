# lib/rhales/utils/json_serializer.rb
#
# frozen_string_literal: true

module Rhales
  # Centralized JSON serialization with optional Oj support
  #
  # This module provides a unified interface for JSON operations with automatic
  # Oj optimization when available. Oj is 10-20x faster than stdlib JSON for
  # parsing and 5-10x faster for generation.
  #
  # The serializer backend is determined once at load time for optimal performance.
  # If you want to use Oj, require it before requiring Rhales:
  #
  # @example Ensuring Oj is used
  #   require 'oj'
  #   require 'rhales'
  #
  # @example Basic usage
  #   Rhales::JSONSerializer.dump({ user: 'Alice' })
  #   # => "{\"user\":\"Alice\"}"
  #
  #   Rhales::JSONSerializer.parse('{"user":"Alice"}')
  #   # => {"user"=>"Alice"}
  #
  # @example Pretty printing
  #   Rhales::JSONSerializer.pretty_dump({ user: 'Alice', count: 42 })
  #   # => "{\n  \"user\": \"Alice\",\n  \"count\": 42\n}"
  #
  # @example Check backend
  #   Rhales::JSONSerializer.backend
  #   # => :oj (if available) or :json (stdlib)
  #
  module JSONSerializer
    class << self
      # Serialize Ruby object to JSON string
      #
      # Uses the serializer backend determined at load time (Oj or stdlib JSON).
      #
      # @param obj [Object] Ruby object to serialize
      # @return [String] JSON string (compact format)
      # @raise [TypeError] if object contains non-serializable types
      def dump(obj)
        @json_dumper.call(obj)
      end

      # Serialize Ruby object to pretty-printed JSON string
      #
      # Uses the serializer backend determined at load time (Oj or stdlib JSON).
      # Output is formatted with indentation for readability.
      #
      # @param obj [Object] Ruby object to serialize
      # @return [String] Pretty-printed JSON string with 2-space indentation
      # @raise [TypeError] if object contains non-serializable types
      def pretty_dump(obj)
        @json_pretty_dumper.call(obj)
      end

      # Parse JSON string to Ruby object
      #
      # Uses the parser backend determined at load time (Oj or stdlib JSON).
      # Always returns hashes with string keys (not symbols) for consistency.
      #
      # @param json_string [String] JSON string to parse
      # @return [Object] parsed Ruby object (Hash with string keys)
      # @raise [JSON::ParserError, Oj::ParseError] if JSON is malformed
      def parse(json_string)
        @json_loader.call(json_string)
      end

      # Returns the active JSON backend
      #
      # @return [Symbol] :oj or :json
      def backend
        @backend
      end

      # Reset backend detection (useful for testing)
      #
      # @api private
      def reset!
        detect_backend!
      end

      private

      # Detect and configure JSON backend at load time
      def detect_backend!
        oj_available = begin
          require 'oj'
          true
        rescue LoadError
          false
        end

        if oj_available
          @backend = :oj
          @json_dumper = ->(obj) { Oj.dump(obj, mode: :strict) }
          @json_pretty_dumper = ->(obj) { Oj.dump(obj, mode: :strict, indent: 2) }
          @json_loader = ->(json_string) { Oj.load(json_string, mode: :strict, symbol_keys: false) }
        else
          require 'json'
          @backend = :json
          @json_dumper = ->(obj) { JSON.generate(obj) }
          @json_pretty_dumper = ->(obj) { JSON.pretty_generate(obj) }
          @json_loader = ->(json_string) { JSON.parse(json_string) }
        end
      end
    end

    # Initialize backend on load
    detect_backend!
  end
end
