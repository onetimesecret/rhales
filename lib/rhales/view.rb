# lib/rhales/view.rb

require_relative 'context'
require_relative 'rue_document'
require_relative 'template_engine'
require_relative 'hydrator'
require_relative 'refinements/require_refinements'

using Rhales::Ruequire

module Rhales
  # Complete RSFC view implementation
  #
  # Single public interface for RSFC template rendering that handles:
  # - Context creation (with pluggable context classes)
  # - Template loading and parsing
  # - Template rendering with Rhales
  # - Data hydration and injection
  #
  # ## Context and Data Boundaries
  #
  # Views implement a two-phase security model:
  #
  # ### Server Templates: Full Context Access
  # Templates have complete access to all server-side data:
  # - All business_data passed to View.new
  # - Data from .rue file's <data> section (processed server-side)
  # - Runtime data (CSRF tokens, nonces, request metadata)
  # - Computed data (authentication status, theme classes)
  # - User objects, configuration, internal APIs
  #
  # ### Client Data: Explicit Allowlist
  # Only data declared in <data> sections reahas_role?ches the browser:
  # - Creates a REST API-like boundary
  # - Server-side variable interpolation processes secrets safely
  # - JSON serialization validates data structure
  # - No accidental exposure of sensitive server data
  #
  # Example:
  #   # Server template has full access:
  #   {{user.admin?}} {{csrf_token}} {{internal_config}}
  #
  #   # Client only gets declared data:
  #   { "user_name": "{{user.name}}", "theme": "{{user.theme}}" }
  #
  # See docs/CONTEXT_AND_DATA_BOUNDARIES.md for complete details.
  #
  # Subclasses can override context_class to use different context implementations.
  class View
    class RenderError < StandardError; end
    class TemplateNotFoundError < RenderError; end

    attr_reader :req, :sess, :cust, :locale, :rsfc_context, :business_data, :config

    def initialize(req, sess = nil, cust = nil, locale_override = nil, business_data: {}, config: nil)
      @req           = req
      @sess          = sess
      @cust          = cust
      @locale        = locale_override
      @business_data = business_data
      @config        = config || Rhales.configuration

      # Create context using the specified context class
      @rsfc_context = create_context
    end

    # Render RSFC template with hydration
    def render(template_name = nil)
      template_name ||= self.class.default_template_name

      # Clear hydration registry for this request
      HydrationRegistry.clear!

      # Load and parse template
      parser = load_template(template_name)

      # Render template content
      template_html = render_template_section(parser)

      # Generate data hydration HTML
      hydration_html = generate_hydration(parser)

      # Combine template and hydration
      inject_hydration_into_template(template_html, hydration_html)
    rescue StandardError => ex
      raise RenderError, "Failed to render template '#{template_name}': #{ex.message}"
    end

    # Render only the template section (without data hydration)
    def render_template_only(template_name = nil)
      template_name ||= self.class.default_template_name
      parser          = load_template(template_name)
      render_template_section(parser)
    end

    # Generate only the data hydration HTML
    def render_hydration_only(template_name = nil)
      template_name ||= self.class.default_template_name

      # Clear hydration registry for this request
      HydrationRegistry.clear!

      parser = load_template(template_name)
      generate_hydration(parser)
    end

    # Get processed data as hash (for API endpoints or testing)
    def data_hash(template_name = nil)
      template_name ||= self.class.default_template_name
      parser          = load_template(template_name)
      Hydrator.generate_data_hash(parser, @rsfc_context)
    end

    protected

    # Create the appropriate context for this view
    # Subclasses can override this to use different context types
    def create_context
      context_class.for_view(@req, @sess, @cust, @locale, config: @config, **@business_data)
    end

    # Return the context class to use
    # Subclasses can override this to use different context implementations
    def context_class
      Context
    end

    private

    # Load and parse template
    def load_template(template_name)
      template_path = resolve_template_path(template_name)

      unless File.exist?(template_path)
        raise TemplateNotFoundError, "Template not found: #{template_path}"
      end

      # Use refinement to load .rue file
      require template_path
    end

    # Resolve template path
    def resolve_template_path(template_name)
      # Check configured template paths first
      if @config && @config.template_paths && !@config.template_paths.empty?
        @config.template_paths.each do |path|
          template_path = File.join(path, "#{template_name}.rue")
          return template_path if File.exist?(template_path)
        end
      end

      # Fallback to default template structure
      # First try templates/web directory
      web_path = File.join(templates_root, 'web', "#{template_name}.rue")
      return web_path if File.exist?(web_path)

      # Then try templates directory
      templates_path = File.join(templates_root, "#{template_name}.rue")
      return templates_path if File.exist?(templates_path)

      # Return first configured path or web path for error message
      if @config && @config.template_paths && !@config.template_paths.empty?
        File.join(@config.template_paths.first, "#{template_name}.rue")
      else
        web_path
      end
    end

    # Get templates root directory
    def templates_root
      boot_root = if defined?(OT) && OT.respond_to?(:boot_root)
                    OT.boot_root
                  else
                    File.expand_path('../../..', __dir__)
                  end
      File.join(boot_root, 'templates')
    end

    # Render template section with Rhales
    #
    # RSFC Security Model: Templates have full server context access
    # - Templates can access all business data, user objects, methods, etc.
    # - Templates can access data from .rue file's <data> section (processed server-side)
    # - This is like any server-side template (ERB, HAML, etc.)
    # - Security boundary is at server-to-client handoff, not within server rendering
    # - Only data declared in <data> section reaches the client (after processing)
    def render_template_section(parser)
      template_content = parser.section('template')
      return '' unless template_content

      # Create partial resolver
      partial_resolver = create_partial_resolver

      # Merge .rue file data with existing context
      context_with_rue_data = create_context_with_rue_data(parser)

      # Render with full server context (business data + computed context + rue data)
      TemplateEngine.render(template_content, context_with_rue_data, partial_resolver: partial_resolver)
    end

    # Create partial resolver for {{> partial}} inclusions
    def create_partial_resolver
      templates_dir = File.join(templates_root, 'web')

      proc do |partial_name|
        partial_path = File.join(templates_dir, "#{partial_name}.rue")

        if File.exist?(partial_path)
          # Parse partial and return template section
          partial_parser = require(partial_path)
          partial_parser.section('template')
        else
          nil
        end
      end
    end

    # Generate data hydration HTML
    def generate_hydration(parser)
      Hydrator.generate(parser, @rsfc_context)
    end

    # Create context that includes data from .rue file's data section
    def create_context_with_rue_data(parser)
      # Get data from .rue file's data section
      rue_data = extract_rue_data(parser)

      # Merge rue data with existing business data (rue data takes precedence)
      merged_business_data = @business_data.merge(rue_data)

      # Create new context with merged data
      context_class.for_view(@req, @sess, @cust, @locale, config: @config, **merged_business_data)
    end

    # Extract and process data from .rue file's data section
    def extract_rue_data(parser)
      data_content = parser.section('data')
      return {} unless data_content

      # Process the data section as JSON and parse it
      hydrator = Hydrator.new(parser, @rsfc_context)
      hydrator.processed_data_hash
    rescue JSON::ParserError, Hydrator::JSONSerializationError => ex
      # If data section isn't valid JSON, return empty hash
      # This allows templates to work even with malformed data sections
      {}
    end

    # Inject hydration HTML into template
    def inject_hydration_into_template(template_html, hydration_html)
      # Try to inject before closing </body> tag
      if template_html.include?('</body>')
        template_html.sub('</body>', "#{hydration_html}\n</body>")
      # Otherwise append to end
      else
        "#{template_html}\n#{hydration_html}"
      end
    end

    class << self
      # Get default template name based on class name
      def default_template_name
        # Convert ClassName to class_name
        name.split('::').last
          .gsub(/([A-Z])/, '_\1')
          .downcase
          .sub(/^_/, '')
          .sub(/_view$/, '')
      end

      # Render template with business data
      def render_with_data(req, sess, cust, locale, template_name: nil, config: nil, **business_data)
        view = new(req, sess, cust, locale, business_data: business_data, config: config)
        view.render(template_name)
      end

      # Create view instance with business data
      def with_data(req, sess, cust, locale, config: nil, **business_data)
        new(req, sess, cust, locale, business_data: business_data, config: config)
      end
    end
  end
end
