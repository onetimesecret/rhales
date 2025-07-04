# lib/rhales/template_engine.rb

require 'erb'
require_relative 'grammars/rue'

module Rhales
  # Rhales - Ruby Handlebars-style template engine
  #
  # AST-based template engine using RueGrammar for parsing.
  # Supports variable interpolation, conditionals, iteration, and partials
  # with proper nested structure handling.
  #
  # Supported syntax:
  # - {{variable}} - Variable interpolation with HTML escaping
  # - {{{variable}}} - Raw variable interpolation (no escaping)
  # - {{#if condition}} ... {{/if}} - Conditionals
  # - {{#unless condition}} ... {{/unless}} - Negated conditionals
  # - {{#each items}} ... {{/each}} - Iteration
  # - {{> partial_name}} - Partial inclusion
  class TemplateEngine
    class RenderError < StandardError; end
    class PartialNotFoundError < RenderError; end
    class UndefinedVariableError < RenderError; end
    class BlockNotFoundError < RenderError; end

    attr_reader :template_content, :context, :partial_resolver

    def initialize(template_content, context, partial_resolver: nil)
      @template_content = template_content
      @context = context
      @partial_resolver = partial_resolver
    end

    def render
      # For simple templates (just handlebars expressions), parse directly
      if simple_template?
        render_simple_template
      else
        # For complex templates with sections, use grammar
        grammar = RueGrammar.new(@template_content)
        grammar.parse!
        render_node(grammar.ast)
      end
    rescue RueGrammar::ParseError => e
      raise RenderError, "Template parsing failed: #{e.message}"
    rescue StandardError => e
      raise RenderError, "Template rendering failed: #{e.message}"
    end

    private

    def simple_template?
      !@template_content.match?(/^<(data|template|logic)\b/)
    end

    def render_simple_template
      # Parse handlebars expressions directly without section structure
      content = @template_content.dup

      # Process block statements first (they can contain other expressions)
      content = process_block_expressions(content)

      # Process partials
      content = process_partial_expressions(content)

      # Process variables
      process_variable_expressions(content)
    end

    def render_node(node)
      case node.type
      when :rue_file
        # For .rue files, only render template section
        template_section = node.children.find { |child| child.value[:tag] == 'template' }
        return '' unless template_section

        render_section_content(template_section.value[:content])
      when :section
        render_section_content(node.value[:content])
      when :text
        node.value
      when :handlebars_expression
        render_handlebars_expression(node)
      else
        ''
      end
    end

    def render_section_content(content_nodes)
      content_nodes.map { |node| render_node(node) }.join
    end

    def render_handlebars_expression(node)
      content = node.value[:content]
      raw = node.value[:raw]

      # Handle different expression types
      case content
      when /^>\s*(\w+)/ # Partials
        render_partial(Regexp.last_match(1))
      when /^#if\s+(.+)/ # If blocks
        render_if_block(Regexp.last_match(1), content)
      when /^#unless\s+(.+)/ # Unless blocks
        render_unless_block(Regexp.last_match(1), content)
      when /^#each\s+(.+)/ # Each blocks
        render_each_block(Regexp.last_match(1), content)
      else # Variables
        value = get_variable_value(content)
        raw ? value.to_s : escape_html(value.to_s)
      end
    end

    def render_partial(partial_name)
      return "{{> #{partial_name}}}" unless @partial_resolver

      partial_content = @partial_resolver.call(partial_name)
      raise PartialNotFoundError, "Partial '#{partial_name}' not found" unless partial_content

      # Recursively render the partial content
      engine = self.class.new(partial_content, @context, partial_resolver: @partial_resolver)
      engine.render
    end

    def render_if_block(condition, full_content)
      # This is a simplified version - for full block parsing, we'd need to parse the template
      # and find the matching {{/if}} with proper nesting
      raise BlockNotFoundError, "Block parsing not implemented for AST nodes yet"
    end

    def render_unless_block(condition, full_content)
      # This is a simplified version - for full block parsing, we'd need to parse the template
      # and find the matching {{/unless}} with proper nesting
      raise BlockNotFoundError, "Block parsing not implemented for AST nodes yet"
    end

    def render_each_block(items_var, full_content)
      # This is a simplified version - for full block parsing, we'd need to parse the template
      # and find the matching {{/each}} with proper nesting
      raise BlockNotFoundError, "Block parsing not implemented for AST nodes yet"
    end

    # Process block expressions in simple templates
    def process_block_expressions(content)
      # Process nested blocks from inside out
      loop do
        original_content = content

        # Process if blocks
        content = process_if_blocks(content)

        # Process unless blocks
        content = process_unless_blocks(content)

        # Process each blocks
        content = process_each_blocks(content)

        # Break if no more changes
        break if content == original_content
      end

      content
    end

    def process_if_blocks(content)
      content.gsub(/\{\{\s*#if\s+([^}]+)\s*\}\}(.*?)\{\{\s*\/if\s*\}\}/m) do |match|
        condition = Regexp.last_match(1).strip
        block_content = Regexp.last_match(2)

        # Check for {{else}} clause
        if block_content.include?('{{else}}')
          if_part, else_part = block_content.split(/\{\{\s*else\s*\}\}/, 2)
          if evaluate_condition(condition)
            render_template_content(if_part)
          else
            render_template_content(else_part)
          end
        elsif evaluate_condition(condition)
          render_template_content(block_content)
        else
          ''
        end
      end
    end

    def process_unless_blocks(content)
      content.gsub(/\{\{\s*#unless\s+([^}]+)\s*\}\}(.*?)\{\{\s*\/unless\s*\}\}/m) do |match|
        condition = Regexp.last_match(1).strip
        block_content = Regexp.last_match(2)

        if evaluate_condition(condition)
          ''
        else
          render_template_content(block_content)
        end
      end
    end

    def process_each_blocks(content)
      content.gsub(/\{\{\s*#each\s+([^}]+)\s*\}\}(.*?)\{\{\s*\/each\s*\}\}/m) do |match|
        items_var = Regexp.last_match(1).strip
        block_content = Regexp.last_match(2)

        items = get_variable_value(items_var)

        if items.respond_to?(:each)
          items.map.with_index do |item, index|
            # Create context for each iteration
            item_context = create_each_context(item, index, items_var)
            engine = self.class.new(block_content, item_context, partial_resolver: @partial_resolver)
            engine.render
          end.join
        else
          ''
        end
      end
    end

    def process_partial_expressions(content)
      content.gsub(/\{\{\s*>\s*(\w+)\s*\}\}/) do |match|
        partial_name = Regexp.last_match(1)
        render_partial(partial_name)
      end
    end

    def process_variable_expressions(content)
      # Process raw variables first {{{variable}}}
      content = content.gsub(/\{\{\{\s*([^}]+)\s*\}\}\}/) do |match|
        variable_name = Regexp.last_match(1).strip
        value = get_variable_value(variable_name)
        value.to_s
      end

      # Process escaped variables {{variable}}
      content.gsub(/\{\{\s*([^}]+)\s*\}\}/) do |match|
        variable_name = Regexp.last_match(1).strip
        # Skip if it's a block statement or partial
        next match if variable_name.match?(/^(#|\/|>)/)

        value = get_variable_value(variable_name)
        escape_html(value.to_s)
      end
    end

    def render_template_content(content)
      engine = self.class.new(content, @context, partial_resolver: @partial_resolver)
      engine.render
    end

    # Get variable value from context
    def get_variable_value(variable_name)
      # Handle special variables
      case variable_name
      when 'this', '.'
        return @context.respond_to?(:current_item) ? @context.current_item : nil
      when '@index'
        return @context.respond_to?(:current_index) ? @context.current_index : nil
      end

      # Get from context
      if @context.respond_to?(:get)
        @context.get(variable_name)
      elsif @context.respond_to?(:[])
        @context[variable_name] || @context[variable_name.to_sym]
      else
        nil
      end
    end

    # Evaluate condition for if/unless blocks
    def evaluate_condition(condition)
      value = get_variable_value(condition)

      # Handle truthy/falsy evaluation
      case value
      when nil, false
        false
      when ''
        false
      when Array
        !value.empty?
      when Hash
        !value.empty?
      when 0
        false
      else
        true
      end
    end

    # Create context for each iteration
    def create_each_context(item, index, items_var)
      EachContext.new(@context, item, index, items_var)
    end

    # HTML escape for XSS protection
    def escape_html(string)
      ERB::Util.html_escape(string)
    end

    # Context wrapper for {{#each}} iterations
    class EachContext
      attr_reader :parent_context, :current_item, :current_index, :items_var

      def initialize(parent_context, current_item, current_index, items_var)
        @parent_context = parent_context
        @current_item = current_item
        @current_index = current_index
        @items_var = items_var
      end

      def get(variable_name)
        # Handle special each variables
        case variable_name
        when 'this', '.'
          return @current_item
        when '@index'
          return @current_index
        when '@first'
          return @current_index == 0
        when '@last'
          # We'd need to know the total length for this
          return false
        end

        # Check if it's a property of the current item
        if @current_item.respond_to?(:[])
          item_value = @current_item[variable_name] || @current_item[variable_name.to_sym]
          return item_value unless item_value.nil?
        end

        if @current_item.respond_to?(variable_name)
          return @current_item.public_send(variable_name)
        end

        # Fall back to parent context
        @parent_context.get(variable_name) if @parent_context.respond_to?(:get)
      end

      def respond_to?(method_name)
        super || @parent_context.respond_to?(method_name)
      end

      def method_missing(method_name, *args)
        if @parent_context.respond_to?(method_name)
          @parent_context.public_send(method_name, *args)
        else
          super
        end
      end
    end

    class << self
      # Render template with context and optional partial resolver
      def render(template_content, context, partial_resolver: nil)
        new(template_content, context, partial_resolver: partial_resolver).render
      end

      # Create partial resolver that loads .rue files from a directory
      def file_partial_resolver(templates_dir)
        proc do |partial_name|
          partial_path = File.join(templates_dir, "#{partial_name}.rue")

          if File.exist?(partial_path)
            # Load and parse the partial .rue file
            parser = Parser.parse_file(partial_path)
            parser.section('template')
          else
            nil
          end
        end
      end
    end
  end
end
