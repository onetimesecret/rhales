# lib/rhales/schema_generator.rb
#
# frozen_string_literal: true

require 'open3'
require 'tempfile'
require 'fileutils'
require_relative 'schema_extractor'
require_relative 'json_serializer'

module Rhales
  # Generates JSON Schemas from Zod schemas using TypeScript execution
  #
  # This class uses pnpm exec tsx to execute Zod schema code and convert it
  # to JSON Schema format. The generated schemas are saved to disk for use
  # by the validation middleware.
  #
  # Usage:
  #   generator = SchemaGenerator.new(
  #     templates_dir: './templates',
  #     output_dir: './public/schemas'
  #   )
  #   results = generator.generate_all
  class SchemaGenerator
    class GenerationError < StandardError; end

    attr_reader :templates_dir, :output_dir

    # @param templates_dir [String] Directory containing .rue files
    # @param output_dir [String] Directory to save generated JSON schemas
    #   Defaults to './public/schemas' (implementing project's public directory)
    def initialize(templates_dir:, output_dir: nil)
      @templates_dir = File.expand_path(templates_dir)

      # Smart default: place schemas in public/schemas relative to current working directory
      # This ensures schemas are generated in the implementing project, not the gem directory
      @output_dir = if output_dir
        File.expand_path(output_dir)
      else
        # Default to public/schemas in current working directory
        File.expand_path('./public/schemas')
      end

      validate_setup!
      ensure_output_directory!
    end

    # Generate JSON Schemas for all templates with <schema> sections
    #
    # @return [Hash] Generation results with stats
    def generate_all
      extractor = SchemaExtractor.new(@templates_dir)
      schemas = extractor.extract_all

      if schemas.empty?
        return {
          success: true,
          generated: 0,
          failed: 0,
          message: 'No schemas found in templates'
        }
      end

      results = {
        success: true,
        generated: 0,
        failed: 0,
        errors: []
      }

      schemas.each do |schema_info|
        begin
          generate_schema(schema_info)
          results[:generated] += 1
          puts "✓ Generated schema for: #{schema_info[:template_name]}"
        rescue => e
          results[:failed] += 1
          results[:success] = false
          source_info = schema_info[:src] ? " (from #{schema_info[:src]})" : ""
          error_msg = "Failed to generate schema for #{schema_info[:template_name]}#{source_info}: #{e.message}"
          results[:errors] << error_msg
          warn error_msg
        end
      end

      results
    end

    # Generate JSON Schema for a single template
    #
    # @param schema_info [Hash] Schema information from SchemaExtractor
    # @return [Hash] Generated JSON Schema
    def generate_schema(schema_info)
      # Create temp file in project directory so Node.js can resolve modules
      temp_dir = File.join(Dir.pwd, 'tmp')
      FileUtils.mkdir_p(temp_dir) unless Dir.exist?(temp_dir)

      temp_file = Tempfile.new(['schema', '.mts'], temp_dir)
      bundled_file = nil

      begin
        # Write TypeScript script - use import mode for external schemas when configured
        if use_tsx_import_mode?(schema_info)
          script, bundled_file = build_typescript_import_script(schema_info)
        else
          script = build_typescript_script(schema_info)
        end
        temp_file.write(script)
        temp_file.close

        # Execute with tsx via pnpm, optionally with tsconfig
        stdout, stderr, status = execute_tsx(temp_file.path)

        unless status.success?
          raise GenerationError, "TypeScript execution failed: #{stderr}"
        end

        # Parse JSON Schema from stdout
        json_schema = JSONSerializer.parse(stdout)

        # Save to disk
        save_schema(schema_info[:template_name], json_schema)

        json_schema
      ensure
        temp_file.unlink if temp_file
        File.unlink(bundled_file) if bundled_file && File.exist?(bundled_file)
      end
    end

    private

    # Determine if we should use tsx import mode for this schema
    #
    # Import mode is used when:
    # 1. schema_use_tsx_import is enabled in configuration
    # 2. The schema has an external src (not inline)
    # 3. The resolved_path exists
    #
    # @param schema_info [Hash] Schema information
    # @return [Boolean]
    def use_tsx_import_mode?(schema_info)
      return false unless Rhales.configuration.schema_use_tsx_import
      return false unless schema_info[:src]
      return false unless schema_info[:resolved_path]

      File.exist?(schema_info[:resolved_path])
    end

    # Execute tsx with optional tsconfig
    #
    # @param script_path [String] Path to the TypeScript script to execute
    # @return [Array] stdout, stderr, status from Open3.capture3
    def execute_tsx(script_path)
      tsconfig_path = Rhales.configuration.schema_tsconfig_path

      if tsconfig_path && File.exist?(tsconfig_path)
        Open3.capture3('pnpm', 'exec', 'tsx', '--tsconfig', tsconfig_path, script_path)
      else
        Open3.capture3('pnpm', 'exec', 'tsx', script_path)
      end
    end

    # Build TypeScript script from bundled external schema
    #
    # Uses esbuild to bundle the external schema with all imports resolved,
    # writes to a temp file, then imports via default export. This allows
    # external files to name their schema variable anything they want.
    #
    # External schema files must use default export:
    #   const mySchema = z.object({ ... });
    #   export default mySchema;
    #
    # @param schema_info [Hash] Schema information with resolved_path
    # @return [Array<String, String>] [script content, bundled_file_path] - caller must clean up bundled file
    def build_typescript_import_script(schema_info)
      safe_name = schema_info[:template_name].gsub("'", "\\'")
      schema_path = schema_info[:resolved_path]

      # Bundle external schema with esbuild to temp file - resolves all imports
      temp_dir = File.join(Dir.pwd, 'tmp')
      FileUtils.mkdir_p(temp_dir) unless Dir.exist?(temp_dir)
      bundled_file = File.join(temp_dir, "bundled_#{File.basename(schema_path, '.*')}_#{Process.pid}.mjs")

      stdout, stderr, status = Open3.capture3(
        'pnpm', 'exec', 'esbuild', schema_path,
        '--bundle', '--format=esm', '--platform=node',
        "--outfile=#{bundled_file}"
      )

      unless status.success?
        raise GenerationError, "esbuild bundling failed for #{schema_path}: #{stderr}"
      end

      script = <<~TYPESCRIPT
        // Auto-generated schema generator for #{safe_name}
        // Source: #{schema_info[:src]} (bundled via esbuild)
        import { z } from 'zod/v4';
        import schema from '#{bundled_file}';

        // Generate JSON Schema
        try {
          const jsonSchema = z.toJSONSchema(schema, {
            target: 'draft-2020-12',
            unrepresentable: 'any',
            cycles: 'ref',
            reused: 'inline',
          });

          // Add metadata
          const schemaWithMeta = {
            $schema: 'https://json-schema.org/draft/2020-12/schema',
            $id: `https://rhales.dev/schemas/#{safe_name}.json`,
            title: '#{safe_name}',
            description: 'Schema for #{safe_name} template',
            ...jsonSchema,
          };

          // Output JSON to stdout
          console.log(JSON.stringify(schemaWithMeta, null, 2));
        } catch (error) {
          console.error('Schema generation error:', error.message);
          process.exit(1);
        }
      TYPESCRIPT

      [script, bundled_file]
    end

    def build_typescript_script(schema_info)
      # Escape single quotes in template name for TypeScript string
      safe_name = schema_info[:template_name].gsub("'", "\\'")
      source_comment = if schema_info[:src]
        "// Source: #{schema_info[:src]} (external)"
      else
        "// Source: inline schema"
      end

      <<~TYPESCRIPT
        // Auto-generated schema generator for #{safe_name}
        #{source_comment}
        import { z } from 'zod/v4';

        // Schema code from .rue template
        #{schema_info[:schema_code].strip}

        // Generate JSON Schema
        try {
          const jsonSchema = z.toJSONSchema(schema, {
            target: 'draft-2020-12',
            unrepresentable: 'any',
            cycles: 'ref',
            reused: 'inline',
          });

          // Add metadata
          const schemaWithMeta = {
            $schema: 'https://json-schema.org/draft/2020-12/schema',
            $id: `https://rhales.dev/schemas/#{safe_name}.json`,
            title: '#{safe_name}',
            description: 'Schema for #{safe_name} template',
            ...jsonSchema,
          };

          // Output JSON to stdout
          console.log(JSON.stringify(schemaWithMeta, null, 2));
        } catch (error) {
          console.error('Schema generation error:', error.message);
          process.exit(1);
        }
      TYPESCRIPT
    end

    def save_schema(template_name, json_schema)
      # Create subdirectories if template name contains paths
      schema_file = File.join(@output_dir, "#{template_name}.json")
      schema_dir = File.dirname(schema_file)
      FileUtils.mkdir_p(schema_dir) unless File.directory?(schema_dir)

      File.write(schema_file, JSONSerializer.dump(json_schema))
    end

    def validate_setup!
      unless File.directory?(@templates_dir)
        raise GenerationError, "Templates directory does not exist: #{@templates_dir}"
      end

      # Check pnpm is available
      stdout, stderr, status = Open3.capture3('pnpm', '--version')
      unless status.success?
        raise GenerationError, "pnpm not found. Install pnpm to generate schemas: npm install -g pnpm"
      end

      # Check tsx is available (will be installed by pnpm if needed)
      stdout, stderr, status = Open3.capture3('pnpm', 'exec', 'tsx', '--version')
      unless status.success?
        raise GenerationError, "tsx not found. Run: pnpm install tsx --save-dev"
      end

      # Check esbuild is available when tsx import mode is enabled
      if Rhales.configuration.schema_use_tsx_import
        stdout, stderr, status = Open3.capture3('pnpm', 'exec', 'esbuild', '--version')
        unless status.success?
          raise GenerationError, "esbuild not found (required for external schema bundling). Run: pnpm install esbuild --save-dev"
        end
      end
    end

    def ensure_output_directory!
      FileUtils.mkdir_p(@output_dir) unless File.directory?(@output_dir)
    end
  end
end
