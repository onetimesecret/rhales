# spec/rhales/utils_spec.rb
# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe Rhales::Utils do
  # Create a test class that includes the Utils module
  let(:test_class) do
    Class.new do
      include Rhales::Utils
    end
  end
  let(:test_instance) { test_class.new }

  describe '#now' do
    it 'returns current time in UTC' do
      result = test_instance.now

      expect(result).to be_a(Time)
      expect(result.utc?).to be true
    end

    it 'returns a time close to Time.now.utc' do
      result = test_instance.now
      expected = Time.now.utc

      # Should be within 1 second of each other
      expect((result - expected).abs).to be < 1
    end
  end

  describe '#now_in_μs' do
    it 'returns an integer' do
      result = test_instance.now_in_μs

      expect(result).to be_a(Integer)
    end

    it 'returns monotonic time in microseconds' do
      result = test_instance.now_in_μs

      # Should be a large positive number (microseconds since some arbitrary point)
      expect(result).to be > 0
    end

    it 'increases over time' do
      first = test_instance.now_in_μs
      sleep(0.001) # Sleep 1 millisecond = 1000 microseconds
      second = test_instance.now_in_μs

      expect(second).to be > first
      # Should increase by at least 1000 microseconds (allowing some tolerance)
      expect(second - first).to be >= 500
    end

    it 'provides microsecond precision' do
      first = test_instance.now_in_μs
      sleep(0.0001) # Sleep 0.1 millisecond = 100 microseconds
      second = test_instance.now_in_μs

      # Should detect sub-millisecond differences
      expect(second).to be > first
    end
  end

  describe '#now_in_microseconds' do
    it 'is an alias for now_in_μs' do
      expect(test_class.instance_method(:now_in_microseconds))
        .to eq(test_class.instance_method(:now_in_μs))
    end

    it 'returns the same value as now_in_μs' do
      # Both should return very close values (within microseconds of each other)
      value1 = test_instance.now_in_μs
      value2 = test_instance.now_in_microseconds

      # Should be within 1000 microseconds (1ms) of each other
      expect((value1 - value2).abs).to be < 1000
    end
  end

  describe 'duration calculation' do
    it 'can be used to measure operation duration in microseconds' do
      start = test_instance.now_in_μs

      # Simulate some work
      sleep(0.005) # 5 milliseconds = 5000 microseconds

      duration = test_instance.now_in_μs - start

      # Duration should be in microseconds (at least 4000, allowing tolerance)
      expect(duration).to be_a(Integer)
      expect(duration).to be >= 4000
      expect(duration).to be < 10000 # Should be less than 10ms
    end

    it 'provides consistent integer microsecond values for timing' do
      durations = []

      5.times do
        start = test_instance.now_in_μs
        sleep(0.001) # 1 millisecond
        durations << (test_instance.now_in_μs - start)
      end

      # All durations should be integers
      expect(durations).to all(be_a(Integer))

      # All should be in microsecond range (roughly 1000 μs ± tolerance)
      expect(durations).to all(be >= 500)
      expect(durations).to all(be < 3000)
    end
  end
end
