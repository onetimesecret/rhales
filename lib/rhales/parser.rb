# lib/rhales/parser.rb - Updated to use formal grammar

require_relative 'grammars/rue'

module Rhales
  class Parser
    class ParseError < StandardError; end
    class SectionMissingError < ParseError; end
    class SectionDuplicateError < ParseError; end
    class InvalidSyntaxError < ParseError; end

    REQUIRED_SECTIONS = %w[data template].freeze
    OPTIONAL_SECTIONS = ['logic'].freeze
    ALL_SECTIONS = (REQUIRED_SECTIONS + OPTIONAL_SECTIONS).freeze

    attr_reader :content, :file_path, :grammar, :ast

    def initialize(content, file_path = nil)
      @content = content
      @file_path = file_path
      @grammar = RueGrammar.new(content, file_path)
      @ast = nil
    end

    def parse!
      @grammar.parse!
      @ast = @grammar.ast
      parse_data_attributes!
      self
    rescue RueGrammar::ParseError => e
      raise ParseError, "Grammar error: #{e.message}"
    end

    def sections
      return {} unless @ast

      @grammar.sections.transform_values do |section_node|
        section_node.value[:content].map do |content_node|
          case content_node.type
          when :text
            content_node.value
          when :handlebars_expression
            if content_node.value[:raw]
              "{{{#{content_node.value[:content]}}}"
            else
              "{{#{content_node.value[:content]}}}"
            end
          end
        end.join
      end
    end

    def section(name)
      sections[name]
    end

    def data_attributes
      @data_attributes ||= {}
    end

    def window_attribute
      data_attributes['window'] || 'data'
    end

    def schema_path
      data_attributes['schema']
    end

    def section?(name)
      @grammar.sections.key?(name)
    end

    def partials
      return [] unless @ast

      partials = []
      extract_partials_from_node(@ast, partials)
      partials.uniq
    end

    def template_variables
      extract_variables_from_section('template', exclude_partials: true)
    end

    def data_variables
      extract_variables_from_section('data')
    end

    def all_variables
      (template_variables + data_variables).uniq
    end

    private

    def extract_partials_from_node(node, partials)
      return unless @ast

      # Extract from all sections
      @grammar.sections.each do |section_name, section_node|
        content_nodes = section_node.value[:content]
        next unless content_nodes.is_a?(Array)

        content_nodes.each do |content_node|
          if content_node.type == :handlebars_expression
            content = content_node.value[:content]
            if content.start_with?('>')
              partials << content[1..-1].strip
            end
          end
        end
      end
    end

    def extract_variables_from_section(section_name, exclude_partials: false)
      section_node = @grammar.sections[section_name]
      return [] unless section_node

      variables = []
      content_nodes = section_node.value[:content]
      extract_variables_from_content(content_nodes, variables, exclude_partials: exclude_partials)
      variables.uniq
    end

    def extract_variables_from_content(content_nodes, variables, exclude_partials: false)
      return unless content_nodes.is_a?(Array)

      content_nodes.each do |node|
        if node.type == :handlebars_expression
          content = node.value[:content]

          # Skip partials if requested
          next if exclude_partials && content.start_with?('>')

          # Skip block helpers
          next if content.match?(/^(#|\/)(if|unless|each|with)\s/)

          variables << content.strip
        end
      end
    end

    private

    def parse_data_attributes!
      data_section = @grammar.sections['data']
      @data_attributes = {}

      if data_section
        @data_attributes = data_section.value[:attributes].dup
      end

      # Set default window attribute
      @data_attributes['window'] ||= 'data'
    end

    class << self
      def parse_file(file_path)
        raise ArgumentError, 'Not a .rue file' unless rue_file?(file_path)

        file_content = File.read(file_path)
        new(file_content, file_path).parse!
      end

      def rue_file?(file_path)
        File.extname(file_path) == '.rue'
      end
    end
  end
end
