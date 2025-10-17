# lib/tasks/rhales_schema.rake

namespace :rhales do
  namespace :schema do
    desc 'Generate JSON Schemas from .rue template files'
    task :generate do
      require 'rhales'
      require 'rhales/schema_extractor'
      require 'rhales/schema_generator'

      # Default to current working directory (implementing project)
      templates_dir = ENV.fetch('TEMPLATES_DIR', './templates')
      output_dir = ENV.fetch('OUTPUT_DIR', './public/schemas')

      puts "Schema Generation"
      puts "=" * 60
      puts "Templates: #{templates_dir}"
      puts "Output: #{output_dir}"
      puts "Zod: (using pnpm exec tsx)"
      puts

      # Validate templates directory exists
      unless Dir.exist?(templates_dir)
        puts "⚠️  Templates directory not found: #{templates_dir}"
        puts
        puts "Usage:"
        puts "  rake rhales:schema:generate TEMPLATES_DIR=./templates OUTPUT_DIR=./public/schemas"
        puts
        puts "Or from project root where templates/ exists:"
        puts "  rake rhales:schema:generate"
        exit 1
      end

      # Extract schemas
      extractor = Rhales::SchemaExtractor.new(templates_dir)
      schemas = extractor.extract_all

      if schemas.empty?
        puts "⚠️  No schema sections found in templates"
        puts
        puts "Make sure your .rue files have <schema> sections:"
        puts "  <schema lang=\"js-zod\" window=\"appData\">"
        puts "  const schema = z.object({ ... });"
        puts "  </schema>"
        exit 0
      end

      puts "Found #{schemas.size} schema section(s):"
      schemas.each do |schema|
        puts "  - #{schema[:template_name]} (#{schema[:lang]})"
      end
      puts

      # Generate JSON Schemas
      generator = Rhales::SchemaGenerator.new(
        templates_dir: templates_dir,
        output_dir: output_dir
      )

      puts "Generating JSON Schemas..."
      results = generator.generate_all

      # Report results
      puts
      puts "Results:"
      puts "-" * 60

      generated_count = results[:generated]
      failed_count = results[:failed]

      if results[:success]
        puts "✓ Successfully generated #{generated_count} schema(s)"
        puts "✓ Output directory: #{output_dir}"
      else
        puts "✗ Generation failed with #{failed_count} error(s)"
        results[:errors].each do |error|
          puts "  - #{error}"
        end
      end

      puts

      exit(results[:success] ? 0 : 1)
    end

    desc 'Validate existing JSON Schemas'
    task :validate do
      require 'rhales'
      require 'json'
      require 'json-schema'

      # Default to current working directory
      schemas_dir = ENV.fetch('OUTPUT_DIR', './public/schemas')

      unless Dir.exist?(schemas_dir)
        puts "⚠️  Schemas directory not found: #{schemas_dir}"
        puts
        puts "Generate schemas first:"
        puts "  rake rhales:schema:generate"
        exit 1
      end

      schema_files = Dir.glob("#{schemas_dir}/**/*.json")

      if schema_files.empty?
        puts "⚠️  No schema files found in #{schemas_dir}"
        puts
        puts "Generate schemas first:"
        puts "  rake rhales:schema:generate"
        exit 1
      end

      puts "Validating #{schema_files.size} schema file(s) in #{schemas_dir}..."
      puts

      errors = []

      schema_files.each do |file|
        relative_path = file.sub("#{schemas_dir}/", '')

        begin
          schema = JSON.parse(File.read(file))

          # Basic validation
          unless schema.is_a?(Hash)
            errors << "#{relative_path}: Not a valid object"
            next
          end

          # Check for required JSON Schema fields
          unless schema['type']
            errors << "#{relative_path}: Missing 'type' field"
          end

          unless schema['$schema']
            errors << "#{relative_path}: Missing '$schema' field"
          end

          puts "✓ #{relative_path}"
        rescue JSON::ParserError => e
          errors << "#{relative_path}: Invalid JSON - #{e.message}"
        rescue => e
          errors << "#{relative_path}: #{e.message}"
        end
      end

      puts

      if errors.any?
        puts "Errors:"
        errors.each { |err| puts "  ✗ #{err}" }
        exit 1
      else
        puts "All schemas valid ✓"
      end
    end

    desc 'Show statistics about schema sections'
    task :stats do
      require 'rhales'
      require 'rhales/schema_extractor'

      # Default to current working directory
      templates_dir = ENV.fetch('TEMPLATES_DIR', './templates')

      unless Dir.exist?(templates_dir)
        puts "⚠️  Templates directory not found: #{templates_dir}"
        puts
        puts "Usage:"
        puts "  rake rhales:schema:stats TEMPLATES_DIR=./templates"
        exit 1
      end

      extractor = Rhales::SchemaExtractor.new(templates_dir)
      stats = extractor.schema_stats

      puts "Schema Statistics"
      puts "=" * 60
      puts "Templates directory: #{templates_dir}"
      puts
      puts "Total .rue files: #{stats[:total_files]}"
      puts "Files with <schema>: #{stats[:files_with_schemas]}"
      puts "Files without <schema>: #{stats[:files_without_schemas]}"
      puts

      if stats[:schemas_by_lang].any?
        puts "By language:"
        stats[:schemas_by_lang].each do |lang, count|
          puts "  #{lang}: #{count}"
        end
      end
    end
  end
end
