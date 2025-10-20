# lib/rhales/template_engine.rb

require 'erb'
require_relative '../parsers/rue_format_parser'
require_relative '../parsers/handlebars_parser'
require_relative 'rue_document'
require_relative '../hydration/hydrator'

module Rhales
  # Rhales - Ruby Handlebars-style template engine
  #
  # Modern AST-based template engine that supports both simple template strings
  # and full .rue files. Uses RueFormatParser for parsing with proper
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
    class RenderError < ::Rhales::RenderError; end
    class PartialNotFoundError < RenderError; end
    class UndefinedVariableError < RenderError; end
    class BlockNotFoundError < RenderError; end

    attr_reader :template_content, :context, :partial_resolver, :parser

    def initialize(template_content, context, partial_resolver: nil)
      @template_content = template_content
      @context          = context
      @partial_resolver = partial_resolver
      @parser           = nil
    end

    def render
      # Check if this is a simple template or a full .rue file
      if simple_template?
        # Use HandlebarsParser for simple templates
        parser = HandlebarsParser.new(@template_content)
        parser.parse!
        render_content_nodes(parser.ast.children)
      else
        # Use RueDocument for .rue files
        @parser = RueDocument.new(@template_content)
        @parser.parse!

        # Get template section via RueDocument
        template_content = @parser.section('template')
        raise RenderError, 'Missing template section' unless template_content

        # Render the template section as a simple template
        render_template_string(template_content)
      end
    rescue ::Rhales::ParseError => ex
      # Parse errors already have good error messages with location
      raise RenderError, "Template parsing failed: #{ex.message}"
    rescue ::Rhales::ValidationError => ex
      # Validation errors from RueDocument
      raise RenderError, "Template validation failed: #{ex.message}"
    rescue StandardError => ex
      raise RenderError, "Template rendering failed: #{ex.message}"
    end

    # Access window attribute from parsed .rue file
    def window_attribute
      @parser&.window_attribute
    end

    # Access schema path from parsed .rue file
    def schema_path
      @parser&.schema_path
    end



    # Get template variables used in the template
    def template_variables
      @parser&.template_variables || []
    end

    # Get all partials used in the template
    def partials
      @parser&.partials || []
    end

    private

    def simple_template?
      !@template_content.match?(/^<(schema|template|logic)\b/)
    end

    def render_template_string(template_string)
      # Parse the template string as a simple Handlebars template
      parser = HandlebarsParser.new(template_string)
      parser.parse!
      render_content_nodes(parser.ast.children)
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
          # Handle handlebars expressions
          result += render_handlebars_expression(node)
        end
      end

      result
    end

    def render_variable_expression(node)
      name = node.value[:name]
      raw  = node.value[:raw]

      value = get_variable_value(name)
      raw ? value.to_s : escape_html(value.to_s)
    end

    def render_partial_expression(node)
      partial_name = node.value[:name]
      render_partial(partial_name)
    end

    def render_if_block(node)
      condition    = node.value[:condition]
      if_content   = node.value[:if_content]
      else_content = node.value[:else_content]

      if evaluate_condition(condition)
        render_content_nodes(if_content)
      else
        render_content_nodes(else_content)
      end
    end

    def render_unless_block(node)
      condition = node.value[:condition]
      content   = node.value[:content]

      if evaluate_condition(condition)
        ''
      else
        render_content_nodes(content)
      end
    end

    def render_each_block(node)
      items_var     = node.value[:items]
      block_content = node.value[:content]

      items = get_variable_value(items_var)

      if items.respond_to?(:each)
        items.map.with_index do |item, index|
          # Create context for each iteration
          item_context = create_each_context(item, index, items_var)
          engine       = self.class.new('', item_context, partial_resolver: @partial_resolver)
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
      when %r{^(#|/)(if|unless|each)} # Block statements (should be handled by render_content_nodes)
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

      # Check if this is a .rue document with sections
      if partial_content.match?(/^<(schema|template|logic)\b/)
        # Parse as RueDocument to handle schema sections properly
        partial_doc = RueDocument.new(partial_content)
        partial_doc.parse!

        # Extract template section
        template_content = partial_doc.section('template')
        raise PartialNotFoundError, "Partial '#{partial_name}' missing template section" unless template_content

        # Render template with current context
        engine = self.class.new(template_content, @context, partial_resolver: @partial_resolver)
        engine.render
      else
        # Simple template without sections - render as before
        engine = self.class.new(partial_content, @context, partial_resolver: @partial_resolver)
        engine.render
      end
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
      when 'false', 'False', 'FALSE'
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

      def respond_to_missing?(method_name, include_private = false)
        super || @parent_context.respond_to?(method_name, include_private)
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
            document = RueDocument.parse_file(partial_path)
            document.section('template')
          end
        end
      end
    end
  end
end
