# lib/rhales/context.rb

require_relative 'configuration'
require_relative 'adapters/base_auth'
require_relative 'adapters/base_session'
require_relative 'adapters/base_request'
require_relative 'csp'

module Rhales
    # RSFCContext provides a clean interface for RSFC templates to access
    # server-side data. Follows the established pattern from InitScriptContext
    # and EnvironmentContext for focused, single-responsibility context objects.
    #
    # The context provides three layers of data:
    # 1. Request: Framework-provided data (CSRF tokens, authentication, config)
    # 2. Server: Template-only variables (page titles, HTML content, etc.)
    # 3. Client: Application data that gets serialized to window state
    #
    # Request data and server data are accessible in templates.
    # Client data takes precedence over server data for variable resolution.
    # Only client data is serialized to the browser via <schema> sections.
    #
    # One RSFCContext instance is created per page render and shared across
    # the main template and all partials to maintain security boundaries.
    class Context
      attr_reader :req, :locale, :client, :server, :config

      def initialize(req, locale_override = nil, client: {}, server: {}, config: nil)
        @req           = req
        @config        = config || Rhales.configuration
        @locale        = locale_override || @config.default_locale

        # Normalize keys to strings for consistent access and expose with clean names
        @client_data = normalize_keys(client).freeze
        @client = @client_data  # Public accessor

        # Build context layers (three-layer model: request + server + client)
        # Server data is merged with built-in request/app data
        @server_data = build_app_data.merge(normalize_keys(server)).freeze
        @server = @server_data  # Public accessor

        # Pre-compute all_data before freezing
        # Client takes precedence over server, and add app namespace for backward compatibility
        @all_data = @server_data.merge(@client_data).merge({ 'app' => @server_data }).freeze

        # Make context immutable after creation
        freeze
      end

      # Get variable value with dot notation support (e.g., "user.id", "features.account_creation")
      def get(variable_path)
        path_parts    = variable_path.split('.')
        current_value = all_data

        path_parts.each do |part|
          case current_value
          when Hash
            if current_value.key?(part)
              current_value = current_value[part]
            elsif current_value.key?(part.to_sym)
              current_value = current_value[part.to_sym]
            else
              return nil
            end
          when Object
            if current_value.respond_to?(part)
              current_value = current_value.public_send(part)
            elsif current_value.respond_to?("#{part}?")
              current_value = current_value.public_send("#{part}?")
            else
              return nil
            end
          else
            return nil
          end

          return nil if current_value.nil?
        end

        current_value
      end

      # Get all available data (runtime + business + computed)
      attr_reader :all_data

      # Check if variable exists
      def variable?(variable_path)
        !get(variable_path).nil?
      end

      # Get list of all available variable paths (for validation)
      def available_variables
        collect_variable_paths(all_data)
      end

      # Resolve variable (alias for get method for hydrator compatibility)
      def resolve_variable(variable_path)
        get(variable_path)
      end

      # Add accessor for request data (maps to @server_data for 'app' namespace compatibility)
      def request
        @server_data
      end



      # Extract session from request object
      def sess
        return default_session unless req
        if req.respond_to?(:session)
          session = req.session
          # Check if session has the adapter interface (respond to authenticated?)
          # If it's a plain Hash (like Rack::Request.session), use default session
          session.respond_to?(:authenticated?) ? session : default_session
        else
          default_session
        end
      end

      # Extract customer/user from request object
      def cust
        return default_customer unless req
        if req.respond_to?(:user)
          req.user
        elsif req.respond_to?(:customer)
          req.customer
        else
          default_customer
        end
      end

      # Create a new context with updated client data
      def with_client(new_client_data)
        self.class.new(
          @req, @locale,
          client: normalize_keys(new_client_data),
          server: @server_data,
          config: @config
        )
      end

      # Create a new context with updated server data
      def with_server(new_server_data)
        self.class.new(
          @req, @locale,
          client: @client_data,
          server: normalize_keys(new_server_data),
          config: @config
        )
      end

      # Create a new context with merged client data
      def merge_client(additional_client_data)
        self.class.new(
          @req, @locale,
          client: @client_data.merge(normalize_keys(additional_client_data)),
          server: @server_data,
          config: @config
        )
      end

    private

      # Build consolidated app data (replaces runtime_data + computed_data)
      def build_app_data
        app = {}

        # Request context (from current runtime_data)
        if req && req.respond_to?(:env) && req.env
          app['csrf_token'] = req.env.fetch(@config.csrf_token_name, nil)
          app['nonce'] = get_or_generate_nonce
          app['request_id'] = req.env.fetch('request_id', nil)
          app['domain_strategy'] = req.env.fetch('domain_strategy', :default)
          app['display_domain'] = req.env.fetch('display_domain', nil)
        else
          # Generate nonce even without request if CSP is enabled
          app['nonce'] = get_or_generate_nonce
        end

        # Configuration (from both layers)
        app['environment'] = @config.app_environment
        app['api_base_url'] = @config.api_base_url
        app['features'] = @config.features
        app['development'] = @config.development?

        # Authentication & UI (from current computed_data)
        app['authenticated'] = authenticated?
        app['theme_class'] = determine_theme_class

        app
      end

      # Build API base URL from configuration (deprecated - moved to config)
      def build_api_base_url
        @config.api_base_url
      end

      # Determine theme class for CSS
      def determine_theme_class
        # Default theme logic - can be overridden by business data
        if @client_data['theme']
          "theme-#{@client_data['theme']}"
        elsif cust && cust.respond_to?(:theme_preference)
          "theme-#{cust.theme_preference}"
        else
          'theme-light'
        end
      end

      # Check if user is authenticated
      def authenticated?
        sess && sess.authenticated? && cust && !cust.anonymous?
      end

      # Get default session instance
      def default_session
        Rhales::Adapters::AnonymousSession.new
      end

      # Get default customer instance
      def default_customer
        Rhales::Adapters::AnonymousAuth.new
      end

      # Normalize hash keys to strings recursively
      def normalize_keys(data)
        case data
        when Hash
          data.each_with_object({}) do |(key, value), result|
            result[key.to_s] = normalize_keys(value)
          end
        when Array
          data.map { |item| normalize_keys(item) }
        else
          data
        end
      end

      # Recursively collect all variable paths from nested data
      def collect_variable_paths(data, prefix = '')
        paths = []

        case data
        when Hash
          data.each do |key, value|
            current_path = prefix.empty? ? key.to_s : "#{prefix}.#{key}"
            paths << current_path

            if value.is_a?(Hash) || value.is_a?(Object)
              paths.concat(collect_variable_paths(value, current_path))
            end
          end
        when Object
          # For objects, collect method names that look like attributes
          data.public_methods(false).each do |method|
            method_name = method.to_s
            next if method_name.end_with?('=') # Skip setters
            next if method_name.start_with?('_') # Skip private-ish methods

            current_path = prefix.empty? ? method_name : "#{prefix}.#{method_name}"
            paths << current_path
          end
        end

        paths
      end

      # Get or generate nonce for CSP
      def get_or_generate_nonce
        # Try to get existing nonce from request env
        if req && req.respond_to?(:env) && req.env
          existing_nonce = req.env.fetch(@config.nonce_header_name, nil)
          return existing_nonce if existing_nonce
        end

        # Generate new nonce if auto_nonce is enabled or CSP is enabled
        return CSP.generate_nonce if @config.auto_nonce || (@config.csp_enabled && csp_nonce_required?)

        # Return nil if nonce is not needed
        nil
      end

      # Check if CSP policy requires nonce
      def csp_nonce_required?
        return false unless @config.csp_enabled

        csp = CSP.new(@config)
        csp.nonce_required?
      end

      class << self
        # Create context with business data for a specific view
        def for_view(req, locale, client: {}, server: {}, config: nil, **additional_client)
          all_client = client.merge(additional_client)
          new(req, locale, client: all_client, server: server, config: config)
        end

        # Create minimal context for testing
        def minimal(locale = 'en', client: {}, server: {}, config: nil)
          new(nil, locale, client: client, server: server, config: config)
        end
      end
  end
end
