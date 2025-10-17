# lib/rhales/schema_extractor.rb

require_relative 'rue_document'

module Rhales
  # Extracts schema definitions from .rue files
  #
  # This class scans template directories for .rue files containing <schema>
  # sections and extracts the schema code along with metadata (attributes).
  #
  # Usage:
  #   extractor = SchemaExtractor.new('./templates')
  #   schemas = extractor.extract_all
  #   schemas.each do |schema_info|
  #     puts "#{schema_info[:template_name]}: #{schema_info[:lang]}"
  #   end
  class SchemaExtractor
    class ExtractionError < StandardError; end

    attr_reader :templates_dir

    def initialize(templates_dir)
      @templates_dir = File.expand_path(templates_dir)
      validate_directory!
    end

    # Extract all schemas from .rue files in the templates directory
    #
    # @return [Array<Hash>] Array of schema information hashes
    # @example
    #   [
    #     {
    #       template_name: 'dashboard',
    #       template_path: '/path/to/dashboard.rue',
    #       schema_code: 'const schema = z.object({...});',
    #       lang: 'ts-zod',
    #       version: '2',
    #       envelope: 'SuccessEnvelope',
    #       window: 'appData',
    #       merge: 'deep',
    #       layout: 'layouts/main',
    #       extends: nil
    #     }
    #   ]
    def extract_all
      rue_files = find_rue_files
      schemas = []

      rue_files.each do |file_path|
        begin
          schema_info = extract_from_file(file_path)
          schemas << schema_info if schema_info
        rescue => e
          warn "Warning: Failed to extract schema from #{file_path}: #{e.message}"
        end
      end

      schemas
    end

    # Extract schema from a single .rue file
    #
    # @param file_path [String] Path to the .rue file
    # @return [Hash, nil] Schema information hash or nil if no schema section
    def extract_from_file(file_path)
      doc = RueDocument.parse_file(file_path)

      return nil unless doc.section?('schema')

      template_name = derive_template_name(file_path)
      schema_code = doc.section('schema')

      {
        template_name: template_name,
        template_path: file_path,
        schema_code: schema_code.strip,
        lang: doc.schema_lang,
        version: doc.schema_version,
        envelope: doc.schema_envelope,
        window: doc.schema_window,
        merge: doc.schema_merge_strategy,
        layout: doc.schema_layout,
        extends: doc.schema_extends
      }
    end

    # Find all .rue files in the templates directory (recursive)
    #
    # @return [Array<String>] Array of absolute file paths
    def find_rue_files
      pattern = File.join(@templates_dir, '**', '*.rue')
      Dir.glob(pattern).sort
    end

    # Count how many .rue files have schema sections
    #
    # @return [Hash] Count information
    def schema_stats
      all_files = find_rue_files
      schemas = extract_all

      {
        total_files: all_files.count,
        files_with_schemas: schemas.count,
        files_without_schemas: all_files.count - schemas.count,
        schemas_by_lang: schemas.group_by { |s| s[:lang] }.transform_values(&:count)
      }
    end

    private

    def validate_directory!
      unless File.directory?(@templates_dir)
        raise ExtractionError, "Templates directory does not exist: #{@templates_dir}"
      end
    end

    # Derive template name from file path
    # Examples:
    #   /path/to/templates/dashboard.rue => 'dashboard'
    #   /path/to/templates/pages/user/profile.rue => 'pages/user/profile'
    def derive_template_name(file_path)
      relative_path = file_path.sub(@templates_dir + '/', '')
      relative_path.sub(/\.rue$/, '')
    end
  end
end
