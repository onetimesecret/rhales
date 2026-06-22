# lib/rhales/hydration/mount_point_detector.rb
#
# frozen_string_literal: true

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
  #
  # ## Performance
  #
  # Detection scans the HTML a single time using one combined alternation
  # pattern built from all selectors, rather than re-scanning the whole
  # document once per selector. Results are memoized per instance keyed by
  # [template_html, selectors], so repeated detection on the same rendered
  # HTML (e.g. across renders that reuse the detector) reuses the prior result
  # and its SafeInjectionValidator work instead of recomputing.
  class MountPointDetector
    DEFAULT_SELECTORS = ['#app', '#root', '[data-rsfc-mount]', '[data-mount]'].freeze

    def initialize
      @cache = {}
    end

    def detect(template_html, custom_selectors = [])
      selectors = (DEFAULT_SELECTORS + Array(custom_selectors)).uniq
      cache_key = [template_html, selectors]
      return @cache[cache_key] if @cache.key?(cache_key)

      @cache[cache_key] = compute_detection(template_html, selectors)
    end

    private

    def compute_detection(template_html, selectors)
      validator = SafeInjectionValidator.new(template_html)
      pattern   = combined_pattern(selectors)
      scanner   = StringScanner.new(template_html)
      matches   = []

      # Single pass over the HTML: the combined alternation finds every
      # selector occurrence in document order, and the matching capture-group
      # index tells us which selector produced it.
      while scanner.scan_until(pattern)
        selector  = selectors[matched_group_index(scanner, selectors.length)]
        tag_start = find_tag_start(scanner, template_html)

        # Only include mount points that are safe for injection
        safe_position = find_safe_injection_position(validator, tag_start)
        next unless safe_position

        matches << {
          selector: selector,
          position: safe_position,
          original_position: tag_start,
          matched: scanner.matched,
        }
      end

      # Preserve the original selection semantics: matches are considered in
      # selector-priority order (then document order within a selector), and
      # the earliest injection position wins. Ordering the matches this way
      # before min_by reproduces the previous per-selector tie-breaking.
      ordered = selectors.flat_map { |selector| matches.select { |mp| mp[:selector] == selector } }
      ordered.min_by { |mp| mp[:position] }
    end

    # Build one alternation pattern from all selectors. Each selector's
    # sub-pattern is wrapped in a capture group so the matched group index
    # identifies which selector matched. None of the sub-patterns introduce
    # their own capture groups, so group N corresponds to selector N-1.
    def combined_pattern(selectors)
      union = selectors.map { |selector| "(#{build_pattern(selector).source})" }.join('|')
      Regexp.new(union, Regexp::IGNORECASE)
    end

    def matched_group_index(scanner, count)
      count.times { |index| return index if scanner[index + 1] }
      0
    end

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
