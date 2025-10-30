# lib/rhales/utils/logging_helpers.rb

module Rhales
  module Utils
    # Helper methods for consistent logging and timing instrumentation across Rhales components
    module LoggingHelpers
      include Rhales::Utils

      # Log with timing for an operation
      #
      # @param logger [Logger] The logger instance to use
      # @param level [Symbol] The log level (:debug, :info, :warn, :error)
      # @param message [String] The log message
      # @param metadata [Hash] Additional metadata to include in the log
      # @yield The block to execute and time
      # @return The result of the block
      #
      # Logs the operation with timing information in microseconds.
      def log_timed_operation(logger, level, message, **metadata)
        start_time = now_in_μs
        result = yield
        duration = now_in_μs - start_time

        log_with_metadata(logger, level, message, metadata.merge(duration: duration))

        result
      rescue StandardError => ex
        duration = now_in_μs - start_time
        log_with_metadata(logger, :error, "#{message} failed",
          metadata.merge(
            duration: duration,
            error: ex.message,
            error_class: ex.class.name,
          )
        )
        raise
      end

      # Log a message with structured metadata
      def log_with_metadata(logger, level, message, metadata = {})
        return logger.public_send(level, message) if metadata.empty?

        metadata_str = metadata.map { |k, v| "#{k}=#{format_value(v)}" }.join(' ')
        logger.public_send(level, "#{message}: #{metadata_str}")
      end

      private

      # Format individual log values
      def format_value(value)
        case value
        when String
          value.include?(' ') ? "\"#{value}\"" : value
        when Symbol, Numeric, true, false, nil
          value.to_s
        when Array
          # For arrays longer than 5 items, show count + first/last items
          if value.size > 5
            first_three = value.first(3).join(', ')
            last_two = value.last(2).join(', ')
            "[#{value.size} items: #{first_three} ... #{last_two}]"
          elsif value.empty?
            '[]'
          else
            "[#{value.join(', ')}]"
          end
        else
          value.to_s
        end
      end
    end
  end
end
