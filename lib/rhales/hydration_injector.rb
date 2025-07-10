module Rhales
  # Handles intelligent hydration script injection based on mount point
  # detection. Supports both early injection (before mount points) and late
  # injection (before </body>).
  #
  # ## Early Injection Strategy Order
  #
  # When injection_strategy is :early, the following order is used to find
  # injection points:
  #
  # 1. **Template Disable Check**: If template is in
  #    `disable_early_for_templates`, fall back to late injection
  # 2. **Mount Point Detection**: Find mount points using configured selectors,
  #    return earliest by position
  # 3. **Safety Validation**: Check if the mount point location is safe for
  #    injection (outside scripts/styles/comments)
  # 4. **Preferred Position**: If safe, inject directly before the mount point
  # 5. **Safe Position Before**: If unsafe, search backwards for the nearest
  #    safe injection point before the mount point
  # 6. **Safe Position After**: If no safe point before, search forwards for
  #    the nearest safe injection point after the mount point
  # 7. **Late Injection Fallback**: If no safe position found and
  #    `fallback_when_unsafe` is true, use late injection
  # 8. **No Injection**: If no safe position and fallback disabled, return
  #    original template unchanged
  #
  # This ensures hydration scripts are placed as close to mount points as
  # possible while maintaining safety.
  #
  class HydrationInjector
    def initialize(hydration_config, template_name = nil)
      @hydration_config = hydration_config
      @template_name = template_name
      @strategy = hydration_config.injection_strategy
      @fallback_to_late = hydration_config.fallback_to_late
      @fallback_when_unsafe = hydration_config.fallback_when_unsafe
      @disabled_templates = hydration_config.disable_early_for_templates
    end

    def inject(template_html, hydration_html, mount_point_data = nil)
      return template_html if hydration_html.nil? || hydration_html.strip.empty?

      # Check if early injection is disabled for this template
      if @strategy == :early && template_disabled_for_early?
        return inject_late(template_html, hydration_html)
      end

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

      # Check if the mount point data indicates an unsafe injection
      # (This would be nil if SafeInjectionValidator found no safe position)
      if mount_point_data[:position].nil?
        return @fallback_when_unsafe ? inject_late(template_html, hydration_html) : template_html
      end

      # Insert hydration script before the mount element
      position = mount_point_data[:position]

      before = template_html[0...position]
      after = template_html[position..]

      "#{before}#{hydration_html}\n#{after}"
    end

    def template_disabled_for_early?
      @template_name && @disabled_templates.include?(@template_name)
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
