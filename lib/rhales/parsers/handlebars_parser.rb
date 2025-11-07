# lib/rhales/parsers/handlebars_parser.rb
# frozen_string_literal: true

module Rhales
  # Hand-rolled recursive descent parser for Handlebars template syntax
  #
  # This parser implements Handlebars parsing rules in Ruby code and produces
  # an Abstract Syntax Tree (AST) for template processing. It handles:
  #
  # - Variable expressions: {{variable}}, {{{raw}}}
  # - Block expressions: {{#if}}{{else}}{{/if}}, {{#each}}{{/each}}
  # - Partials: {{> partial_name}}
  # - Proper nesting and error reporting
  # - Whitespace control (future)
  #
  # Note: This class is a parser implementation, not a formal grammar definition.
  # A formal grammar would be written in BNF/EBNF notation, while this class
  # contains the actual parsing logic written in Ruby.
  #
  # AST Node Types:
  # - :template - Root template node
  # - :text - Plain text content
  # - :variable_expression - {{variable}} or {{{variable}}}
  # - :if_block - {{#if}}...{{else}}...{{/if}}
  # - :unless_block - {{#unless}}...{{/unless}}
  # - :each_block - {{#each}}...{{/each}}
  # - :partial_expression - {{> partial}}
  class HandlebarsParser
    class ParseError < ::Rhales::ParseError
      def initialize(message, line: nil, column: nil, offset: nil)
        super(message, line: line, column: column, offset: offset, source_type: :handlebars)
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

      def add_child(child)
        @children << child
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

    attr_reader :content, :ast

    def initialize(content)
      @content  = content
      @position = 0
      @line     = 1
      @column   = 1
      @ast      = nil
    end

    def parse!
      @ast = parse_template
      self
    end

    def variables
      return [] unless @ast

      collect_variables(@ast)
    end

    def partials
      return [] unless @ast

      collect_partials(@ast)
    end

    def blocks
      return [] unless @ast

      collect_blocks(@ast)
    end

    private

    def parse_template
      start_pos = current_position
      children  = []

      until at_end?
        if current_char == '{' && peek_char == '{'
          children << parse_handlebars_expression
        else
          text_content = parse_text_until_handlebars
          children << create_text_node(text_content) unless text_content.empty?
        end
      end

      end_pos  = current_position
      location = create_location(start_pos, end_pos)
      Node.new(:template, location, children: children)
    end

    def parse_handlebars_expression
      start_pos = current_position

      consume('{{') || parse_error("Expected '{{'")

      # Check for triple braces (raw output)
      raw = false
      if current_char == '{'
        raw = true
        advance
      end

      skip_whitespace

      # Parse expression content
      expression_content = parse_expression_content(raw)
      skip_whitespace

      # Consume closing braces
      if raw
        consume('}}}') || parse_error("Expected '}}}'")
      else
        consume('}}') || parse_error("Expected '}}'")
      end

      end_pos  = current_position
      location = create_location(start_pos, end_pos)

      # Determine expression type and create appropriate node
      create_expression_node(expression_content, raw, location)
    end

    def parse_expression_content(raw)
      chars          = []
      closing_braces = raw ? '}}}' : '}}'
      brace_count    = 0

      until at_end?
        if current_char == '}' && peek_string?(closing_braces)
          break
        elsif current_char == '{' && peek_char == '{'
          # Handle nested braces in content
          brace_count += 1
        elsif current_char == '}' && peek_char == '}'
          brace_count -= 1
          if brace_count < 0
            break
          end
        end

        chars << current_char
        advance
      end

      chars.join.strip
    end

    def create_expression_node(content, raw, location)
      case content
      when /^#if\s+(.+)$/
        create_if_block(Regexp.last_match(1).strip, location)
      when /^#unless\s+(.+)$/
        create_unless_block(Regexp.last_match(1).strip, location)
      when /^#each\s+(.+)$/
        create_each_block(Regexp.last_match(1).strip, location)
      when /^>\s*(.+)$/
        create_partial_node(Regexp.last_match(1).strip, location)
      when %r{^/(.+)$}
        # This is a closing tag, should be handled by block parsing
        parse_error("Unexpected closing tag: #{content}")
      when 'else'
        # This should be handled by block parsing
        parse_error("Unexpected 'else' outside of block")
      else
        # Variable expression
        create_variable_node(content, raw, location)
      end
    end

    def create_if_block(condition, start_location)
      # Parse the if block content
      if_content      = []
      else_content    = []
      current_content = if_content
      depth           = 1

      while !at_end? && depth > 0
        if current_char == '{' && peek_char == '{'
          expr_start = current_position
          consume('{{')

          # Check for triple braces
          raw = false
          if current_char == '{'
            raw = true
            advance
          end

          skip_whitespace
          expr_content = parse_expression_content(raw)
          skip_whitespace

          if raw
            consume('}}}') || parse_error("Expected '}}}'")
          else
            consume('}}') || parse_error("Expected '}}'")
          end

          expr_end      = current_position
          expr_location = create_location(expr_start, expr_end)

          case expr_content
          when /^#if\s+(.+)$/
            depth += 1
            # Add as variable expression, will be parsed properly later
            current_content << Node.new(:variable_expression, expr_location, value: {
              name: expr_content,
              raw: raw,
            }
            )
          when /^#unless\s+(.+)$/
            depth += 1
            current_content << Node.new(:variable_expression, expr_location, value: {
              name: expr_content,
              raw: raw,
            }
            )
          when /^#each\s+(.+)$/
            depth += 1
            current_content << Node.new(:variable_expression, expr_location, value: {
              name: expr_content,
              raw: raw,
            }
            )
          when %r{^/if$}
            depth -= 1
            break if depth == 0

            # Found the matching closing tag

            # This is a nested closing tag
            current_content << Node.new(:variable_expression, expr_location, value: {
              name: expr_content,
              raw: raw,
            }
            )

          when %r{^/unless$}
            depth -= 1
            current_content << Node.new(:variable_expression, expr_location, value: {
              name: expr_content,
              raw: raw,
            }
            )
          when %r{^/each$}
            depth -= 1
            current_content << Node.new(:variable_expression, expr_location, value: {
              name: expr_content,
              raw: raw,
            }
            )
          when 'else'
            if depth == 1
              current_content = else_content
            else
              current_content << Node.new(:variable_expression, expr_location, value: {
                name: expr_content,
                raw: raw,
              }
              )
            end
          else
            current_content << create_expression_node(expr_content, raw, expr_location)
          end
        else
          text_content = parse_text_until_handlebars
          current_content << create_text_node(text_content) unless text_content.empty?
        end
      end

      if depth > 0
        parse_error('Missing closing tag for {{#if}}')
      end

      # Now post-process the content to handle nested blocks
      processed_if_content   = post_process_content(if_content)
      processed_else_content = post_process_content(else_content)

      Node.new(:if_block, start_location, value: {
        condition: condition,
        if_content: processed_if_content,
        else_content: processed_else_content,
      }
      )
    end

    def create_unless_block(condition, start_location)
      # Parse the unless block content
      content = []
      depth   = 1

      while !at_end? && depth > 0
        if current_char == '{' && peek_char == '{'
          expr_start = current_position
          consume('{{')

          raw = false
          if current_char == '{'
            raw = true
            advance
          end

          skip_whitespace
          expr_content = parse_expression_content(raw)
          skip_whitespace

          if raw
            consume('}}}') || parse_error("Expected '}}}'")
          else
            consume('}}') || parse_error("Expected '}}'")
          end

          expr_end      = current_position
          expr_location = create_location(expr_start, expr_end)

          case expr_content
          when /^#if\s+(.+)$/, /^#unless\s+(.+)$/, /^#each\s+(.+)$/
            depth += 1
            content << Node.new(:variable_expression, expr_location, value: {
              name: expr_content,
              raw: raw,
            }
            )
          when %r{^/unless$}
            depth -= 1
            break if depth == 0

            content << Node.new(:variable_expression, expr_location, value: {
              name: expr_content,
              raw: raw,
            }
            )

          when %r{^/if$}, %r{^/each$}
            depth -= 1
            content << Node.new(:variable_expression, expr_location, value: {
              name: expr_content,
              raw: raw,
            }
            )
          when 'else'
            # This else belongs to a nested if block, not this unless block
            content << Node.new(:variable_expression, expr_location, value: {
              name: expr_content,
              raw: raw,
            }
            )
          else
            content << create_expression_node(expr_content, raw, expr_location)
          end
        else
          text_content = parse_text_until_handlebars
          content << create_text_node(text_content) unless text_content.empty?
        end
      end

      if depth > 0
        parse_error('Missing closing tag for {{#unless}}')
      end

      processed_content = post_process_content(content)

      Node.new(:unless_block, start_location, value: {
        condition: condition,
        content: processed_content,
      }
      )
    end

    def create_each_block(items_expression, start_location)
      # Parse the each block content
      content = []
      depth   = 1

      while !at_end? && depth > 0
        if current_char == '{' && peek_char == '{'
          expr_start = current_position
          consume('{{')

          raw = false
          if current_char == '{'
            raw = true
            advance
          end

          skip_whitespace
          expr_content = parse_expression_content(raw)
          skip_whitespace

          if raw
            consume('}}}') || parse_error("Expected '}}}'")
          else
            consume('}}') || parse_error("Expected '}}'")
          end

          expr_end      = current_position
          expr_location = create_location(expr_start, expr_end)

          case expr_content
          when /^#if\s+(.+)$/, /^#unless\s+(.+)$/, /^#each\s+(.+)$/
            depth += 1
            content << Node.new(:variable_expression, expr_location, value: {
              name: expr_content,
              raw: raw,
            }
            )
          when %r{^/each$}
            depth -= 1
            break if depth == 0

            content << Node.new(:variable_expression, expr_location, value: {
              name: expr_content,
              raw: raw,
            }
            )

          when %r{^/if$}, %r{^/unless$}
            depth -= 1
            content << Node.new(:variable_expression, expr_location, value: {
              name: expr_content,
              raw: raw,
            }
            )
          when 'else'
            # This else belongs to a nested if block, not this each block
            content << Node.new(:variable_expression, expr_location, value: {
              name: expr_content,
              raw: raw,
            }
            )
          else
            content << create_expression_node(expr_content, raw, expr_location)
          end
        else
          text_content = parse_text_until_handlebars
          content << create_text_node(text_content) unless text_content.empty?
        end
      end

      if depth > 0
        parse_error('Missing closing tag for {{#each}}')
      end

      processed_content = post_process_content(content)

      Node.new(:each_block, start_location, value: {
        items: items_expression,
        content: processed_content,
      }
      )
    end

    def create_variable_node(name, raw, location)
      Node.new(:variable_expression, location, value: {
        name: name,
        raw: raw,
      }
      )
    end

    def create_partial_node(name, location)
      Node.new(:partial_expression, location, value: {
        name: name,
      }
      )
    end

    def create_text_node(text)
      pos      = current_position
      location = create_location(pos, pos)
      Node.new(:text, location, value: text)
    end

    def post_process_content(content)
      # Convert variable expressions that are actually block expressions
      processed = []
      i         = 0

      while i < content.length
        node = content[i]

        if node.type == :variable_expression
          case node.value[:name]
          when /^#if\s+(.+)$/
            condition                           = Regexp.last_match(1).strip
            if_content, else_content, end_index = extract_block_content_from_array(content, i + 1, 'if')
            processed << Node.new(:if_block, node.location, value: {
              condition: condition,
              if_content: post_process_content(if_content),
              else_content: post_process_content(else_content),
            }
            )
            i                                   = end_index
          when /^#unless\s+(.+)$/
            condition                   = Regexp.last_match(1).strip
            block_content, _, end_index = extract_block_content_from_array(content, i + 1, 'unless')
            processed << Node.new(:unless_block, node.location, value: {
              condition: condition,
              content: post_process_content(block_content),
            }
            )
            i                           = end_index
          when /^#each\s+(.+)$/
            items                       = Regexp.last_match(1).strip
            block_content, _, end_index = extract_block_content_from_array(content, i + 1, 'each')
            processed << Node.new(:each_block, node.location, value: {
              items: items,
              content: post_process_content(block_content),
            }
            )
            i                           = end_index
          when %r{^/\w+$}, 'else'
            # Skip closing tags and else - they're handled by block extraction
            i += 1
          else
            processed << node
            i += 1
          end
        else
          processed << node
          i += 1
        end
      end

      processed
    end

    def extract_block_content_from_array(content, start_index, block_type)
      block_content   = []
      else_content    = []
      current_content = block_content
      depth           = 1
      i               = start_index

      while i < content.length && depth > 0
        node = content[i]

        if node.type == :variable_expression
          case node.value[:name]
          when /^##{block_type}\s+/
            depth += 1
            current_content << node
          when %r{^/#{block_type}$}
            depth -= 1
            return [block_content, else_content, i + 1] if depth == 0

            current_content << node

          when 'else'
            if block_type == 'if' && depth == 1
              current_content = else_content
            else
              current_content << node
            end
          else
            current_content << node
          end
        else
          current_content << node
        end

        i += 1
      end

      [block_content, else_content, i]
    end

    def parse_text_until_handlebars
      chars = []

      while !at_end? && !(current_char == '{' && peek_char == '{')
        chars << current_char
        advance
      end

      chars.join
    end

    def collect_variables(node)
      variables = []

      case node.type
      when :variable_expression
        variables << node.value[:name]
      when :if_block
        variables << node.value[:condition]
        variables.concat(node.value[:if_content].flat_map { |child| collect_variables(child) })
        variables.concat(node.value[:else_content].flat_map { |child| collect_variables(child) })
      when :unless_block
        variables << node.value[:condition]
        variables.concat(node.value[:content].flat_map { |child| collect_variables(child) })
      when :each_block
        variables << node.value[:items]
        variables.concat(node.value[:content].flat_map { |child| collect_variables(child) })
      else
        variables.concat(node.children.flat_map { |child| collect_variables(child) })
      end

      variables.uniq
    end

    def collect_partials(node)
      partials = []

      case node.type
      when :partial_expression
        partials << node.value[:name]
      when :if_block
        partials.concat(node.value[:if_content].flat_map { |child| collect_partials(child) })
        partials.concat(node.value[:else_content].flat_map { |child| collect_partials(child) })
      when :unless_block, :each_block
        partials.concat(node.value[:content].flat_map { |child| collect_partials(child) })
      else
        partials.concat(node.children.flat_map { |child| collect_partials(child) })
      end

      partials.uniq
    end

    def collect_blocks(node)
      blocks = []

      case node.type
      when :if_block, :unless_block, :each_block
        blocks << node
        # Also collect nested blocks
        if node.type == :if_block
          blocks.concat(node.value[:if_content].flat_map { |child| collect_blocks(child) })
          blocks.concat(node.value[:else_content].flat_map { |child| collect_blocks(child) })
        else
          blocks.concat(node.value[:content].flat_map { |child| collect_blocks(child) })
        end
      else
        blocks.concat(node.children.flat_map { |child| collect_blocks(child) })
      end

      blocks
    end

    # Utility methods
    def current_char
      return "\0" if at_end?

      @content[@position]
    end

    def peek_char
      return "\0" if @position + 1 >= @content.length

      @content[@position + 1]
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

    def create_location(start_pos, end_pos)
      Location.new(
        start_line: start_pos[:line],
        start_column: start_pos[:column],
        end_line: end_pos[:line],
        end_column: end_pos[:column],
        start_offset: start_pos[:offset],
        end_offset: end_pos[:offset],
      )
    end

    def parse_error(message)
      raise ParseError.new(message, line: @line, column: @column, offset: @position)
    end
  end
end
