require 'strscan'

module Rhales
  # Detects frontend application mount points in HTML templates
  # Used to determine optimal hydration script injection points
  class MountPointDetector
    DEFAULT_SELECTORS = ['#app', '#root', '[data-rsfc-mount]', '[data-mount]'].freeze

    def detect(template_html, custom_selectors = [])
      selectors = (DEFAULT_SELECTORS + Array(custom_selectors)).uniq
      scanner = StringScanner.new(template_html)
      mount_points = []

      selectors.each do |selector|
        scanner.pos = 0
        pattern = build_pattern(selector)

        while scanner.scan_until(pattern)
          # Calculate position where the full tag starts
          tag_start_pos = find_tag_start(scanner, template_html)

          mount_points << {
            selector: selector,
            position: tag_start_pos,
            matched: scanner.matched
          }
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
  end
end
