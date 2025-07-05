# lib/rhales/template_engine.rb

require 'erb'
require_relative 'grammars/rue'
require_relative 'grammars/handlebars'

module Rhales
  # Rhales - Ruby Handlebars-style template engine
  #
  # Modern AST-based template engine that supports both simple template strings
  # and full .rue files. Uses RueGrammar for formal parsing with proper
  # nested structure handling and block statement support.
  #
  # Features:
  # - Dual-mode operation: simple templates and .rue files
  # - Full AST parsing eliminates regex-based vulnerabilities
  # - Proper nested block handling with accurate error reporting
  # - XSS protection through HTML escaping by default
  # - Handlebars-compatible syntax with Ruby idioms
  #
  # Supported syntax:
  # - {{variable}} - Variable interpolation with HTML escaping
  # - {{{variable}}} - Raw variable interpolation (no escaping)
  # - {{#if condition}} ... {{else}} ... {{/if}} - Conditionals with else
  # - {{#unless condition}} ... {{/unless}} - Negated conditionals
  # - {{#each items}} ... {{/each}} - Iteration with context
  # - {{> partial_name}} - Partial inclusion
  class TemplateEngine
    class RenderError < StandardError; end
    class PartialNotFoundError < RenderError; end
    class UndefinedVariableError < RenderError; end
    class BlockNotFoundError < RenderError; end

    attr_reader :template_content, :context, :partial_resolver

    def initialize(template_content, context, partial_resolver: nil)
      @template_content = template_content
      @context          = context
      @partial_resolver = partial_resolver
    end

    def render
      # Check if this is a simple template or a full .rue file
      if simple_template?
        # Use HandlebarsGrammar for simple templates
        grammar = HandlebarsGrammar.new(@template_content)
        grammar.parse!
        render_content_nodes(grammar.ast.children)
      else
        # Parse .rue file using RueGrammar
        grammar = RueGrammar.new(@template_content)
        grammar.parse!
        render_node(grammar.ast)
      end
    rescue RueGrammar::ParseError => ex
      raise RenderError, "Template parsing failed: #{ex.message}"
    rescue HandlebarsGrammar::ParseError => ex
      raise RenderError, "Template parsing failed: #{ex.message}"
    rescue StandardError => ex
      raise RenderError, "Template rendering failed: #{ex.message}"
    end

    private

    def simple_template?
      !@template_content.match?(/^<(data|template|logic)\b/)
    end

    def render_node(node)
      case node.type
      when :rue_file
        # For .rue files, only render template section
        template_section = node.children.find { |child| child.value[:tag] == 'template' }
        return '' unless template_section

        render_content_nodes(template_section.value[:content])
      when :section
        render_content_nodes(node.value[:content])
      when :text
        node.value
      when :handlebars_expression
        render_handlebars_expression(node)
      else
        ''
      end
    end

    # Render array of AST content nodes with proper block handling
    # Processes text nodes and AST block nodes directly
    def render_content_nodes(content_nodes)
      return '' unless content_nodes.is_a?(Array)

      result = ''

      content_nodes.each do |node|
        case node.type
        when :text
          result += node.value
        when :variable_expression
          result += render_variable_expression(node)
        when :partial_expression
          result += render_partial_expression(node)
        when :if_block
          result += render_if_block(node)
        when :unless_block
          result += render_unless_block(node)
        when :each_block
          result += render_each_block(node)
        when :handlebars_expression
          # Handle old format for data sections
          result += render_handlebars_expression(node)
        end
      end

      result
    end

    def render_variable_expression(node)
      name = node.value[:name]
      raw = node.value[:raw]

      value = get_variable_value(name)
      raw ? value.to_s : escape_html(value.to_s)
    end

    def render_partial_expression(node)
      partial_name = node.value[:name]
      render_partial(partial_name)
    end

    def render_if_block(node)
      condition = node.value[:condition]
      if_content = node.value[:if_content]
      else_content = node.value[:else_content]

      if evaluate_condition(condition)
        render_content_nodes(if_content)
      else
        render_content_nodes(else_content)
      end
    end

    def render_unless_block(node)
      condition = node.value[:condition]
      content = node.value[:content]

      if evaluate_condition(condition)
        ''
      else
        render_content_nodes(content)
      end
    end

    def render_each_block(node)
      items_var = node.value[:items]
      block_content = node.value[:content]

      items = get_variable_value(items_var)

      if items.respond_to?(:each)
        items.map.with_index do |item, index|
          # Create context for each iteration
          item_context = create_each_context(item, index, items_var)
          engine = self.class.new('', item_context, partial_resolver: @partial_resolver)
          engine.send(:render_content_nodes, block_content)
        end.join
      else
        ''
      end
    end

    def render_handlebars_expression(node)
      content = node.value[:content]
      raw     = node.value[:raw]

      # Handle different expression types
      case content
      when /^>\s*(\w+)/ # Partials
        render_partial(Regexp.last_match(1))
      when /^(#|\/)(if|unless|each)/ # Block statements (should be handled by render_content_nodes)
        ''
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
        @current_item   = current_item
        @current_index  = current_index
        @items_var      = items_var
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

      def method_missing(method_name, *)
        if @parent_context.respond_to?(method_name)
          @parent_context.public_send(method_name, *)
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
