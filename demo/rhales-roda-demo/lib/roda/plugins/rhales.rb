# frozen_string_literal: true

# Add the lib directory to the load path to find rhales
$:.unshift(File.expand_path('../../../../../lib', __dir__))
require 'roda'
require 'rhales'

class Roda
  module RodaPlugins
    # Roda plugin to integrate Rhales as the template engine
    #
    # This plugin allows Roda apps to use Rhales (.rue) templates
    # with automatic template discovery, layout support, and
    # seamless integration with Rodauth.
    #
    # Usage:
    #   plugin :rhales, template_paths: ['templates'], layout: 'layouts/main'
    module Rhales
      def self.configure(app, opts = {})
        app.opts[:rhales] = {
          template_paths: opts[:template_paths] || ['templates'],
          default_layout: opts[:layout] || 'layouts/main',
          cache_templates: opts[:cache_templates] != false,
          auto_data: opts[:auto_data] || {},
        }.freeze

        # Configure Rhales globally
        ::Rhales.configure do |config|
          config.template_paths = app.opts[:rhales][:template_paths].map { |path|
            File.expand_path(path, app.opts[:root] || Dir.pwd)
          }
          config.cache_templates = app.opts[:rhales][:cache_templates]
        end
      end

      module InstanceMethods
        # Render a Rhales template with optional layout
        #
        # @param template [String] Template name (e.g. 'login', 'auth/register')
        # @param props [Hash] Template variables
        # @param opts [Hash] Options including :layout
        # @return [String] Rendered HTML
        def rhales(template, props = {}, opts = {})
          layout = opts.fetch(:layout, self.class.opts[:rhales][:default_layout])

          # Merge auto data with template-specific props
          merged_props = build_auto_data.merge(props)

          # Create Rhales context adapters
          rhales_context = build_rhales_context(merged_props)

          # Render template content
          content_html = rhales_context.render(template)

          # Apply layout if specified
          if layout
            layout_props = merged_props.merge(
              content: content_html,
              authenticated: respond_to?(:logged_in?) ? logged_in? : false
            )
            layout_context = build_rhales_context(layout_props)
            layout_context.render(layout)
          else
            content_html
          end
        end

        # Override Roda's view method to use Rhales for .rue templates
        def view(template, opts = {})
          # Check if template exists as .rue file
          template_paths = self.class.opts[:rhales][:template_paths]
          rue_template_found = template_paths.any? do |path|
            full_path = File.expand_path(path, self.class.opts[:root] || Dir.pwd)
            File.exist?(File.join(full_path, "#{template}.rue"))
          end

          if rue_template_found
            # Use Rhales for .rue templates
            props = opts.is_a?(Hash) ? opts : {}
            layout = props.delete(:layout)
            rhales(template, props, layout: layout)
          else
            # If no .rue template found, try to call super if render plugin is loaded
            if defined?(super)
              super
            else
              raise "Template not found: #{template} (no .rue file and no render plugin loaded)"
            end
          end
        end

        private

        # Build automatic data available to all templates
        def build_auto_data
          auto_data = {
            'current_path' => request.path,
            'request_method' => request.request_method,
          }

          # Add flash messages if available
          if respond_to?(:flash)
            auto_data['flash_notice'] = flash['notice']
            auto_data['flash_error'] = flash['error']
          end

          # Add rodauth object if available
          if respond_to?(:rodauth)
            auto_data['rodauth'] = rodauth
          end

          # Merge configured auto data
          auto_data.merge(self.class.opts[:rhales][:auto_data])
        end

        # Build Rhales context objects from request/session/auth data
        def build_rhales_context(props)
          # Simple request adapter
          request_data = Struct.new(:path, :method, :ip, :params, :env).new(
            request.path,
            request.request_method,
            request.ip,
            request.params,
            {
              'nonce' => SecureRandom.hex(16),
              'request_id' => SecureRandom.hex(8),
            }
          )

          # Simple session adapter
          session_data = Struct.new(:authenticated, :csrf_token).new(
            respond_to?(:logged_in?) ? logged_in? : false,
            nil # Let Rodauth handle CSRF
          )

          # Simple auth adapter
          if respond_to?(:logged_in?) && logged_in? && respond_to?(:current_user)
            user = current_user
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
      end
    end

    register_plugin(:rhales, Rhales)
  end
end
