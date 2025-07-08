# frozen_string_literal: true

require 'tilt'
require 'rhales'
require_relative 'adapters/base_request'

module Rhales
  # Tilt integration for Rhales templates
  #
  # This allows Rhales to be used with any framework that supports Tilt,
  # including Roda's render plugin, Sinatra, and others.
  #
  # Usage in Roda:
  #   require 'rhales/tilt'
  #   plugin :render, engine: 'rhales'
  #
  # Usage in Sinatra:
  #   require 'rhales/tilt'
  #   set :template_engine, :rhales
  #
  class TiltTemplate < Tilt::Template
    self.default_mime_type = 'text/html'

    # Parse template during initialization
    def prepare
      # Store the template content - parsing happens during render
      @template_content = data
    end

    # Render the template with given scope and locals
    #
    # @param scope [Object] The scope object (usually the Roda/Sinatra app instance)
    # @param locals [Hash] Local variables for the template
    # @param block [Proc] Optional block content
    # @return [String] Rendered HTML
    def evaluate(scope, locals = {}, &)
      # Build template props from locals and scope
      props = build_props(scope, locals, &)

      # Create Rhales context adapters from scope
      rhales_context = build_rhales_context(scope, props)

      # Get template name from file path
      template_name = derive_template_name

      # Render the template
      rhales_context.render(template_name)
    end

    private

    # Get shared nonce from scope if available, otherwise generate one
    def get_shared_nonce(scope)
      # Try to get nonce from scope's CSP nonce or instance variable
      if scope.respond_to?(:csp_nonce) && scope.csp_nonce
        scope.csp_nonce
      elsif scope.respond_to?(:request) && scope.request.env['csp.nonce']
        scope.request.env['csp.nonce']
      elsif scope.instance_variable_defined?(:@csp_nonce)
        scope.instance_variable_get(:@csp_nonce)
      else
        # Generate a new nonce and store it for consistency
        nonce = SecureRandom.hex(16)
        scope.instance_variable_set(:@csp_nonce, nonce) if scope.respond_to?(:instance_variable_set)
        nonce
      end
    end

    # Build props hash from locals and scope context
    def build_props(scope, locals, &block)
      props = locals.dup

      # Add block content if provided
      props['content'] = yield if block

      # Add scope-specific data
      if scope.respond_to?(:request)
        props['current_path']   = scope.request.path
        props['request_method'] = scope.request.request_method
      end

      # Add flash messages if available
      if scope.respond_to?(:flash)
        props['flash_notice'] = scope.flash['notice']
        props['flash_error']  = scope.flash['error']
      end

      # Add rodauth object if available
      if scope.respond_to?(:rodauth)
        props['rodauth'] = scope.rodauth
      end

      # Add authentication status
      if scope.respond_to?(:logged_in?)
        props['authenticated'] = scope.logged_in?
      end

      props
    end

    # Build Rhales context objects from scope
    def build_rhales_context(scope, props)
      # Get shared nonce from scope if available, otherwise generate one
      shared_nonce = get_shared_nonce(scope)

      # Use proper request adapter
      request_data = if scope.respond_to?(:request)
        # Add CSP nonce to framework request env
        framework_env = scope.request.env.merge({
          'nonce' => shared_nonce,
          'request_id' => SecureRandom.hex(8),
        })

        # Create wrapper that preserves original but adds our env
        wrapped_request = Class.new do
          def initialize(original, custom_env)
            @original = original
            @custom_env = custom_env
          end

          def method_missing(method, *args, &block)
            @original.send(method, *args, &block)
          end

          def respond_to_missing?(method, include_private = false)
            @original.respond_to?(method, include_private)
          end

          def env
            @custom_env
          end
        end.new(scope.request, framework_env)

        Rhales::Adapters::FrameworkRequest.new(wrapped_request)
      else
        Rhales::Adapters::SimpleRequest.new(
          path: '/',
          method: 'GET',
          ip: '127.0.0.1',
          params: {},
          env: {
            'nonce' => shared_nonce,
            'request_id' => SecureRandom.hex(8),
          }
        )
      end

      # Use proper session adapter
      session_data = if scope.respond_to?(:logged_in?) && scope.logged_in?
        Rhales::Adapters::AuthenticatedSession.new(
          {
            id: SecureRandom.hex(8),
            created_at: Time.now,
          },
        )
      else
        Rhales::Adapters::AnonymousSession.new
      end

      # Use proper auth adapter
      if scope.respond_to?(:logged_in?) && scope.logged_in? && scope.respond_to?(:current_user)
        user      = scope.current_user
        auth_data = Rhales::Adapters::AuthenticatedAuth.new({
          id: user[:id],
          email: user[:email],
          authenticated: true,
        },
                                                           )
      else
        auth_data = Rhales::Adapters::AnonymousAuth.new
      end

      ::Rhales::View.new(
        request_data,
        session_data,
        auth_data,
        nil, # locale_override
        props: props,
      )
    end

    # Derive template name from file path
    def derive_template_name
      return @template_name if @template_name

      if file
        # Remove extension and get relative path from template directory
        template_path = File.basename(file, '.*')

        # Check if this is in a subdirectory (relative to configured paths)
        if ::Rhales.configuration.template_paths
          ::Rhales.configuration.template_paths.each do |path|
            next unless file.start_with?(path)

            relative_path = file.sub(path + '/', '')
            template_path = if File.dirname(relative_path) == '.'
            File.basename(relative_path, '.*')
          else
            File.join(File.dirname(relative_path), File.basename(relative_path, '.*'))
          end
            break
          end
        end

        @template_name = template_path
      else
        @template_name = 'unknown'
      end
    end
  end
end

# Register the template with Tilt
Tilt.register Rhales::TiltTemplate, 'rue'
