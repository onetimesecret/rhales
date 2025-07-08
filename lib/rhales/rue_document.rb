# lib/rhales/rue_document.rb

require_relative 'parsers/rue_format_parser'

module Rhales
  # High-level interface for parsed .rue files
  #
  # This class provides a convenient interface to .rue files parsed by RueFormatParser.
  # It uses RueFormatParser internally for low-level parsing and provides high-level
  # methods for accessing sections, attributes, and extracted data.
  #
  # Features:
  # - High-level interface to RueFormatParser AST
  # - Accurate error reporting with line/column information
  # - Convenient section access methods
  # - Section validation and attribute extraction
  # - Variable and partial dependency analysis
  # - AST-to-string conversion when needed
  #
  # Note: This class represents a parsed .rue file document, similar to how
  # HTML::Document represents a parsed HTML document.
  #
  # Usage:
  #   document = RueDocument.new(rue_content)
  #   document.parse!
  #   template_section = document.section('template')
  #   variables = document.template_variables
  class RueDocument
    class ParseError < ::Rhales::ValidationError; end
    class SectionMissingError < ParseError; end
    class SectionDuplicateError < ParseError; end
    class InvalidSyntaxError < ParseError; end

    REQUIRED_SECTIONS = %w[template].freeze
    OPTIONAL_SECTIONS = %w[data logic].freeze
    ALL_SECTIONS      = (REQUIRED_SECTIONS + OPTIONAL_SECTIONS).freeze

    attr_reader :content, :file_path, :grammar, :ast

    def initialize(content, file_path = nil)
      @content   = content
      @file_path = file_path
      @grammar   = RueFormatParser.new(content, file_path)
      @ast       = nil
    end

    def parse!
      @grammar.parse!
      @ast = @grammar.ast
      parse_data_attributes!
      self
    rescue RueFormatParser::ParseError => ex
      raise ParseError, "Parser error: #{ex.message}"
    end

    def sections
      return {} unless @ast

      @grammar.sections.transform_values do |section_node|
        convert_nodes_to_string(section_node.value[:content])
      end
    end

    def convert_nodes_to_string(nodes)
      nodes.map { |node| convert_node_to_string(node) }.join
    end

    def convert_node_to_string(node)
      case node.type
      when :text
        node.value
      when :variable_expression
        name = node.value[:name]
        raw  = node.value[:raw]
        raw ? "{{{#{name}}}}" : "{{#{name}}}"
      when :partial_expression
        "{{> #{node.value[:name]}}}"
      when :if_block
        condition    = node.value[:condition]
        if_content   = convert_nodes_to_string(node.value[:if_content])
        else_content = convert_nodes_to_string(node.value[:else_content])
        if else_content.empty?
          "{{#if #{condition}}}#{if_content}{{/if}}"
        else
          "{{#if #{condition}}}#{if_content}{{else}}#{else_content}{{/if}}"
        end
      when :unless_block
        condition = node.value[:condition]
        content   = convert_nodes_to_string(node.value[:content])
        "{{#unless #{condition}}}#{content}{{/unless}}"
      when :each_block
        items   = node.value[:items]
        content = convert_nodes_to_string(node.value[:content])
        "{{#each #{items}}}#{content}{{/each}}"
      when :handlebars_expression
        # Handle legacy format for data sections
        if node.value[:raw]
          "{{{#{node.value[:content]}}}"
        else
          "{{#{node.value[:content]}}}"
        end
      else
        ''
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

    def merge_strategy
      data_attributes['merge']
    end

    def layout
      data_attributes['layout']
    end

    def section?(name)
      @grammar.sections.key?(name)
    end

    # Get the raw section node with location information
    def section_node(name)
      @grammar.sections[name]
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

        extract_partials_from_content_nodes(content_nodes, partials)
      end
    end

    def extract_partials_from_content_nodes(content_nodes, partials)
      content_nodes.each do |content_node|
        case content_node.type
        when :partial_expression
          partials << content_node.value[:name]
        when :if_block
          extract_partials_from_content_nodes(content_node.value[:if_content], partials)
          extract_partials_from_content_nodes(content_node.value[:else_content], partials)
        when :unless_block, :each_block
          extract_partials_from_content_nodes(content_node.value[:content], partials)
        when :handlebars_expression
          # Handle old format for data sections
          content = content_node.value[:content]
          if content.start_with?('>')
            partials << content[1..].strip
          end
        end
      end
    end

    def extract_variables_from_section(section_name, exclude_partials: false)
      section_node = @grammar.sections[section_name]
      return [] unless section_node

      variables     = []
      content_nodes = section_node.value[:content]
      extract_variables_from_content(content_nodes, variables, exclude_partials: exclude_partials)
      variables.uniq
    end

    def extract_variables_from_content(content_nodes, variables, exclude_partials: false)
      return unless content_nodes.is_a?(Array)

      content_nodes.each do |node|
        case node.type
        when :variable_expression
          variables << node.value[:name]
        when :if_block
          variables << node.value[:condition]
          extract_variables_from_content(node.value[:if_content], variables, exclude_partials: exclude_partials)
          extract_variables_from_content(node.value[:else_content], variables, exclude_partials: exclude_partials)
        when :unless_block
          variables << node.value[:condition]
          extract_variables_from_content(node.value[:content], variables, exclude_partials: exclude_partials)
        when :each_block
          variables << node.value[:items]
          extract_variables_from_content(node.value[:content], variables, exclude_partials: exclude_partials)
        when :partial_expression
          # Skip partials if requested
          next if exclude_partials
        when :text
          # Extract handlebars expressions from text content (for data sections)
          extract_variables_from_text(node.value, variables, exclude_partials: exclude_partials)
        when :handlebars_expression
          # Handle old format for data sections
          content = node.value[:content]

          # Skip partials if requested
          next if exclude_partials && content.start_with?('>')

          # Skip block helpers
          next if content.match?(%r{^(#|/)(if|unless|each|with)\s})

          variables << content.strip
        end
      end
    end

    private

    def extract_variables_from_text(text, variables, exclude_partials: false)
      # Find all handlebars expressions in text content
      text.scan(/\{\{(.+?)\}\}/) do |match|
        content = match[0].strip

        # Skip partials if requested
        next if exclude_partials && content.start_with?('>')

        # Skip block helpers
        next if content.match?(%r{^(#|/)(if|unless|each|with)\s})

        variables << content
      end
    end

    def parse_data_attributes!
      data_section     = @grammar.sections['data']
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
