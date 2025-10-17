# lib/rhales/schema_generator.rb

require 'ferrum'
require 'json'
require 'fileutils'
require_relative 'schema_extractor'

module Rhales
  # Generates JSON Schemas from Zod schemas using headless browser automation
  #
  # This class uses Ferrum (headless Chrome) to execute Zod schema code and
  # convert it to JSON Schema format. The generated schemas are saved to disk
  # for use by the validation middleware.
  #
  # Usage:
  #   generator = SchemaGenerator.new(
  #     templates_dir: './templates',
  #     output_dir: './lib/rhales/schemas',
  #     zod_path: './node_modules/zod/v4-mini/index.js'
  #   )
  #   generator.generate_all
  class SchemaGenerator
    class GenerationError < StandardError; end

    DEFAULT_ZOD_PATHS = [
      './node_modules/zod/v4-mini/index.js',
      './node_modules/zod/lib/index.mjs',
      '../node_modules/zod/v4-mini/index.js'
    ].freeze

    attr_reader :templates_dir, :output_dir, :zod_path

    # @param templates_dir [String] Directory containing .rue files
    # @param output_dir [String] Directory to save generated JSON schemas
    # @param zod_path [String, nil] Path to Zod module (auto-detected if nil)
    # @param headless [Boolean] Run browser in headless mode (default: true)
    def initialize(templates_dir:, output_dir: './lib/rhales/schemas', zod_path: nil, headless: true)
      @templates_dir = File.expand_path(templates_dir)
      @output_dir = File.expand_path(output_dir)
      @zod_path = zod_path || detect_zod_path
      @headless = headless

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

      browser = create_browser

      begin
        schemas.each do |schema_info|
          begin
            generate_schema(browser, schema_info)
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
      ensure
        browser&.quit
      end

      results
    end

    # Generate JSON Schema for a single template
    #
    # @param browser [Ferrum::Browser] Browser instance
    # @param schema_info [Hash] Schema information from SchemaExtractor
    # @return [Hash] Generated JSON Schema
    def generate_schema(browser, schema_info)
      # Create HTML page that executes Zod and generates JSON Schema
      html = build_schema_html(schema_info)

      # Navigate to data URL with HTML content
      page = browser.create_page
      page.go("data:text/html;charset=utf-8,#{URI.encode_www_form_component(html)}")

      # Wait for schema generation (max 5 seconds)
      start_time = Time.now
      json_schema = nil

      while Time.now - start_time < 5
        json_schema = page.evaluate('window.__generatedSchema')
        break if json_schema
        sleep 0.1
      end

      unless json_schema
        error_message = page.evaluate('window.__generationError') rescue 'Unknown error'
        raise GenerationError, "Schema generation timed out or failed: #{error_message}"
      end

      # Save to disk
      save_schema(schema_info[:template_name], json_schema)

      json_schema
    ensure
      page&.close
    end

    private

    def create_browser
      Ferrum::Browser.new(
        headless: @headless,
        timeout: 30,
        window_size: [1024, 768],
        browser_options: {
          'no-sandbox': nil,
          'disable-gpu': nil
        }
      )
    end

    def build_schema_html(schema_info)
      <<~HTML
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="utf-8">
          <title>Schema Generation: #{schema_info[:template_name]}</title>
        </head>
        <body>
          <h1>Generating schema...</h1>
          <script type="module">
            try {
              // Import Zod
              const zod = await import('file://#{@zod_path}');
              const z = zod.z || zod.default || zod;

              // Execute schema code
              #{schema_info[:schema_code]}

              // Convert to JSON Schema (Zod v4 has toJSONSchema method)
              if (typeof z.toJSONSchema === 'function') {
                window.__generatedSchema = z.toJSONSchema(schema);
              } else {
                throw new Error('z.toJSONSchema is not available - Zod v4 required');
              }

              console.log('✓ Schema generation successful');
            } catch (error) {
              window.__generationError = error.message;
              console.error('✗ Schema generation failed:', error);
            }
          </script>
        </body>
        </html>
      HTML
    end

    def save_schema(template_name, json_schema)
      # Create subdirectories if template name contains paths
      schema_file = File.join(@output_dir, "#{template_name}.json")
      schema_dir = File.dirname(schema_file)
      FileUtils.mkdir_p(schema_dir) unless File.directory?(schema_dir)

      File.write(schema_file, JSON.pretty_generate(json_schema))
    end

    def detect_zod_path
      DEFAULT_ZOD_PATHS.each do |path|
        full_path = File.expand_path(path, @templates_dir)
        return full_path if File.exist?(full_path)
      end

      raise GenerationError, "Could not find Zod module. Tried: #{DEFAULT_ZOD_PATHS.join(', ')}"
    end

    def validate_setup!
      unless File.directory?(@templates_dir)
        raise GenerationError, "Templates directory does not exist: #{@templates_dir}"
      end

      unless File.exist?(@zod_path)
        raise GenerationError, "Zod module not found at: #{@zod_path}"
      end
    end

    def ensure_output_directory!
      FileUtils.mkdir_p(@output_dir) unless File.directory?(@output_dir)
    end
  end
end
