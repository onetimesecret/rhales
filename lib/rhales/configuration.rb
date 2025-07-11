# lib/rhales/configuration.rb

module Rhales
  # Hydration-specific configuration settings
  #
  # Controls how hydration scripts are injected into HTML templates.
  # Supports multiple injection strategies for different performance characteristics:
  #
  # ## Traditional Strategies
  # - `:late` (default) - injects before </body> tag (safest, backwards compatible)
  # - `:early` - injects before detected mount points for improved performance
  # - `:earliest` - injects in HTML head section for maximum performance
  #
  # ## Link-Based Strategies (API endpoints)
  # - `:link` - basic link reference to API endpoint
  # - `:prefetch` - browser prefetch for future page loads
  # - `:preload` - high priority preload for current page
  # - `:modulepreload` - ES module preloading
  # - `:lazy` - intersection observer-based lazy loading
  class HydrationConfiguration
    VALID_STRATEGIES = [:late, :early, :earliest, :link, :prefetch, :preload, :modulepreload, :lazy].freeze
    LINK_BASED_STRATEGIES = [:link, :prefetch, :preload, :modulepreload, :lazy].freeze
    DEFAULT_API_CACHE_TTL = 300  # 5 minutes

    # Injection strategy - one of VALID_STRATEGIES
    attr_accessor :injection_strategy

    # Array of CSS selectors to detect frontend mount points
    attr_accessor :mount_point_selectors

    # Whether to fallback to late injection when no mount points detected
    attr_accessor :fallback_to_late

    # Whether to fallback to late injection when early injection is unsafe
    attr_accessor :fallback_when_unsafe

    # Disable early injection for specific templates (array of template names)
    attr_accessor :disable_early_for_templates

    # API endpoint configuration for link-based strategies
    attr_accessor :api_endpoint_enabled, :api_endpoint_path

    # Link tag configuration
    attr_accessor :link_crossorigin

    # Module export configuration for :modulepreload strategy
    attr_accessor :module_export_enabled

    # Lazy loading configuration
    attr_accessor :lazy_mount_selector

    # Data attribute reflection system
    attr_accessor :reflection_enabled

    # Caching configuration for API endpoints
    attr_accessor :api_cache_enabled, :api_cache_ttl

    # CORS configuration for API endpoints
    attr_accessor :cors_enabled, :cors_origin

    def initialize
      # Traditional strategy settings
      @injection_strategy = :late
      @mount_point_selectors = ['#app', '#root', '[data-rsfc-mount]', '[data-mount]']
      @fallback_to_late = true
      @fallback_when_unsafe = true
      @disable_early_for_templates = []

      # API endpoint settings
      @api_endpoint_enabled = false
      @api_endpoint_path = '/api/hydration'

      # Link tag settings
      @link_crossorigin = true

      # Module export settings
      @module_export_enabled = false

      # Lazy loading settings
      @lazy_mount_selector = '#app'

      # Reflection system settings
      @reflection_enabled = true

      # Caching settings
      @api_cache_enabled = false
      @api_cache_ttl = DEFAULT_API_CACHE_TTL

      # CORS settings
      @cors_enabled = false
      @cors_origin = '*'
    end

    # Validate the injection strategy
    def injection_strategy=(strategy)
      unless VALID_STRATEGIES.include?(strategy)
        raise ArgumentError, "Invalid injection strategy: #{strategy}. Valid options: #{VALID_STRATEGIES.join(', ')}"
      end
      @injection_strategy = strategy
    end

    # Check if current strategy is link-based
    def link_based_strategy?
      LINK_BASED_STRATEGIES.include?(@injection_strategy)
    end

    # Check if API endpoints should be enabled
    def api_endpoints_required?
      link_based_strategy? || @api_endpoint_enabled
    end
  end

  # Configuration management for Rhales library
  #
  # Provides a clean, testable alternative to global configuration access.
  # Supports block-based configuration typical of Ruby gems and dependency injection.
  #
  # Usage:
  #   Rhales.configure do |config|
  #     config.default_locale = 'en'
  #     config.template_paths = ['app/templates', 'lib/templates']
  #     config.features = { account_creation: true }
  #   end
  class Configuration
    # Core application settings
    attr_accessor :default_locale, :app_environment, :development_enabled

    # Template settings
    attr_accessor :template_paths, :template_root, :cache_templates

    # Security settings
    attr_accessor :csrf_token_name, :nonce_header_name, :csp_enabled, :csp_policy, :auto_nonce

    # Feature flags
    attr_accessor :features

    # Site configuration
    attr_accessor :site_host, :site_ssl_enabled, :api_base_url

    # Performance settings
    attr_accessor :cache_parsed_templates, :cache_ttl

    # Hydration settings
    attr_accessor :hydration

    def initialize
      # Set sensible defaults
      @default_locale         = 'en'
      @app_environment        = 'development'
      @development_enabled    = false
      @template_paths         = []
      @cache_templates        = true
      @csrf_token_name        = 'csrf_token'
      @nonce_header_name      = 'nonce'
      @csp_enabled            = true
      @auto_nonce             = true
      @csp_policy             = default_csp_policy
      @features               = {}
      @site_ssl_enabled       = false
      @cache_parsed_templates = true
      @cache_ttl              = 3600 # 1 hour
      @hydration              = HydrationConfiguration.new
    end

    # Build API base URL from site configuration
    def api_base_url
      return @api_base_url if @api_base_url

      return nil unless @site_host

      protocol = @site_ssl_enabled ? 'https' : 'http'
      "#{protocol}://#{@site_host}/api"
    end

    # Check if development mode is enabled
    def development?
      @development_enabled || @app_environment == 'development'
    end

    # Check if production mode
    def production?
      @app_environment == 'production'
    end

    # Default CSP policy with secure defaults
    def default_csp_policy
      {
        'default-src' => ["'self'"],
        'script-src' => ["'self'", "'nonce-{{nonce}}'"],
        'style-src' => ["'self'", "'nonce-{{nonce}}'", "'unsafe-hashes'"],
        'img-src' => ["'self'", 'data:'],
        'font-src' => ["'self'"],
        'connect-src' => ["'self'"],
        'base-uri' => ["'self'"],
        'form-action' => ["'self'"],
        'frame-ancestors' => ["'none'"],
        'object-src' => ["'none'"],
        'media-src' => ["'self'"],
        'worker-src' => ["'self'"],
        'manifest-src' => ["'self'"],
        'prefetch-src' => ["'self'"],
        'upgrade-insecure-requests' => [],
      }.freeze
    end

    # Get feature flag value
    def feature_enabled?(feature_name)
      @features[feature_name] || @features[feature_name.to_s] || false
    end

    # Validate configuration
    def validate!
      errors = []

      # Validate locale
      if @default_locale.nil? || @default_locale.empty?
        errors << 'default_locale cannot be empty'
      end

      # Validate template paths exist if specified
      @template_paths.each do |path|
        unless Dir.exist?(path)
          errors << "Template path does not exist: #{path}"
        end
      end

      # Validate cache TTL
      if @cache_ttl && @cache_ttl <= 0
        errors << 'cache_ttl must be positive'
      end

      raise ConfigurationError, "Configuration errors: #{errors.join(', ')}" unless errors.empty?
    end

    # Deep freeze configuration to prevent modification after setup
    def freeze!
      @features.freeze
      @template_paths.freeze
      freeze
    end

    class ConfigurationError < StandardError; end
  end

  class << self
    # Global configuration instance
    def configuration
      @configuration ||= Configuration.new
    end

    # Configure Rhales with block
    def configure
      yield(configuration) if block_given?
      configuration.validate!
      configuration.freeze!
      configuration
    end

    # Reset configuration (useful for testing)
    def reset_configuration!
      @configuration = nil
    end

    # Shorthand access to configuration
    def config
      configuration
    end
  end
end
