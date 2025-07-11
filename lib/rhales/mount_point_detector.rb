require 'strscan'
require_relative 'safe_injection_validator'

module Rhales
  # Detects frontend application mount points in HTML templates
  # Used to determine optimal hydration script injection points
  #
  # ## Mount Point Detection Order
  #
  # 1. **Selector Priority**: All selectors (default + custom) are checked in parallel
  # 2. **Position Priority**: Returns the earliest mount point by position in HTML (not selector order)
  # 3. **Safety Validation**: Validates injection points are outside unsafe contexts (scripts/styles/comments)
  # 4. **Safe Position Search**: If original position unsafe, searches for nearest safe alternative:
  #    - First tries positions before the mount point (maintains earlier injection)
  #    - Then tries positions after the mount point (fallback)
  #    - Returns nil if no safe position found
  #
  # Default selectors are checked: ['#app', '#root', '[data-rsfc-mount]', '[data-mount]']
  # Custom selectors can be added via configuration and are combined with defaults.
  class MountPointDetector
    DEFAULT_SELECTORS = ['#app', '#root', '[data-rsfc-mount]', '[data-mount]'].freeze

    def detect(template_html, custom_selectors = [])
      selectors = (DEFAULT_SELECTORS + Array(custom_selectors)).uniq
      scanner = StringScanner.new(template_html)
      validator = SafeInjectionValidator.new(template_html)
      mount_points = []

      selectors.each do |selector|
        scanner.pos = 0
        pattern = build_pattern(selector)

        while scanner.scan_until(pattern)
          # Calculate position where the full tag starts
          tag_start_pos = find_tag_start(scanner, template_html)

          # Only include mount points that are safe for injection
          safe_position = find_safe_injection_position(validator, tag_start_pos)

          if safe_position
            mount_points << {
              selector: selector,
              position: safe_position,
              original_position: tag_start_pos,
              matched: scanner.matched
            }
          end
        end
      end

      # Return earliest mount point by position
      mount_points.min_by { |mp| mp[:position] }
    end

    private

    def build_pattern(selector)
      case selector
      when /^#(.+)$/
        # ID selector: <tag id="value">
        id_name = Regexp.escape($1)
        /id\s*=\s*["']#{id_name}["']/i
      when /^\.(.+)$/
        # Class selector: <tag class="... value ...">
        class_name = Regexp.escape($1)
        /class\s*=\s*["'][^"']*\b#{class_name}\b[^"']*["']/i
      when /^\[([^\]]+)\]$/
        # Attribute selector: <tag data-attr> or <tag data-attr="value">
        attr_name = Regexp.escape($1)
        /#{attr_name}(?:\s*=\s*["'][^"']*["'])?/i
      else
        # Invalid selector, match nothing
        /(?!.*)/
      end
    end

    def find_tag_start(scanner, template_html)
      # Work backwards from current position to find the opening <
      pos = scanner.pos - scanner.matched.length

      while pos > 0 && template_html[pos - 1] != '<'
        pos -= 1
      end

      # Return position of the < character
      pos > 0 ? pos - 1 : 0
    end

    def find_safe_injection_position(validator, preferred_position)
      # First check if the preferred position is safe
      return preferred_position if validator.safe_injection_point?(preferred_position)

      # Try to find a safe position before the preferred position
      safe_before = validator.nearest_safe_point_before(preferred_position)
      return safe_before if safe_before

      # As a last resort, try after the preferred position
      safe_after = validator.nearest_safe_point_after(preferred_position)
      return safe_after if safe_after

      # No safe position found
      nil
    end
  end
end
