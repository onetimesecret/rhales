# lib/rhales/hydration_data_aggregator.rb

require 'json'
require_relative 'template_engine'
require_relative 'errors'

module Rhales
  # HydrationDataAggregator traverses the ViewComposition and executes
  # all <data> sections to produce a single, merged JSON structure.
  #
  # This class implements the server-side data aggregation phase of the
  # two-pass rendering model, handling:
  # - Traversal of the template dependency tree
  # - Execution of <data> sections with full server context
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

    def process_template(template_name, parser)
      data_content = parser.section('data')
      return unless data_content

      window_attr = parser.window_attribute || 'data'
      merge_strategy = parser.merge_strategy

      # Build template path for error reporting
      template_path = build_template_path(parser)

      # Check for collisions
      if @window_attributes.key?(window_attr) && merge_strategy.nil?
        existing = @window_attributes[window_attr]
        raise ::Rhales::HydrationCollisionError.new(window_attr, existing[:path], template_path)
      end

      # Process the data section
      processed_data = process_data_section(data_content, parser)

      # Merge or set the data
      if @merged_data.key?(window_attr)
        @merged_data[window_attr] = merge_data(
          @merged_data[window_attr],
          processed_data,
          merge_strategy || 'deep',
          window_attr,
          template_path
        )
      else
        @merged_data[window_attr] = processed_data
      end

      # Track the window attribute
      @window_attributes[window_attr] = {
        path: template_path,
        merge_strategy: merge_strategy
      }
    end

    def process_data_section(data_content, parser)
      # Process template variables in the data section
      processed_content = TemplateEngine.render(data_content, @context)

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
        if result.key?(key) && result[key].is_a?(Hash) && value.is_a?(Hash)
          result[key] = deep_merge(result[key], value)
        else
          result[key] = value
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
            template_path
          )
        end
        result[key] = value
      end

      result
    end

    def strict_merge(target, source, window_attr, template_path)
      # In strict mode, any collision is an error
      target.each_key do |key|
        if source.key?(key)
          raise ::Rhales::HydrationCollisionError.new(
            "#{window_attr}.#{key}",
            @window_attributes[window_attr][:path],
            template_path
          )
        end
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
  end
end
