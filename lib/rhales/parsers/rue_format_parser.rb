# lib/rhales/parsers/rue_format_parser.rb

require_relative 'handlebars_parser'
require_relative 'xml_strategy_factory'

module Rhales
  # Hand-rolled recursive descent parser for .rue files
  #
  # This parser implements .rue file parsing rules in Ruby code and produces
  # an Abstract Syntax Tree (AST) for .rue file processing. It handles:
  #
  # - Section-based parsing: <data>, <template>, <logic>
  # - Attribute extraction from section tags
  # - Delegation to HandlebarsParser for template content
  # - Validation of required sections
  #
  # Note: This class is a parser implementation, not a formal grammar definition.
  # A formal grammar would be written in BNF/EBNF notation, while this class
  # contains the actual parsing logic written in Ruby.
  #
  # File format structure:
  # rue_file := section+
  # section := '<' tag_name attributes? '>' content '</' tag_name '>'
  # tag_name := 'data' | 'template' | 'logic'
  # attributes := attribute+
  # attribute := key '=' quoted_value
  # content := (text | handlebars_expression)*
  # handlebars_expression := '{{' expression '}}'
  class RueFormatParser
    # At least one of these sections must be present
    unless defined?(REQUIRES_ONE_OF_SECTIONS)
      REQUIRES_ONE_OF_SECTIONS = %w[data template].freeze

      KNOWN_SECTIONS = %w[data template logic].freeze
      ALL_SECTIONS = KNOWN_SECTIONS.freeze

      # Regular expression to match HTML/XML comments outside of sections
      COMMENT_REGEX = /<!--.*?-->/m
    end

    class ParseError < ::Rhales::ParseError
      def initialize(message, line: nil, column: nil, offset: nil)
        super(message, line: line, column: column, offset: offset, source_type: :rue)
      end
    end

    class Node
      attr_reader :type, :location, :children, :value

      def initialize(type, location, value: nil, children: [])
        @type     = type
        @location = location
        @value    = value
        @children = children
      end
    end

    class Location
      attr_reader :start_line, :start_column, :end_line, :end_column, :start_offset, :end_offset

      def initialize(start_line:, start_column:, end_line:, end_column:, start_offset:, end_offset:)
        @start_line   = start_line
        @start_column = start_column
        @end_line     = end_line
        @end_column   = end_column
        @start_offset = start_offset
        @end_offset   = end_offset
      end
    end

    def initialize(content, file_path = nil)
      @content   = preprocess_content(content)
      @file_path = file_path
      @ast       = nil
    end

    def parse!
      parser_strategy = Parsers::XmlStrategyFactory.create
      sections_data = parser_strategy.parse(@content)

      parsed_sections = sections_data.map do |section_hash|
        tag_name = section_hash[:tag]
        attributes = section_hash[:attributes]
        content_str = section_hash[:content]

        content_nodes = if tag_name == 'template'
          HandlebarsParser.new(content_str).parse!.ast.children
        else
          [Node.new(:text, dummy_location, value: content_str)]
        end

        Node.new(:section, dummy_location, value: {
          tag: tag_name,
          attributes: attributes,
          content: content_nodes
        })
      end

      if parsed_sections.empty? && !@content.strip.empty?
        raise ParseError, 'Failed to parse any sections. Check for malformed tags.'
      end

      @ast = Node.new(:rue_file, dummy_location, children: parsed_sections)
      validate_ast!
      self
    end

    attr_reader :ast

    def sections
      return {} unless @ast

      @ast.children.each_with_object({}) do |section_node, sections|
        sections[section_node.value[:tag]] = section_node
      end
    end

    private

    def validate_ast!
      sections = @ast.children.map { |node| node.value[:tag] }

      # Check that at least one required section is present
      required_present = REQUIRES_ONE_OF_SECTIONS & sections
      if required_present.empty?
        raise ParseError.new("Must have at least one of: #{REQUIRES_ONE_OF_SECTIONS.join(', ')}", line: 1, column: 1)
      end

      # Check for duplicates
      duplicates = sections.select { |tag| sections.count(tag) > 1 }.uniq
      if duplicates.any?
        raise ParseError.new("Duplicate sections: #{duplicates.join(', ')}", line: 1, column: 1)
      end

      # Check for unknown sections
      unknown = sections - KNOWN_SECTIONS
      if unknown.any?
        raise ParseError.new("Unknown sections: #{unknown.join(', ')}", line: 1, column: 1)
      end
    end

    # Preprocess content to strip XML/HTML comments.
    def preprocess_content(content)
      content.gsub(COMMENT_REGEX, '')
    end

    # Create a dummy location. The new parsers don't provide line/col info
    # in a standardized way yet. This can be improved later.
    def dummy_location
      Location.new(start_line: 0, start_column: 0, end_line: 0, end_column: 0, start_offset: 0, end_offset: 0)
    end
  end
end
