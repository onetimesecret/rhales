# lib/rhales/csp.rb

module Rhales
  # Content Security Policy (CSP) header generation and management
  #
  # Provides secure defaults and nonce integration for CSP headers.
  # Converts policy configuration into proper CSP header strings.
  #
  # Usage:
  #   csp = Rhales::CSP.new(config, nonce: 'abc123')
  #   header = csp.build_header
  #   # => "default-src 'self'; script-src 'self' 'nonce-abc123'; ..."
  class CSP
    attr_reader :config, :nonce

    def initialize(config, nonce: nil)
      @config = config
      @nonce = nonce
    end

    # Build CSP header string from configuration
    def build_header
      return nil unless @config.csp_enabled

      policy_directives = []

      @config.csp_policy.each do |directive, sources|
        if sources.empty?
          # For directives with no sources (like upgrade-insecure-requests)
          policy_directives << directive
        else
          # Process sources and interpolate nonce if present
          processed_sources = sources.map { |source| interpolate_nonce(source) }
          directive_string = "#{directive} #{processed_sources.join(' ')}"
          policy_directives << directive_string
        end
      end

      policy_directives.join('; ')
    end

    # Generate a new nonce value
    def self.generate_nonce
      SecureRandom.hex(16)
    end

    # Validate CSP policy configuration
    def validate_policy!
      return unless @config.csp_enabled

      errors = []

      # Ensure policy is a hash
      unless @config.csp_policy.is_a?(Hash)
        errors << 'csp_policy must be a hash'
        raise Rhales::Configuration::ConfigurationError, "CSP policy errors: #{errors.join(', ')}"
      end

      # Validate each directive
      @config.csp_policy.each do |directive, sources|
        unless sources.is_a?(Array)
          errors << "#{directive} sources must be an array"
        end

        # Check for dangerous sources
        if sources.include?("'unsafe-eval'")
          errors << "#{directive} contains dangerous 'unsafe-eval' source"
        end

        if sources.include?("'unsafe-inline'") && !%w[style-src].include?(directive)
          errors << "#{directive} contains dangerous 'unsafe-inline' source"
        end
      end

      raise Rhales::Configuration::ConfigurationError, "CSP policy errors: #{errors.join(', ')}" unless errors.empty?
    end

    # Check if nonce is required for any directive
    def nonce_required?
      return false unless @config.csp_enabled

      @config.csp_policy.values.flatten.any? { |source| source.include?('{{nonce}}') }
    end

    private

    # Interpolate nonce placeholder in source values
    def interpolate_nonce(source)
      return source unless @nonce && source.include?('{{nonce}}')

      source.gsub('{{nonce}}', @nonce)
    end
  end
end
