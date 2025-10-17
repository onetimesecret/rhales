# lib/rhales/hydration_data_aggregator.rb

require 'json'
require_relative 'template_engine'
require_relative 'errors'

module Rhales
  # HydrationDataAggregator traverses the ViewComposition and executes
  # all <data> and <schema> sections to produce a single, merged JSON structure.
  #
  # This class implements the server-side data aggregation phase of the
  # two-pass rendering model, handling:
  # - Traversal of the template dependency tree
  # - Execution of <data> sections with template interpolation (deprecated)
  # - Direct serialization of props for <schema> sections (preferred)
  # - Merge strategies (deep, shallow, strict)
  # - Collision detection and error reporting
  #
  # The aggregator replaces the HydrationRegistry by performing all
  # data merging in a single, coordinated pass.
  class HydrationDataAggregator
    class JSONSerializationError < StandardError; end

    def initialize(context)
      @context = context
      @window_attributes = {}
      @merged_data = {}
    end

    # Aggregate all hydration data from the view composition
    def aggregate(composition)
      composition.each_document_in_render_order do |template_name, parser|
        process_template(template_name, parser)
      end

      @merged_data
    end

    private

    def process_template(_template_name, parser)
      # Check for schema section first (preferred), then data section (deprecated)
      if parser.schema_lang
        process_schema_section(parser)
      elsif parser.section('data')
        process_data_section_legacy(parser)
      end
    end

    # Process schema section: Direct JSON serialization
    def process_schema_section(parser)
      window_attr = parser.schema_window || 'data'
      merge_strategy = parser.schema_merge_strategy

      # Build template path for error reporting
      template_path = build_template_path_for_schema(parser)

      # Direct serialization of client data (no template interpolation)
      processed_data = @context.client

      # Check for collisions only if the data is not empty
      if @window_attributes.key?(window_attr) && merge_strategy.nil? && !empty_data?(processed_data)
        existing = @window_attributes[window_attr]
        existing_data = @merged_data[window_attr]

        # Only raise collision error if existing data is also not empty
        unless empty_data?(existing_data)
          raise ::Rhales::HydrationCollisionError.new(window_attr, existing[:path], template_path)
        end
      end

      # Merge or set the data
      @merged_data[window_attr] = if @merged_data.key?(window_attr)
        merge_data(
          @merged_data[window_attr],
          processed_data,
          merge_strategy || 'deep',
          window_attr,
          template_path,
        )
      else
        processed_data
                                  end

      # Track the window attribute
      @window_attributes[window_attr] = {
        path: template_path,
        merge_strategy: merge_strategy,
        section_type: :schema,
      }
    end

    # Process data section (deprecated): Template interpolation
    def process_data_section_legacy(parser)
      data_content = parser.section('data')
      return unless data_content

window_attr = parser.window_attribute || 'data'
      merge_strategy = parser.merge_strategy

      # Build template path for error reporting
      template_path = build_template_path(parser)

      # Process the data section with template interpolation
      processed_data = process_data_section_with_interpolation(data_content, parser)

      # Check for collisions only if the data is not empty
      if @window_attributes.key?(window_attr) && merge_strategy.nil? && !empty_data?(processed_data)
        existing = @window_attributes[window_attr]
        existing_data = @merged_data[window_attr]

        # Only raise collision error if existing data is also not empty
        unless empty_data?(existing_data)
          raise ::Rhales::HydrationCollisionError.new(window_attr, existing[:path], template_path)
        end
      end

      # Merge or set the data
      @merged_data[window_attr] = if @merged_data.key?(window_attr)
        merge_data(
          @merged_data[window_attr],
          processed_data,
          merge_strategy || 'deep',
          window_attr,
          template_path,
        )
      else
        processed_data
                                  end

      # Track the window attribute
      @window_attributes[window_attr] = {
        path: template_path,
        merge_strategy: merge_strategy,
        section_type: :data,
      }
    end

    # Process data section with template interpolation (for deprecated <data> sections)
    def process_data_section_with_interpolation(data_content, parser)
      # Create a JSON-aware context wrapper for data sections
      json_context = JsonAwareContext.new(@context)

      # Process template variables in the data section
      processed_content = TemplateEngine.render(data_content, json_context)

      # Parse as JSON
      begin
        JSON.parse(processed_content)
      rescue JSON::ParserError => ex
        template_path = build_template_path(parser)
        raise JSONSerializationError,
          "Invalid JSON in data section at #{template_path}: #{ex.message}\n" \
          "Processed content: #{processed_content[0..200]}..."
      end
    end

    def merge_data(target, source, strategy, window_attr, template_path)
      case strategy
      when 'deep'
        deep_merge(target, source)
      when 'shallow'
        shallow_merge(target, source, window_attr, template_path)
      when 'strict'
        strict_merge(target, source, window_attr, template_path)
      else
        raise ArgumentError, "Unknown merge strategy: #{strategy}"
      end
    end

    def deep_merge(target, source)
      result = target.dup

      source.each do |key, value|
        result[key] = if result.key?(key) && result[key].is_a?(Hash) && value.is_a?(Hash)
          deep_merge(result[key], value)
        else
          value
                      end
      end

      result
    end

    def shallow_merge(target, source, window_attr, template_path)
      result = target.dup

      source.each do |key, value|
        if result.key?(key)
          raise ::Rhales::HydrationCollisionError.new(
            "#{window_attr}.#{key}",
            @window_attributes[window_attr][:path],
            template_path,
          )
        end
        result[key] = value
      end

      result
    end

    def strict_merge(target, source, window_attr, template_path)
      # In strict mode, any collision is an error
      target.each_key do |key|
        next unless source.key?(key)

        raise ::Rhales::HydrationCollisionError.new(
          "#{window_attr}.#{key}",
          @window_attributes[window_attr][:path],
          template_path,
        )
      end

      target.merge(source)
    end

    def build_template_path(parser)
      data_node = parser.section_node('data')
      line_number = data_node ? data_node.location.start_line : 1

      if parser.file_path
        "#{parser.file_path}:#{line_number}"
      else
        "<inline>:#{line_number}"
      end
    end

    def build_template_path_for_schema(parser)
      schema_node = parser.section_node('schema')
      line_number = schema_node ? schema_node.location.start_line : 1

      if parser.file_path
        "#{parser.file_path}:#{line_number}"
      else
        "<inline>:#{line_number}"
      end
    end



    # Check if data is considered empty for collision detection
    def empty_data?(data)
      return true if data.nil?
      return true if data == {}
      return true if data == []
      return true if data.respond_to?(:empty?) && data.empty?

      false
    end
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
end
