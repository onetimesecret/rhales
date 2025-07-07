# frozen_string_literal: true

module Rhales
  # Registry to track window attributes used in hydration blocks
  # within a single request. Prevents silent data overwrites.
  class HydrationRegistry
    class << self
      def register(window_attr, template_path, merge_strategy = nil)
        validate_inputs(window_attr, template_path)

        registry = thread_local_registry

        if registry[window_attr] && merge_strategy.nil?
          existing = registry[window_attr]
          raise HydrationCollisionError.new(
            window_attr,
            existing[:path],
            template_path,
          )
        end

        registry[window_attr] = {
          path: template_path,
          merge_strategy: merge_strategy,
        }
      end

      def clear!
        Thread.current[:rhales_hydration_registry] = {}
      end

      # Expose registry for testing purposes
      def registry
        thread_local_registry
      end

      private

      def thread_local_registry
        Thread.current[:rhales_hydration_registry] ||= {}
      end

      def validate_inputs(window_attr, template_path)
        if window_attr.nil?
          raise ArgumentError, 'window attribute cannot be nil'
        end

        if window_attr.empty?
          raise ArgumentError, 'window attribute cannot be empty'
        end

        if template_path.nil?
          raise ArgumentError, 'template path cannot be nil'
        end
      end
    end
  end
end
