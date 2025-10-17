# lib/rhales/schema_generator.rb

require 'open3'
require 'json'
require 'tempfile'
require 'fileutils'
require_relative 'schema_extractor'

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
  #     output_dir: './lib/rhales/schemas'
  #   )
  #   results = generator.generate_all
  class SchemaGenerator
    class GenerationError < StandardError; end

    attr_reader :templates_dir, :output_dir

    # @param templates_dir [String] Directory containing .rue files
    # @param output_dir [String] Directory to save generated JSON schemas
    def initialize(templates_dir:, output_dir: './lib/rhales/schemas')
      @templates_dir = File.expand_path(templates_dir)
      @output_dir = File.expand_path(output_dir)

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
          error_msg = "Failed to generate schema for #{schema_info[:template_name]}: #{e.message}"
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

      begin
        # Write TypeScript script
        temp_file.write(build_typescript_script(schema_info))
        temp_file.close

        # Execute with tsx via pnpm
        stdout, stderr, status = Open3.capture3('pnpm', 'exec', 'tsx', temp_file.path)

        unless status.success?
          raise GenerationError, "TypeScript execution failed: #{stderr}"
        end

        # Parse JSON Schema from stdout
        json_schema = JSON.parse(stdout)

        # Save to disk
        save_schema(schema_info[:template_name], json_schema)

        json_schema
      ensure
        temp_file.unlink if temp_file
      end
    end

    private

    def build_typescript_script(schema_info)
      # Escape single quotes in template name for TypeScript string
      safe_name = schema_info[:template_name].gsub("'", "\\'")

      <<~TYPESCRIPT
        // Auto-generated schema generator for #{safe_name}
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

      File.write(schema_file, JSON.pretty_generate(json_schema))
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
    end

    def ensure_output_directory!
      FileUtils.mkdir_p(@output_dir) unless File.directory?(@output_dir)
    end
  end
end
