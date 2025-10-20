# lib/rhales/utils/logging_helpers.rb

module Rhales
  module Utils
    # Helper methods for consistent logging and timing instrumentation across Rhales components
    # Compatible with both standard Logger and SemanticLogger
    module LoggingHelpers
      
      # Time a block and return [result, duration_ms]
      def time_operation(&block)
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        result = yield
        duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round(2)
        [result, duration_ms]
      end
      
      # Log with timing for an operation - compatible with both Logger types
      def log_timed_operation(logger, level, message, **metadata, &block)
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        result = yield
        duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round(2)
        
        # Format message with metadata for standard Logger compatibility
        formatted_message = format_log_message(message, metadata.merge(duration_ms: duration_ms))
        structured_log(logger, level, formatted_message, metadata.merge(duration_ms: duration_ms))
        
        result
      rescue => ex
        duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round(2)
        error_metadata = metadata.merge(
          duration_ms: duration_ms,
          error: ex.message,
          error_class: ex.class.name
        )
        error_message = format_log_message("#{message} failed", error_metadata)
        structured_log(logger, :error, error_message, error_metadata)
        raise
      end
      
      # Log a message with structured data, supporting both Logger types
      def structured_log(logger, level, message, metadata = {})
        # Check if logger supports structured logging (like SemanticLogger)
        if logger.respond_to?(:tagged) || metadata.empty?
          # SemanticLogger or simple message
          if metadata.empty?
            logger.public_send(level, message)
          else
            # Try structured logging first, fallback to formatted string
            begin
              logger.public_send(level, message, **metadata)
            rescue ArgumentError
              # Standard Logger - use formatted string
              formatted = format_log_message(message, metadata)
              logger.public_send(level, formatted)
            end
          end
        else
          # Standard Logger - use formatted string
          formatted = format_log_message(message, metadata)
          logger.public_send(level, formatted)
        end
      end
      
      # Format log message with metadata for standard Logger
      def format_log_message(message, metadata = {})
        return message if metadata.empty?
        
        metadata_str = metadata.map { |k, v| "#{k}=#{format_log_value(v)}" }.join(' ')
        "#{message}: #{metadata_str}"
      end
      
      # Format individual log values
      def format_log_value(value)
        case value
        when String, Symbol, Numeric, true, false, nil
          value.to_s
        when Array
          "[#{value.join(', ')}]"
        else
          value.to_s
        end
      end
      
      # Format byte size for logging
      def format_size(bytes)
        return 0 unless bytes
        case bytes
        when 0...1024 then "#{bytes}B"
        when 1024...1048576 then "#{(bytes / 1024.0).round(1)}KB"
        else "#{(bytes / 1048576.0).round(1)}MB"
        end
      end
    end
  end
end