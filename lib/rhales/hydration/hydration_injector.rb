# lib/rhales/hydration/hydration_injector.rb
#
# frozen_string_literal: true

require_relative 'earliest_injection_detector'
require_relative 'link_based_injection_detector'

module Rhales
  # Handles intelligent hydration script injection with multiple strategies
  # for optimal performance and resource loading.
  #
  # ## Supported Injection Strategies
  #
  # ### Traditional Strategies
  # - **`:late`** (default) - Inject before </body> tag (safest, backwards compatible)
  # - **`:early`** - Inject before detected mount points (#app, #root, etc.)
  # - **`:earliest`** - Inject in HTML head section for maximum performance
  #
  # ### Link-Based Strategies (API endpoints)
  # - **`:link`** - Basic link reference to API endpoint
  # - **`:prefetch`** - Browser prefetch for future page loads
  # - **`:preload`** - High priority preload for current page
  # - **`:modulepreload`** - ES module preloading
  # - **`:lazy`** - Intersection observer-based lazy loading
  #
  # ## Strategy Selection Logic
  #
  # 1. **Template Disable Check**: Respect `disable_early_for_templates` configuration
  # 2. **Strategy Routing**: Execute strategy-specific injection logic
  # 3. **Fallback Chain**: :earliest → :early → :late (when enabled)
  # 4. **Safety Validation**: All injection points validated for HTML safety
  #
  # Link-based strategies generate API calls instead of inline data,
  # enabling better caching, parallel loading, and reduced HTML payload.
  #
  class HydrationInjector
    LINK_BASED_STRATEGIES = [:link, :prefetch, :preload, :modulepreload, :lazy].freeze

    def initialize(hydration_config, template_name = nil)
      @hydration_config = hydration_config
      @template_name = template_name
      @strategy = hydration_config.injection_strategy
      @fallback_to_late = hydration_config.fallback_to_late
      @fallback_when_unsafe = hydration_config.fallback_when_unsafe
      @disabled_templates = hydration_config.disable_early_for_templates
      @earliest_detector = EarliestInjectionDetector.new
      @link_detector = LinkBasedInjectionDetector.new(hydration_config)
    end

    def inject(template_html, hydration_html, mount_point_data = nil)
      return template_html if hydration_html.nil? || hydration_html.strip.empty?

      # Check if early/earliest injection is disabled for this template
      if [:early, :earliest].include?(@strategy) && template_disabled_for_early?
        return inject_late(template_html, hydration_html)
      end

      case @strategy
      when :early
        inject_early(template_html, hydration_html, mount_point_data)
      when :earliest
        inject_earliest(template_html, hydration_html)
      when :late
        inject_late(template_html, hydration_html)
      when *LINK_BASED_STRATEGIES
        inject_link_based(template_html, hydration_html)
      else
        inject_late(template_html, hydration_html)
      end
    end

    # Special method for link-based strategies that need merged data context
    def inject_link_based_strategy(template_html, merged_data, nonce = nil)
      return template_html if merged_data.nil? || merged_data.empty?

      # Check if early injection is disabled for this template
      if template_disabled_for_early?
        # For link strategies, we still generate the links but fall back to late positioning
        link_html = generate_all_link_strategies(merged_data, nonce)
        return inject_late(template_html, link_html)
      end

      link_html = generate_all_link_strategies(merged_data, nonce)

      case @strategy
      when :earliest
        inject_earliest(template_html, link_html)
      when *LINK_BASED_STRATEGIES
        inject_link_based(template_html, link_html)
      else
        inject_late(template_html, link_html)
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

    def inject_earliest(template_html, hydration_html)
      begin
        injection_position = @earliest_detector.detect(template_html)
      rescue => e
        # Fall back to late injection on detector error
        return @fallback_to_late ? inject_late(template_html, hydration_html) : template_html
      end

      if injection_position
        before = template_html[0...injection_position]
        after = template_html[injection_position..]
        "#{before}#{hydration_html}\n#{after}"
      else
        # Fallback to late injection if earliest fails
        @fallback_to_late ? inject_late(template_html, hydration_html) : template_html
      end
    end

    def inject_link_based(template_html, hydration_html)
      # For link-based strategies, try earliest injection first, then fallback
      injection_position = @earliest_detector.detect(template_html)

      if injection_position
        before = template_html[0...injection_position]
        after = template_html[injection_position..]
        "#{before}#{hydration_html}\n#{after}"
      else
        # Fallback to late injection
        @fallback_to_late ? inject_late(template_html, hydration_html) : template_html
      end
    end

    def generate_all_link_strategies(merged_data, nonce)
      link_parts = []

      merged_data.each do |window_attr, _data|
        link_html = @link_detector.generate_for_strategy(@strategy, @template_name, window_attr, nonce)
        link_parts << link_html
      end

      link_parts.join("\n")
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
