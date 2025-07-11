require 'strscan'
require_relative 'safe_injection_validator'

module Rhales
  # Generates link-based hydration strategies that use browser resource hints
  # and API endpoints instead of inline scripts
  #
  # ## Supported Strategies
  #
  # - **`:link`** - Basic link reference: `<link href="/api/hydration/template">`
  # - **`:prefetch`** - Background prefetch: `<link rel="prefetch" href="..." as="fetch">`
  # - **`:preload`** - High priority preload: `<link rel="preload" href="..." as="fetch">`
  # - **`:modulepreload`** - ES module preload: `<link rel="modulepreload" href="..."`
  # - **`:lazy`** - Lazy loading with intersection observer
  #
  # All strategies generate both link tags and accompanying JavaScript
  # for data fetching and assignment to window objects.
  class LinkBasedInjectionDetector
    def initialize(hydration_config)
      @hydration_config = hydration_config
      @api_endpoint_path = hydration_config.api_endpoint_path || '/api/hydration'
      @crossorigin_enabled = hydration_config.link_crossorigin.nil? ? true : hydration_config.link_crossorigin
    end

    def generate_for_strategy(strategy, template_name, window_attr, nonce = nil)
      case strategy
      when :link
        generate_basic_link(template_name, window_attr, nonce)
      when :prefetch
        generate_prefetch_link(template_name, window_attr, nonce)
      when :preload
        generate_preload_link(template_name, window_attr, nonce)
      when :modulepreload
        generate_modulepreload_link(template_name, window_attr, nonce)
      when :lazy
        generate_lazy_loading(template_name, window_attr, nonce)
      else
        raise ArgumentError, "Unsupported link strategy: #{strategy}"
      end
    end

    private

    def generate_basic_link(template_name, window_attr, nonce)
      endpoint_url = "#{@api_endpoint_path}/#{template_name}"

      link_tag = %(<link href="#{endpoint_url}" type="application/json">)

      script_tag = <<~HTML.strip
        <script#{nonce_attribute(nonce)} data-hydration-target="#{window_attr}">
        // Basic link - manual fetch when needed
        window.__rhales__ = window.__rhales__ || {};
        window.__rhales__.loadData = function(target) {
          fetch('#{endpoint_url}')
            .then(r => r.json())
            .then(data => window[target] = data);
        };
        </script>
      HTML

      "#{link_tag}\n#{script_tag}"
    end

    def generate_prefetch_link(template_name, window_attr, nonce)
      endpoint_url = "#{@api_endpoint_path}/#{template_name}"
      crossorigin_attr = @crossorigin_enabled ? ' crossorigin' : ''

      link_tag = %(<link rel="prefetch" href="#{endpoint_url}" as="fetch"#{crossorigin_attr}>)

      script_tag = <<~HTML.strip
        <script#{nonce_attribute(nonce)} data-hydration-target="#{window_attr}">
        // Prefetch strategy - data available in browser cache
        window.__rhales__ = window.__rhales__ || {};
        window.__rhales__.loadPrefetched = function(target) {
          fetch('#{endpoint_url}')
            .then(r => r.json())
            .then(data => window[target] = data);
        };
        </script>
      HTML

      "#{link_tag}\n#{script_tag}"
    end

    def generate_preload_link(template_name, window_attr, nonce)
      endpoint_url = "#{@api_endpoint_path}/#{template_name}"
      crossorigin_attr = @crossorigin_enabled ? ' crossorigin' : ''

      link_tag = %(<link rel="preload" href="#{endpoint_url}" as="fetch"#{crossorigin_attr}>)

      script_tag = <<~HTML.strip
        <script#{nonce_attribute(nonce)} data-hydration-target="#{window_attr}">
        // Preload strategy - high priority fetch
        fetch('#{endpoint_url}')
          .then(r => r.json())
          .then(data => {
            window.#{window_attr} = data;
            // Dispatch ready event
            window.dispatchEvent(new CustomEvent('rhales:hydrated', {
              detail: { target: '#{window_attr}', data: data }
            }));
          })
          .catch(err => console.error('Rhales hydration error:', err));
        </script>
      HTML

      "#{link_tag}\n#{script_tag}"
    end

    def generate_modulepreload_link(template_name, window_attr, nonce)
      endpoint_url = "#{@api_endpoint_path}/#{template_name}.js"

      link_tag = %(<link rel="modulepreload" href="#{endpoint_url}">)

      script_tag = <<~HTML.strip
        <script type="module"#{nonce_attribute(nonce)} data-hydration-target="#{window_attr}">
        // Module preload strategy
        import data from '#{endpoint_url}';
        window.#{window_attr} = data;

        // Dispatch ready event
        window.dispatchEvent(new CustomEvent('rhales:hydrated', {
          detail: { target: '#{window_attr}', data: data }
        }));
        </script>
      HTML

      "#{link_tag}\n#{script_tag}"
    end

    def generate_lazy_loading(template_name, window_attr, nonce)
      endpoint_url = "#{@api_endpoint_path}/#{template_name}"
      mount_selector = @hydration_config.lazy_mount_selector || '#app'

      # No link tag for lazy loading - purely script-driven
      script_tag = <<~HTML.strip
        <script#{nonce_attribute(nonce)} data-hydration-target="#{window_attr}" data-lazy-src="#{endpoint_url}">
        // Lazy loading strategy with intersection observer
        window.__rhales__ = window.__rhales__ || {};
        window.__rhales__.initLazyLoading = function() {
          const mountElement = document.querySelector('#{mount_selector}');
          if (!mountElement) {
            console.warn('Rhales: Mount element "#{mount_selector}" not found for lazy loading');
            return;
          }

          const observer = new IntersectionObserver((entries) => {
            entries.forEach(entry => {
              if (entry.isIntersecting) {
                fetch('#{endpoint_url}')
                  .then(r => r.json())
                  .then(data => {
                    window.#{window_attr} = data;
                    window.dispatchEvent(new CustomEvent('rhales:hydrated', {
                      detail: { target: '#{window_attr}', data: data }
                    }));
                  })
                  .catch(err => console.error('Rhales lazy hydration error:', err));

                observer.unobserve(entry.target);
              }
            });
          });

          observer.observe(mountElement);
        };

        // Initialize when DOM is ready
        if (document.readyState === 'loading') {
          document.addEventListener('DOMContentLoaded', window.__rhales__.initLazyLoading);
        } else {
          window.__rhales__.initLazyLoading();
        }
        </script>
      HTML

      script_tag
    end

    def nonce_attribute(nonce)
      nonce ? " nonce=\"#{nonce}\"" : ''
    end
  end
end
