# lib/rhales/schema_extractor.rb
#
# frozen_string_literal: true

require 'pathname'
require_relative '../core/rue_document'

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
      src = doc.schema_src
      resolved_path = nil
      schema_code = nil

      if src
        # External schema: resolve path and read content
        resolved_path = resolve_schema_src_path(file_path, src)
        schema_code = read_schema_from_src(resolved_path, src, template_name)
      else
        # Inline schema: use content from the schema section
        schema_code = doc.section('schema')
      end

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
        extends: doc.schema_extends,
        src: src,
        resolved_path: resolved_path
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
    # @return [Hash] Count information including external vs inline breakdown
    def schema_stats
      all_files = find_rue_files
      schemas = extract_all

      external_count = schemas.count { |s| s[:src] }
      inline_count = schemas.count { |s| s[:src].nil? }

      {
        total_files: all_files.count,
        files_with_schemas: schemas.count,
        files_without_schemas: all_files.count - schemas.count,
        external_schemas: external_count,
        inline_schemas: inline_count,
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
      templates_pathname = Pathname.new(@templates_dir)
      file_pathname = Pathname.new(file_path)
      relative_path = file_pathname.relative_path_from(templates_pathname)
      relative_path.to_s.sub(/\.rue$/, '')
    end

    # Resolve external schema src path
    #
    # Resolution order:
    # 1. Relative to template file directory
    # 2. Search through configured schema_search_paths
    #
    # @param template_path [String] Absolute path to the .rue template
    # @param src [String] The src attribute value from the schema tag
    # @return [String] Absolute path to the external schema file
    # @raise [ExtractionError] If path traversal is detected or file not found
    def resolve_schema_src_path(template_path, src)
      template_dir = File.dirname(template_path)
      resolved = File.expand_path(src, template_dir)
      searched_paths = [resolved]

      # First, check if the path exists relative to template
      if File.exist?(resolved) && path_within_allowed_directories?(resolved)
        return resolved
      end

      # If the relative path does not exist or is not allowed,
      # search through configured schema_search_paths
      search_paths = Rhales.configuration.schema_search_paths || []
      search_paths.each do |search_path|
        expanded_search_path = File.expand_path(search_path)
        candidate = File.join(expanded_search_path, src)
        searched_paths << candidate

        if File.exist?(candidate) && path_within_allowed_directories?(candidate)
          return candidate
        end
      end

      # Security check on the template-relative path
      unless path_within_allowed_directories?(resolved)
        raise ExtractionError,
              "Schema src path traversal not allowed: '#{src}' resolves outside allowed directories"
      end

      # File not found in any location - raise helpful error listing all searched paths
      raise ExtractionError,
            "Schema file not found: '#{src}'. Searched:\n  - #{searched_paths.join("\n  - ")}"
    end

    # Check if a path is within any allowed directory
    #
    # Allowed directories include:
    # - The templates directory
    # - Any configured schema_search_paths
    #
    # @param path [String] Path to check
    # @return [Boolean] True if path is within an allowed directory
    def path_within_allowed_directories?(path)
      return true if path_within_directory?(path, @templates_dir)

      search_paths = Rhales.configuration.schema_search_paths || []
      search_paths.any? do |search_path|
        expanded_search_path = File.expand_path(search_path)
        path_within_directory?(path, expanded_search_path)
      end
    end

    # Read schema content from external file
    #
    # @param resolved_path [String] Absolute path to the schema file
    # @param src [String] Original src attribute value (for error messages)
    # @param template_name [String] Template name (for error messages)
    # @return [String] Schema file content
    # @raise [ExtractionError] If file cannot be read
    def read_schema_from_src(resolved_path, src, template_name)
      unless File.exist?(resolved_path)
        raise ExtractionError,
              "External schema file not found: '#{src}' (resolved to: #{resolved_path}) " \
              "referenced by template '#{template_name}'"
      end

      File.read(resolved_path)
    rescue Errno::EACCES => e
      raise ExtractionError,
            "Permission denied reading external schema '#{src}': #{e.message}"
    rescue Errno::EISDIR
      raise ExtractionError,
            "External schema path '#{src}' is a directory, not a file"
    end

    # Check if a path is within a given directory (security check)
    #
    # @param path [String] Path to check
    # @param directory [String] Directory that should contain the path
    # @return [Boolean] True if path is within directory
    def path_within_directory?(path, directory)
      expanded_path = File.expand_path(path)
      expanded_dir = File.expand_path(directory)

      # Ensure directory ends with separator for accurate prefix matching
      expanded_dir_with_sep = expanded_dir.end_with?(File::SEPARATOR) ? expanded_dir : "#{expanded_dir}#{File::SEPARATOR}"

      expanded_path.start_with?(expanded_dir_with_sep) || expanded_path == expanded_dir
    end
  end
end
