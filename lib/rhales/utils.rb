# lib/rhales/utils.rb

module Rhales
  module Utils
    # Utility modules and classes

    # @return [Time] Current time in UTC
    def now
      Time.now.utc
    end

    # Returns the current time in microseconds.
    # This is used to measure the duration of Database commands.
    #
    # Alias: now_in_microseconds
    #
    # @return [Integer] The current time in microseconds.
    def now_in_μs
      Process.clock_gettime(Process::CLOCK_MONOTONIC, :microsecond)
    end
    alias now_in_microseconds now_in_μs
  end
end

require_relative 'utils/json_serializer'
require_relative 'utils/schema_generator'
require_relative 'utils/schema_extractor'
require_relative 'utils/logging_helpers'
