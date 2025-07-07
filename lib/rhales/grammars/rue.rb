# lib/rhales/rue_grammar.rb

require_relative 'handlebars'

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
  class RueGrammar
    REQUIRED_SECTIONS = %w[data template].freeze
    OPTIONAL_SECTIONS = ['logic'].freeze
    ALL_SECTIONS      = (REQUIRED_SECTIONS + OPTIONAL_SECTIONS).freeze

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
      @content   = content
      @file_path = file_path
      @position  = 0
      @line      = 1
      @column    = 1
      @ast       = nil
    end

    def parse!
      @ast = parse_rue_file
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

    def parse_rue_file
      sections = []

      until at_end?
        skip_whitespace
        break if at_end?

        sections << parse_section
      end

      if sections.empty?
        raise ParseError.new('Empty .rue file', line: @line, column: @column, offset: @position)
      end

      Node.new(:rue_file, current_location, children: sections)
    end

    def parse_section
      start_pos = current_position

      # Parse opening tag
      consume('<') || parse_error("Expected '<' to start section")
      tag_name   = parse_tag_name
      attributes = parse_attributes
      consume('>') || parse_error("Expected '>' to close opening tag")

      # Parse content
      content = parse_section_content(tag_name)

      # Parse closing tag
      consume("</#{tag_name}>") || parse_error("Expected '</#{tag_name}>' to close section")

      end_pos  = current_position
      location = Location.new(
        start_line: start_pos[:line],
        start_column: start_pos[:column],
        end_line: end_pos[:line],
        end_column: end_pos[:column],
        start_offset: start_pos[:offset],
        end_offset: end_pos[:offset],
      )

      Node.new(:section, location, value: {
        tag: tag_name,
        attributes: attributes,
        content: content,
      }
      )
    end

    def parse_tag_name
      start_pos = @position

      advance while !at_end? && current_char.match?(/[a-zA-Z]/)

      if start_pos == @position
        parse_error('Expected tag name')
      end

      @content[start_pos...@position]
    end

    def parse_attributes
      attributes = {}

      while !at_end? && current_char != '>'
        skip_whitespace
        break if current_char == '>'

        # Parse attribute name
        attr_name = parse_identifier
        skip_whitespace

        consume('=') || parse_error("Expected '=' after attribute name")
        skip_whitespace

        # Parse attribute value
        attr_value            = parse_quoted_string
        attributes[attr_name] = attr_value

        skip_whitespace
      end

      attributes
    end

    def parse_section_content(tag_name)
      start_pos     = @position
      content_start = @position

      # Extract the raw content between section tags
      raw_content = ''
      while !at_end? && !peek_closing_tag?(tag_name)
        raw_content << current_char
        advance
      end

      # For template sections, use HandlebarsGrammar to parse the content
      if tag_name == 'template'
        handlebars_grammar = HandlebarsGrammar.new(raw_content)
        handlebars_grammar.parse!
        handlebars_grammar.ast.children
      else
        # For data and logic sections, keep as simple text
        return [Node.new(:text, current_location, value: raw_content)] unless raw_content.empty?

        []
      end
    end

    def parse_quoted_string
      quote_char = current_char
      unless ['"', "'"].include?(quote_char)
        parse_error('Expected quoted string')
      end

      advance # Skip opening quote
      value = ''

      while !at_end? && current_char != quote_char
        value << current_char
        advance
      end

      consume(quote_char) || parse_error('Unterminated quoted string')
      value
    end

    def parse_identifier
      start_pos = @position

      advance while !at_end? && current_char.match?(/[a-zA-Z0-9_]/)

      if start_pos == @position
        parse_error('Expected identifier')
      end

      @content[start_pos...@position]
    end

    def peek_closing_tag?(tag_name)
      peek_string?("</#{tag_name}>")
    end

    def peek_string?(string)
      @content[@position, string.length] == string
    end

    def consume(expected)
      if peek_string?(expected)
        expected.length.times { advance }
        true
      else
        false
      end
    end

    def current_char
      return "\0" if at_end?

      @content[@position]
    end

    def peek_char
      return "\0" if @position + 1 >= @content.length

      @content[@position + 1]
    end

    def advance
      if current_char == "\n"
        @line  += 1
        @column = 1
      else
        @column += 1
      end
      @position += 1
    end

    def at_end?
      @position >= @content.length
    end

    def skip_whitespace
      advance while !at_end? && current_char.match?(/\s/)
    end

    def current_position
      { line: @line, column: @column, offset: @position }
    end

    def current_location
      pos = current_position
      Location.new(
        start_line: pos[:line],
        start_column: pos[:column],
        end_line: pos[:line],
        end_column: pos[:column],
        start_offset: pos[:offset],
        end_offset: pos[:offset],
      )
    end

    def validate_ast!
      sections = @ast.children.map { |node| node.value[:tag] }

      # Check for required sections
      missing = REQUIRED_SECTIONS - sections
      if missing.any?
        raise ParseError.new("Missing required sections: #{missing.join(', ')}", line: 1, column: 1)
      end

      # Check for duplicates
      duplicates = sections.select { |tag| sections.count(tag) > 1 }.uniq
      if duplicates.any?
        raise ParseError.new("Duplicate sections: #{duplicates.join(', ')}", line: 1, column: 1)
      end
    end

    def parse_error(message)
      raise ParseError.new(message, line: @line, column: @column, offset: @position)
    end
  end
end
