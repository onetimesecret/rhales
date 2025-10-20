# lib/rhales/utils/logging_helpers.rb

module Rhales
  module Utils
    # Helper methods for consistent logging and timing instrumentation across Rhales components
    module LoggingHelpers

      # Log with timing for an operation
      def log_timed_operation(logger, level, message, **metadata, &block)
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        result = yield
        duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round(2)

        log_with_metadata(logger, level, message, metadata.merge(duration_ms: duration_ms))

        result
      rescue => ex
        duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round(2)
        log_with_metadata(logger, :error, "#{message} failed",
          metadata.merge(
            duration_ms: duration_ms,
            error: ex.message,
            error_class: ex.class.name
          ))
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
          "[#{value.join(', ')}]"
        else
          value.to_s
        end
      end
    end
  end
end
