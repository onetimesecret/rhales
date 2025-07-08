# frozen_string_literal: true

require 'tilt'
require 'rhales'

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
    def evaluate(scope, locals = {}, &block)
      # Build template props from locals and scope
      props = build_props(scope, locals, &block)

      # Create Rhales context adapters from scope
      rhales_context = build_rhales_context(scope, props)

      # Get template name from file path
      template_name = derive_template_name

      # Render the template
      rhales_context.render(template_name)
    end

    private

    # Build props hash from locals and scope context
    def build_props(scope, locals, &block)
      props = locals.dup

      # Add block content if provided
      props['content'] = block.call if block

      # Add scope-specific data
      if scope.respond_to?(:request)
        props['current_path'] = scope.request.path
        props['request_method'] = scope.request.request_method
      end

      # Add flash messages if available
      if scope.respond_to?(:flash)
        props['flash_notice'] = scope.flash['notice']
        props['flash_error'] = scope.flash['error']
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
      # Simple request adapter
      if scope.respond_to?(:request)
        request_data = Struct.new(:path, :method, :ip, :params, :env).new(
          scope.request.path,
          scope.request.request_method,
          scope.request.ip,
          scope.request.params,
          {
            'nonce' => SecureRandom.hex(16),
            'request_id' => SecureRandom.hex(8),
          }
        )
      else
        request_data = Struct.new(:path, :method, :ip, :params, :env).new(
          '/',
          'GET',
          '127.0.0.1',
          {},
          {
            'nonce' => SecureRandom.hex(16),
            'request_id' => SecureRandom.hex(8),
          }
        )
      end

      # Simple session adapter
      session_data = Struct.new(:authenticated, :csrf_token).new(
        scope.respond_to?(:logged_in?) ? scope.logged_in? : false,
        nil # Let framework handle CSRF
      )

      # Simple auth adapter
      if scope.respond_to?(:logged_in?) && scope.logged_in? && scope.respond_to?(:current_user)
        user = scope.current_user
        auth_data = Struct.new(:authenticated, :anonymous?, :email, :user_data, :theme_preference, :user_id, :display_name).new(
          true,
          false,
          user[:email],
          { id: user[:id], email: user[:email] },
          'light',
          user[:id],
          user[:email]
        )
      else
        auth_data = Struct.new(:authenticated, :anonymous?, :email, :user_data, :theme_preference, :user_id, :display_name).new(
          false,
          true,
          nil,
          nil,
          'light',
          nil,
          nil
        )
      end

      ::Rhales::View.new(
        request_data,
        session_data,
        auth_data,
        nil, # locale_override
        props: props
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
            if file.start_with?(path)
              relative_path = file.sub(path + '/', '')
              template_path = File.dirname(relative_path) == '.' ?
                File.basename(relative_path, '.*') :
                File.join(File.dirname(relative_path), File.basename(relative_path, '.*'))
              break
            end
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
