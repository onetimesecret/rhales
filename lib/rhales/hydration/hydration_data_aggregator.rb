# lib/rhales/hydration_data_aggregator.rb
#
# frozen_string_literal: true

require 'json'
require_relative '../core/template_engine'
require_relative '../errors'

module Rhales
  # HydrationDataAggregator traverses the ViewComposition and executes
  # all <schema> sections to produce a single, merged JSON structure.
  #
  # This class implements the server-side data aggregation phase of the
  # two-pass rendering model, handling:
  # - Traversal of the template dependency tree
  # - Direct serialization of props for <schema> sections
  # - Merge strategies (deep, shallow, strict)
  # - Collision detection and error reporting
  #
  # The aggregator replaces the HydrationRegistry by performing all
  # data merging in a single, coordinated pass.
  class HydrationDataAggregator
    include Rhales::Utils::LoggingHelpers

    class JSONSerializationError < StandardError; end

    def initialize(context)
      @context = context
      @window_attributes = {}
      @merged_data = {}
      @schema_cache = {}
      @schemas_dir = File.join(Dir.pwd, 'public/schemas')
    end

    # Aggregate all hydration data from the view composition
    def aggregate(composition)
      log_timed_operation(Rhales.logger, :debug, 'Schema aggregation started',
        template_count: composition.template_names.size
      ) do
        composition.each_document_in_render_order do |template_name, parser|
          process_template(template_name, parser)
        end

        @merged_data
      end
    end

    private

    # Log hydration schema mismatch using configured format
    def log_hydration_mismatch(template_path, window_attr, expected, actual, missing, extra, data_size)
      format = Rhales.config.hydration_mismatch_format || :compact

      formatter = case format
      when :sidebyside
        format_sidebyside(template_path, window_attr, expected, actual, missing, extra, data_size)
      when :multiline
        format_multiline(template_path, window_attr, expected, actual, missing, extra, data_size)
      when :compact
        format_compact(template_path, window_attr, expected, actual, missing, extra, data_size)
      when :json
        format_json(template_path, window_attr, expected, actual, missing, extra, data_size)
      else
        raise ArgumentError, "Unknown hydration_mismatch_format: #{format}. Valid: :compact, :multiline, :sidebyside, :json"
      end

      Rhales.logger.warn formatter
    end

    # Format: Side-by-side comparison (most visual, for development)
    def format_sidebyside(template_path, window_attr, expected, actual, missing, extra, data_size)
      # Determine authority: schema (default) or data
      authority = Rhales.config.hydration_authority || :schema

      lines = []
      lines << 'Hydration schema mismatch'
      lines << "  Template: #{template_path}"
      lines << "  Window: #{window_attr} (#{data_size} keys)"
      lines << ''

      if authority == :schema
        # Schema is correct, data needs fixing
        lines << '  Schema (correct) │ Data (fix)'
        lines << '  ─────────────────┼────────────'

        # Show all expected keys with their status
        expected.each do |key|
          lines << if actual.include?(key)
            "  #{key.ljust(17)}│ ✓ #{key}"
          else
            "  #{key.ljust(17)}│ ✗ missing  ← add to data source"
                   end
        end

        # Show extra keys that shouldn't be in data
        extra.each do |key|
          lines << "  (not in schema)  │ ✗ #{key}  ← remove from data source"
        end
      else
        # Data is correct, schema needs fixing
        lines << '  Schema (fix)     │ Data (correct)'
        lines << '  ─────────────────┼───────────────'

        # Show all actual keys with their status
        actual.each do |key|
          lines << if expected.include?(key)
            "  #{key.ljust(17)}│ ✓ #{key}"
          else
            "  [missing]        │ ✓ #{key}  ← add to schema"
                   end
        end

        # Show keys in schema but not in data
        missing.each do |key|
          lines << "  #{key.ljust(17)}│ (not in data)  ← remove from schema"
        end
      end

      lines.join("\n")
    end

    # Format: Multi-line with visual indicators (balanced)
    def format_multiline(template_path, window_attr, expected, actual, missing, extra, data_size)
      # Check if order changed (same keys, different positions)
      order_changed = (expected.to_set == actual.to_set) && (expected != actual)

      # Find keys that moved position
      moved_keys = if order_changed
        (expected & actual).select do |k|
          expected.index(k) != actual.index(k)
        end
      else
        []
      end

      lines = []
      lines << 'Hydration schema mismatch'
      lines << "  Template: #{template_path}"
      lines << "  Window: #{window_attr}"
      lines << "  Data size: #{data_size}"

      if missing.any?
        lines << "  ✗ Schema expects (#{missing.size}): #{missing.join(', ')}"
      end

      if extra.any?
        lines << "  + Data provides (#{extra.size}): #{extra.join(', ')}"
      end

      if moved_keys.any?
        lines << "  ↔ Order changed (#{moved_keys.size}): #{moved_keys.join(', ')}"
      end

      lines.join("\n")
    end

    # Format: Single line compact (for production)
    def format_compact(template_path, window_attr, _expected, _actual, missing, extra, data_size)
      parts = []
      parts << "#{missing.size} missing" if missing.any?
      parts << "#{extra.size} extra" if extra.any?

      summary = parts.join(', ')
      metadata = {
        template: template_path,
        window_attribute: window_attr,
        missing_keys: missing,
        extra_keys: extra,
        client_data_size: data_size,
      }

      # Use existing metadata formatter
      metadata_str = metadata.map do |k, v|
        "#{k}=#{format_metadata_value(v)}"
      end.join(' ')

      "Schema mismatch (#{summary}): #{metadata_str}"
    end

    # Format: JSON (for structured logging systems)
    def format_json(template_path, window_attr, expected, actual, missing, extra, data_size)
      require 'json'

      authority = Rhales.config.hydration_authority || :schema

      # Check if order changed
      order_changed = (expected.to_set == actual.to_set) && (expected != actual)
      moved_keys = if order_changed
        (expected & actual).select { |k| expected.index(k) != actual.index(k) }
      else
        []
      end

      data = {
        event: 'hydration_schema_mismatch',
        template: template_path,
        window_attribute: window_attr,
        authority: authority,
        schema: {
          expected_keys: expected,
          key_count: expected.size,
        },
        data: {
          actual_keys: actual,
          key_count: data_size,
        },
        diff: {
          missing_keys: missing,
          missing_count: missing.size,
          extra_keys: extra,
          extra_count: extra.size,
          order_changed: order_changed,
          moved_keys: moved_keys,
        },
      }

      JSON.generate(data)
    end

    # Format values for compact metadata output
    def format_metadata_value(value)
      case value
      when Array
        if value.empty?
          '[]'
        else
          "[#{value.join(', ')}]"
        end
      when String
        value.include?(' ') ? "\"#{value}\"" : value
      else
        value.to_s
      end
    end

    def process_template(template_name, parser)
      # Process schema section
      if parser.schema_lang
        log_timed_operation(Rhales.logger, :debug, 'Schema validation',
          template: template_name,
          schema_lang: parser.schema_lang
        ) do
          process_schema_section(template_name, parser)
        end
      end
    end

    # Process schema section: Direct JSON serialization
    def process_schema_section(template_name, parser)
      window_attr = parser.schema_window || 'data'
      merge_strategy = parser.schema_merge_strategy

      # Extract client data for validation
      client_data = @context.client || {}
      schema_content = parser.section('schema')
      expected_keys = extract_expected_keys(template_name, schema_content) if schema_content

      # Build template path for error reporting
      template_path = build_template_path_for_schema(parser)

      # Log schema validation details
      if expected_keys && expected_keys.any?
        actual_keys = client_data.keys.map(&:to_s)
        missing_keys = expected_keys - actual_keys
        extra_keys = actual_keys - expected_keys

        if missing_keys.any? || extra_keys.any?
          log_hydration_mismatch(
            Rhales.pretty_path(template_path),
            window_attr,
            expected_keys,
            actual_keys,
            missing_keys,
            extra_keys,
            client_data.size,
          )
        else
          log_with_metadata(Rhales.logger, :debug, 'Schema validation passed',
            template: Rhales.pretty_path(template_path),
            window_attribute: window_attr,
            key_count: expected_keys.size,
            client_data_size: client_data.size
          )
        end
      end

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

    # Extract expected keys using hybrid approach
    #
    # Tries to load pre-generated JSON schema first (reliable, handles all Zod patterns).
    # Falls back to regex parsing for development (before schemas are generated).
    #
    # To generate JSON schemas, run: rake rhales:schema:generate
    def extract_expected_keys(template_name, schema_content)
      # Try JSON schema first (reliable, comprehensive)
      keys = extract_keys_from_json_schema(template_name)
      if keys&.any?
        log_with_metadata(Rhales.logger, :debug, 'Schema keys extracted from JSON schema',
          template: template_name, key_count: keys.size, method: 'json_schema'
        )
        return keys
      end

      # Fall back to regex (development, before schemas generated)
      keys = extract_keys_from_zod_regex(schema_content)
      if keys.any?
        log_with_metadata(Rhales.logger, :debug, 'Schema keys extracted from Zod regex',
          template: template_name, key_count: keys.size, method: 'regex_fallback',
          note: 'Run rake rhales:schema:generate for reliable validation'
        )
      end

      keys
    end

    # Extract keys from pre-generated JSON schema (preferred method)
    def extract_keys_from_json_schema(template_name)
      schema = load_schema_cached(template_name)
      return nil unless schema

      # Extract all properties from JSON schema
      properties = schema.dig('properties') || {}
      properties.keys
    rescue StandardError => ex
      log_with_metadata(Rhales.logger, :debug, 'JSON schema loading failed',
        template: template_name, error: ex.message
      )
      nil
    end

    # Load and cache JSON schema from disk
    def load_schema_cached(template_name)
      @schema_cache[template_name] ||= begin
        schema_path = File.join(@schemas_dir, "#{template_name}.json")
        return nil unless File.exist?(schema_path)

        JSON.parse(File.read(schema_path))
      rescue JSON::ParserError, Errno::ENOENT => ex
        log_with_metadata(Rhales.logger, :debug, 'Schema file error',
          template: template_name, path: schema_path, error: ex.class.name
        )
        nil
      end
    end

    # Extract keys from Zod schema using regex (fallback method)
    #
    # NOTE: This is a basic implementation that only matches simple patterns like:
    #   fieldName: z.string()
    #
    # It will miss:
    # - Nested object literals: settings: { theme: z.enum([...]) }
    # - Complex compositions and unions
    # - Multiline definitions
    #
    # For reliable validation, generate JSON schemas with: rake rhales:schema:generate
    def extract_keys_from_zod_regex(schema_content)
      return [] unless schema_content

      keys = []
      schema_content.scan(/(\w+):\s*z\./) do |match|
        keys << match[0]
      end
      keys
    rescue StandardError => ex
      log_with_metadata(Rhales.logger, :debug, 'Regex key extraction failed',
        error: ex.message,
        schema_preview: schema_content[0..100]
      )
      []
    end
  end
end
