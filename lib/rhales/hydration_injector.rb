module Rhales
  # Handles intelligent hydration script injection based on mount point detection
  # Supports both early injection (before mount points) and late injection (before </body>)
  class HydrationInjector
    def initialize(config)
      @config = config
      @strategy = config.respond_to?(:hydration) && config.hydration.respond_to?(:injection_strategy) ?
                  config.hydration.injection_strategy : :late
      @fallback_to_late = config.respond_to?(:hydration) && config.hydration.respond_to?(:fallback_to_late) ?
                          config.hydration.fallback_to_late : true
    end

    def inject(template_html, hydration_html, mount_point_data = nil)
      return template_html if hydration_html.nil? || hydration_html.strip.empty?

      case @strategy
      when :early
        inject_early(template_html, hydration_html, mount_point_data)
      when :late
        inject_late(template_html, hydration_html)
      else
        inject_late(template_html, hydration_html)
      end
    end

    private

    def inject_early(template_html, hydration_html, mount_point_data)
      # Fallback to late injection if no mount point found
      if mount_point_data.nil?
        return @fallback_to_late ? inject_late(template_html, hydration_html) : template_html
      end

      # Insert hydration script before the mount element
      position = mount_point_data[:position]

      before = template_html[0...position]
      after = template_html[position..-1]

      "#{before}#{hydration_html}\n#{after}"
    end

    def inject_late(template_html, hydration_html)
      # Try to inject before closing </body> tag
      if template_html.include?('</body>')
        template_html.sub('</body>', "#{hydration_html}\n</body>")
      else
        # If no </body> tag, append to end
        "#{template_html}\n#{hydration_html}"
      end
    end
  end
end
