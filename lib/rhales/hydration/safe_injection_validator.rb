require 'strscan'

module Rhales
  # Validates whether a hydration injection point is safe within HTML context
  # Prevents injection inside script tags, style tags, comments, or other unsafe locations
  class SafeInjectionValidator
    UNSAFE_CONTEXTS = [
      { start: /<script\b[^>]*>/i, end: /<\/script>/i },
      { start: /<style\b[^>]*>/i, end: /<\/style>/i },
      { start: /<!--/, end: /-->/ },
      { start: /<!\[CDATA\[/, end: /\]\]>/ }
    ].freeze

    def initialize(html)
      @html = html
      @unsafe_ranges = calculate_unsafe_ranges
    end

    # Check if the given position is safe for injection
    def safe_injection_point?(position)
      return false if position < 0 || position > @html.length

      # Check if position falls within any unsafe range
      @unsafe_ranges.none? { |range| range.cover?(position) }
    end

    # Find the nearest safe injection point before the given position
    def nearest_safe_point_before(position)
      # Work backwards from position to find a safe point
      (0...position).reverse_each do |pos|
        return pos if safe_injection_point?(pos) && at_tag_boundary?(pos)
      end

      # If no safe point found before, return nil
      nil
    end

    # Find the nearest safe injection point after the given position
    def nearest_safe_point_after(position)
      # Work forwards from position to find a safe point
      (position...@html.length).each do |pos|
        return pos if safe_injection_point?(pos) && at_tag_boundary?(pos)
      end

      # If no safe point found after, return nil
      nil
    end

    private

    def calculate_unsafe_ranges
      ranges = []
      scanner = StringScanner.new(@html)

      UNSAFE_CONTEXTS.each do |context|
        scanner.pos = 0

        while scanner.scan_until(context[:start])
          start_pos = scanner.pos - scanner.matched.length

          # Find the corresponding end tag
          if scanner.scan_until(context[:end])
            end_pos = scanner.pos
            ranges << (start_pos...end_pos)
          else
            # If no closing tag found, consider rest of document unsafe
            ranges << (start_pos...@html.length)
            break
          end
        end
      end

      ranges
    end

    # Check if position is at a tag boundary (before < or after >)
    def at_tag_boundary?(position)
      return true if position == 0 || position == @html.length

      char_before = position > 0 ? @html[position - 1] : nil
      char_at = @html[position]

      # Safe positions:
      # - Right after a closing >
      # - Right before an opening <
      # - At whitespace boundaries between tags
      char_before == '>' || char_at == '<' || (char_at&.match?(/\s/) && next_non_whitespace_is_tag?(position))
    end

    def next_non_whitespace_is_tag?(position)
      pos = position
      while pos < @html.length && @html[pos].match?(/\s/)
        pos += 1
      end

      pos < @html.length && @html[pos] == '<'
    end
  end
end
