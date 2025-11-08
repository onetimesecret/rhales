# lib/rhales/hydration/earliest_injection_detector.rb
#
# frozen_string_literal: true

require 'strscan'
require_relative 'safe_injection_validator'

module Rhales
  # Detects the earliest safe injection points in HTML head and body sections
  # for optimal hydration script placement performance
  #
  # ## Injection Priority Order
  #
  # For `<head></head>` section:
  # 1. After the last `<link>` tag
  # 2. After the last `<meta>` tag
  # 3. After the first `<script>` tag (assuming early scripts are intentional)
  # 4. Before the `</head>` tag
  #
  # If no `<head>` but there is `<body>`:
  # - Before the `<body>` tag
  #
  # All injection points are validated for safety using SafeInjectionValidator
  # to prevent injection inside unsafe contexts (scripts, styles, comments).
  class EarliestInjectionDetector
    def detect(template_html)
      scanner = StringScanner.new(template_html)
      validator = SafeInjectionValidator.new(template_html)

      # Try head section injection points first
      head_injection_point = detect_head_injection_point(scanner, validator, template_html)
      return head_injection_point if head_injection_point

      # Fallback to body tag injection
      body_injection_point = detect_body_injection_point(scanner, validator, template_html)
      return body_injection_point if body_injection_point

      # No suitable injection point found
      nil
    end

    private

    def detect_head_injection_point(scanner, validator, template_html)
      # Find head section bounds
      head_start, head_end = find_head_section(template_html)
      return nil unless head_start && head_end

      # Try injection points in priority order within head section
      injection_candidates = [
        find_after_last_link(template_html, head_start, head_end),
        find_after_last_meta(template_html, head_start, head_end),
        find_after_first_script(template_html, head_start, head_end),
        head_end # Before </head>
      ].compact

      # Return first safe injection point
      injection_candidates.each do |position|
        safe_position = find_safe_injection_position(validator, position)
        return safe_position if safe_position
      end

      nil
    end

    def detect_body_injection_point(scanner, validator, template_html)
      scanner.pos = 0

      # Find opening <body> tag
      if scanner.scan_until(/<body\b[^>]*>/i)
        body_start = scanner.pos - scanner.matched.length
        safe_position = find_safe_injection_position(validator, body_start)
        return safe_position if safe_position
      end

      nil
    end

    def find_head_section(template_html)
      scanner = StringScanner.new(template_html)

      # Find opening <head> tag
      return nil unless scanner.scan_until(/<head\b[^>]*>/i)
      head_start = scanner.pos

      # Find closing </head> tag
      return nil unless scanner.scan_until(/<\/head>/i)
      head_end = scanner.pos - scanner.matched.length

      [head_start, head_end]
    end

    def find_after_last_link(template_html, head_start, head_end)
      head_content = template_html[head_start...head_end]
      scanner = StringScanner.new(head_content)
      last_link_end = nil

      while scanner.scan_until(/<link\b[^>]*\/?>/i)
        last_link_end = scanner.pos
      end

      last_link_end ? head_start + last_link_end : nil
    end

    def find_after_last_meta(template_html, head_start, head_end)
      head_content = template_html[head_start...head_end]
      scanner = StringScanner.new(head_content)
      last_meta_end = nil

      while scanner.scan_until(/<meta\b[^>]*\/?>/i)
        last_meta_end = scanner.pos
      end

      last_meta_end ? head_start + last_meta_end : nil
    end

    def find_after_first_script(template_html, head_start, head_end)
      head_content = template_html[head_start...head_end]
      scanner = StringScanner.new(head_content)

      # Find first script opening tag
      if scanner.scan_until(/<script\b[^>]*>/i)
        script_start = scanner.pos - scanner.matched.length

        # Find corresponding closing tag
        if scanner.scan_until(/<\/script>/i)
          first_script_end = scanner.pos
          return head_start + first_script_end
        end
      end

      nil
    end

    def find_safe_injection_position(validator, preferred_position)
      return nil unless preferred_position

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
