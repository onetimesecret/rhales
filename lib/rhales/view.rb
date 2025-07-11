# lib/rhales/view.rb

require 'securerandom'
require_relative 'context'
require_relative 'rue_document'
require_relative 'template_engine'
require_relative 'hydrator'
require_relative 'view_composition'
require_relative 'hydration_data_aggregator'
require_relative 'csp'
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
  # - All props passed to View.new
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

    attr_reader :req, :sess, :cust, :locale, :rsfc_context, :props, :config

    def initialize(req, sess = nil, cust = nil, locale_override = nil, props: {}, config: nil)
      @req           = req
      @sess          = sess
      @cust          = cust
      @locale        = locale_override
      @props         = props
      @config        = config || Rhales.configuration

      # Create context using the specified context class
      @rsfc_context = create_context
    end

    # Render RSFC template with hydration using two-pass architecture
    def render(template_name = nil)
      template_name ||= self.class.default_template_name

      # Phase 1: Build view composition and aggregate data
      composition           = build_view_composition(template_name)
      aggregator            = HydrationDataAggregator.new(@rsfc_context)
      merged_hydration_data = aggregator.aggregate(composition)

      # Phase 2: Render HTML with pre-computed data
      # Render template content
      template_html = render_template_with_composition(composition, template_name)

      # Generate hydration HTML with merged data
      hydration_html = generate_hydration_from_merged_data(merged_hydration_data)

      # Set CSP header if enabled
      set_csp_header_if_enabled

      # Smart hydration injection with mount point detection
      inject_hydration_with_mount_points(composition, template_name, template_html, hydration_html)
    rescue StandardError => ex
      raise RenderError, "Failed to render template '#{template_name}': #{ex.message}"
    end

    # Render only the template section (without data hydration)
    def render_template_only(template_name = nil)
      template_name ||= self.class.default_template_name

      # Build composition for consistent behavior
      composition = build_view_composition(template_name)
      render_template_with_composition(composition, template_name)
    end

    # Render JSON response for API endpoints (link-based strategies)
    def render_json_only(template_name = nil, additional_context = {})
      require_relative 'hydration_endpoint'

      template_name ||= self.class.default_template_name
      endpoint = HydrationEndpoint.new(@config, @rsfc_context)
      endpoint.render_json(template_name, additional_context)
    end

    # Render ES module response for modulepreload strategy
    def render_module_only(template_name = nil, additional_context = {})
      require_relative 'hydration_endpoint'

      template_name ||= self.class.default_template_name
      endpoint = HydrationEndpoint.new(@config, @rsfc_context)
      endpoint.render_module(template_name, additional_context)
    end

    # Render JSONP response with callback
    def render_jsonp_only(template_name = nil, callback_name = 'callback', additional_context = {})
      require_relative 'hydration_endpoint'

      template_name ||= self.class.default_template_name
      endpoint = HydrationEndpoint.new(@config, @rsfc_context)
      endpoint.render_jsonp(template_name, callback_name, additional_context)
    end

    # Check if template data has changed for caching
    def data_changed?(template_name = nil, etag = nil, additional_context = {})
      require_relative 'hydration_endpoint'

      template_name ||= self.class.default_template_name
      endpoint = HydrationEndpoint.new(@config, @rsfc_context)
      endpoint.data_changed?(template_name, etag, additional_context)
    end

    # Calculate ETag for current template data
    def calculate_etag(template_name = nil, additional_context = {})
      require_relative 'hydration_endpoint'

      template_name ||= self.class.default_template_name
      endpoint = HydrationEndpoint.new(@config, @rsfc_context)
      endpoint.calculate_etag(template_name, additional_context)
    end

    # Generate only the data hydration HTML
    def render_hydration_only(template_name = nil)
      template_name ||= self.class.default_template_name

      # Build composition and aggregate data
      composition           = build_view_composition(template_name)
      aggregator            = HydrationDataAggregator.new(@rsfc_context)
      merged_hydration_data = aggregator.aggregate(composition)

      # Generate hydration HTML
      generate_hydration_from_merged_data(merged_hydration_data)
    end

    # Get processed data as hash (for API endpoints or testing)
    def data_hash(template_name = nil)
      template_name ||= self.class.default_template_name

      # Build composition and aggregate data
      composition = build_view_composition(template_name)
      aggregator  = HydrationDataAggregator.new(@rsfc_context)
      aggregator.aggregate(composition)
    end

    protected

    # Create the appropriate context for this view
    # Subclasses can override this to use different context types
    def create_context
      context_class.for_view(@req, @sess, @cust, @locale, config: @config, **@props)
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
      boot_root = File.expand_path('../../..', __dir__)
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

      # Render with full server context (props + computed context + rue data)
      TemplateEngine.render(template_content, context_with_rue_data, partial_resolver: partial_resolver)
    end

    # Create partial resolver for {{> partial}} inclusions
    def create_partial_resolver
      templates_dir = File.join(templates_root, 'web')

      proc do |partial_name|
        partial_path = File.join(templates_dir, "#{partial_name}.rue")

        if File.exist?(partial_path)
          # Return full partial content so TemplateEngine can process
          # data sections, otherwise nil.
          File.read(partial_path)
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

      # Merge rue data with existing props (rue data takes precedence)
      merged_props = @props.merge(rue_data)

      # Create new context with merged data
      context_class.for_view(@req, @sess, @cust, @locale, config: @config, **merged_props)
    end

    # Extract and process data from .rue file's data section
    def extract_rue_data(parser)
      data_content = parser.section('data')
      return {} unless data_content

      # Process the data section as JSON and parse it
      hydrator = Hydrator.new(parser, @rsfc_context)
      hydrator.processed_data_hash
    rescue JSON::ParserError, Hydrator::JSONSerializationError => ex
      puts "Error processing data section: #{ex.message}"
      # If data section isn't valid JSON, return empty hash
      # This allows templates to work even with malformed data sections
      {}
    end

    # Smart hydration injection with mount point detection on rendered HTML
    def inject_hydration_with_mount_points(composition, template_name, template_html, hydration_html)
      injector = HydrationInjector.new(@config.hydration, template_name)

      # Check if using link-based strategy
      if @config.hydration.link_based_strategy?
        # For link-based strategies, we need the merged data context
        aggregator = HydrationDataAggregator.new(@rsfc_context)
        merged_data = aggregator.aggregate(composition)
        nonce = @rsfc_context.get('nonce')

        injector.inject_link_based_strategy(template_html, merged_data, nonce)
      else
        # Traditional strategies (early, earliest, late)
        mount_point = detect_mount_point_in_rendered_html(template_html)
        injector.inject(template_html, hydration_html, mount_point)
      end
    end

    # Legacy injection method (kept for backwards compatibility)
    def inject_hydration_into_template(template_html, hydration_html)
      # Try to inject before closing </body> tag
      if template_html.include?('</body>')
        template_html.sub('</body>', "#{hydration_html}\n</body>")
      # Otherwise append to end
      else
        "#{template_html}\n#{hydration_html}"
      end
    end

    # Detect mount points in fully rendered HTML
    def detect_mount_point_in_rendered_html(template_html)
      return nil unless @config&.hydration

      custom_selectors = @config.hydration.mount_point_selectors || []
      detector = MountPointDetector.new
      detector.detect(template_html, custom_selectors)
    end

    # Build view composition for the given template
    def build_view_composition(template_name)
      loader      = method(:load_template_for_composition)
      composition = ViewComposition.new(template_name, loader: loader, config: @config)
      composition.resolve!
    end

    # Loader proc for ViewComposition
    def load_template_for_composition(template_name)
      template_path = resolve_template_path(template_name)
      return nil unless File.exist?(template_path)

      require template_path
    rescue StandardError => ex
      raise TemplateNotFoundError, "Failed to load template #{template_name}: #{ex.message}"
    end

    # Render template using the view composition
    def render_template_with_composition(composition, root_template_name)
      root_parser      = composition.template(root_template_name)
      template_content = root_parser.section('template')
      return '' unless template_content

      # Create partial resolver that uses the composition
      partial_resolver = create_partial_resolver_from_composition(composition)

      # Merge .rue file data with existing context
      context_with_rue_data = create_context_with_rue_data(root_parser)

      # Check if template has a layout
      if root_parser.layout && composition.template(root_parser.layout)
        # Render content template first
        content_html = TemplateEngine.render(template_content, context_with_rue_data, partial_resolver: partial_resolver)

        # Then render layout with content
        layout_parser  = composition.template(root_parser.layout)
        layout_content = layout_parser.section('template')
        return '' unless layout_content

        # Create new context with content for layout rendering
        layout_props   = context_with_rue_data.props.merge('content' => content_html)
        layout_context = Context.new(
          context_with_rue_data.req,
          context_with_rue_data.sess,
          context_with_rue_data.cust,
          context_with_rue_data.locale,
          props: layout_props,
          config: context_with_rue_data.config,
        )

        TemplateEngine.render(layout_content, layout_context, partial_resolver: partial_resolver)
      else
        # Render with full server context (no layout)
        TemplateEngine.render(template_content, context_with_rue_data, partial_resolver: partial_resolver)
      end
    end

    # Create partial resolver that uses pre-loaded templates from composition
    def create_partial_resolver_from_composition(composition)
      proc do |partial_name|
        parser = composition.template(partial_name)
        parser ? parser.content : nil
      end
    end

    # Generate hydration HTML from pre-merged data
    def generate_hydration_from_merged_data(merged_data)
      hydration_parts = []

      merged_data.each do |window_attr, data|
        # Generate unique ID for this data block
        unique_id = "rsfc-data-#{SecureRandom.hex(8)}"

        # Create JSON script tag with optional reflection attributes
        json_attrs = reflection_enabled? ? " data-window=\"#{window_attr}\"" : ""
        json_script = <<~HTML.strip
          <script id="#{unique_id}" type="application/json"#{json_attrs}>#{JSON.generate(data)}</script>
        HTML

        # Create hydration script with optional reflection attributes
        nonce_attr = nonce_attribute
        hydration_attrs = reflection_enabled? ? " data-hydration-target=\"#{window_attr}\"" : ""
        hydration_script = if reflection_enabled?
          <<~HTML.strip
            <script#{nonce_attr}#{hydration_attrs}>
            var dataScript = document.getElementById('#{unique_id}');
            var targetName = dataScript.getAttribute('data-window') || '#{window_attr}';
            window[targetName] = JSON.parse(dataScript.textContent);
            </script>
          HTML
        else
          <<~HTML.strip
            <script#{nonce_attr}#{hydration_attrs}>
            window.#{window_attr} = JSON.parse(document.getElementById('#{unique_id}').textContent);
            </script>
          HTML
        end

        hydration_parts << json_script
        hydration_parts << hydration_script
      end

      # Add reflection utilities if enabled
      if reflection_enabled? && !merged_data.empty?
        hydration_parts << generate_reflection_utilities
      end

      hydration_parts.join("\n")
    end

    # Check if reflection system is enabled
    def reflection_enabled?
      @config.hydration.reflection_enabled
    end

    # Generate JavaScript utilities for hydration reflection
    def generate_reflection_utilities
      nonce_attr = nonce_attribute

      <<~HTML.strip
        <script#{nonce_attr}>
        // Rhales hydration reflection utilities
        window.__rhales__ = window.__rhales__ || {
          getHydrationTargets: function() {
            return Array.from(document.querySelectorAll('[data-hydration-target]'));
          },
          getDataForTarget: function(target) {
            var targetName = target.dataset.hydrationTarget;
            return window[targetName];
          },
          getWindowAttribute: function(scriptEl) {
            return scriptEl.dataset.window;
          },
          getDataScripts: function() {
            return Array.from(document.querySelectorAll('script[data-window]'));
          },
          refreshData: function(target) {
            var targetName = target.dataset.hydrationTarget;
            var dataScript = document.querySelector('script[data-window="' + targetName + '"]');
            if (dataScript) {
              try {
                window[targetName] = JSON.parse(dataScript.textContent);
                return true;
              } catch (e) {
                console.error('Rhales: Failed to refresh data for ' + targetName, e);
                return false;
              }
            }
            return false;
          },
          getAllHydrationData: function() {
            var data = {};
            this.getHydrationTargets().forEach(function(target) {
              var targetName = target.dataset.hydrationTarget;
              data[targetName] = window[targetName];
            });
            return data;
          }
        };
        </script>
      HTML
    end

    # Get nonce attribute if available
    def nonce_attribute
      nonce = @rsfc_context.get('nonce')
      nonce ? " nonce=\"#{nonce}\"" : ''
    end

    # Set CSP header if enabled
    def set_csp_header_if_enabled
      return unless @config.csp_enabled
      return unless @req && @req.respond_to?(:env)

      # Get nonce from context
      nonce = @rsfc_context.get('nonce')

      # Create CSP instance and build header
      csp = CSP.new(@config, nonce: nonce)
      header_value = csp.build_header

      # Set header in request environment for framework to use
      @req.env['csp_header'] = header_value if header_value
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

      # Render template with props
      def render_with_data(req, sess, cust, locale, template_name: nil, config: nil, **props)
        view = new(req, sess, cust, locale, props: props, config: config)
        view.render(template_name)
      end

      # Create view instance with props
      def with_data(req, sess, cust, locale, config: nil, **props)
        new(req, sess, cust, locale, props: props, config: config)
      end
    end
  end
end
