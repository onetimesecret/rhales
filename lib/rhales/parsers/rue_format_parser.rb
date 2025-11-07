# lib/rhales/parsers/rue_format_parser.rb
# frozen_string_literal: true

require 'strscan'
require_relative 'handlebars_parser'

module Rhales
  # Hand-rolled recursive descent parser for .rue files
  #
  # This parser implements .rue file parsing rules in Ruby code and produces
  # an Abstract Syntax Tree (AST) for .rue file processing. It handles:
  #
  # - Section-based parsing: <schema>, <template>, <logic>
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
  # tag_name := 'schema' | 'template' | 'logic'
  # attributes := attribute+
  # attribute := key '=' quoted_value
  # content := (text | handlebars_expression)*
  # handlebars_expression := '{{' expression '}}'
  class RueFormatParser
    # At least one of these sections must be present
    unless defined?(REQUIRES_ONE_OF_SECTIONS)
      REQUIRES_ONE_OF_SECTIONS = %w[schema template].freeze

      KNOWN_SECTIONS = %w[schema template logic].freeze
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

      advance while !at_end? && current_char.match?(/[a-zA-Z0-9_]/)

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

    # Uses StringScanner to parse "content" in <section>content</section>
    def parse_section_content(tag_name)
      content_start = @position
      closing_tag = "</#{tag_name}>"

      # Create scanner from remaining content
      scanner = StringScanner.new(@content[content_start..])

      # Find the closing tag position
      if scanner.scan_until(/(?=#{Regexp.escape(closing_tag)})/)
        # Calculate content length (scanner.charpos gives us position right before closing tag)
        content_length = scanner.charpos
        raw_content = @content[content_start, content_length]

        # Advance position tracking to end of content
        advance_to_position(content_start + content_length)

        # Process content based on tag type
        if tag_name == 'template'
          handlebars_parser = HandlebarsParser.new(raw_content)
          handlebars_parser.parse!
          handlebars_parser.ast.children
        else
          # For schema and logic sections, keep as simple text
          raw_content.empty? ? [] : [Node.new(:text, current_location, value: raw_content)]
        end
      else
        parse_error("Expected '#{closing_tag}' to close section")
      end
    end

    # Add this helper method to advance position tracking to a specific offset
    def advance_to_position(target_position)
      advance while @position < target_position && !at_end?
    end

    def parse_quoted_string
      quote_char = current_char
      unless ['"', "'"].include?(quote_char)
        parse_error('Expected quoted string')
      end

      advance # Skip opening quote
      value = []

      while !at_end? && current_char != quote_char
        value << current_char
        advance
      end

      consume(quote_char) || parse_error('Unterminated quoted string')

      # NOTE: Character-by-character parsing is acceptable here since attribute values
      # in section tags (e.g., <tag attribute="value">) are typically short strings.
      # Using StringScanner would be overkill for this use case.
      value.join
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

    def parse_error(message)
      raise ParseError.new(message, line: @line, column: @column, offset: @position)
    end

    # Preprocess content to strip XML/HTML comments outside of sections
    # Uses Ruby 3.4+ pattern matching for robust, secure parsing
    def preprocess_content(content)
      tokens = tokenize_content(content)

      # Use pattern matching to filter out comments outside sections
      result_parts = []
      in_section = false

      tokens.each do |token|
        case token
        in { type: :comment } unless in_section
          # Skip comments outside sections
          next
        in { type: :section_start }
          in_section = true
          result_parts << token[:content]
        in { type: :section_end }
          in_section = false
          result_parts << token[:content]
        in { type: :comment | :text, content: content }
          # Include comments inside sections and all text
          result_parts << content
        end
      end

      result_parts.join
    end

    # Tokenize content into structured tokens for pattern matching
    # Uses StringScanner for better performance and cleaner code
    def tokenize_content(content)
      scanner = StringScanner.new(content)
      tokens = []

      until scanner.eos?
        tokens << case
        when scanner.scan(/<!--.*?-->/m)
          # Comment token - non-greedy match for complete comments
          { type: :comment, content: scanner.matched }
        when scanner.scan(/<(schema|template|logic)(\s[^>]*)?>/m)
          # Section start token - matches opening tags with optional attributes
          { type: :section_start, content: scanner.matched }
        when scanner.scan(%r{</(schema|template|logic)>}m)
          # Section end token - matches closing tags
          { type: :section_end, content: scanner.matched }
        when scanner.scan(/[^<]+/)
          # Text token - consolidates runs of non-< characters for efficiency
          { type: :text, content: scanner.matched }
        else
          # Fallback for single characters (< that don't match patterns)
          # This maintains compatibility with the original character-by-character behavior
          { type: :text, content: scanner.getch }
        end
      end

      tokens
    end
  end
end
