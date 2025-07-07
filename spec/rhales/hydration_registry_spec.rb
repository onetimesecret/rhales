# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Rhales::HydrationRegistry do
  # TDD - no implementation yet

  describe '.register' do
    before do
      described_class.clear!
    end

    after do
      described_class.clear!
    end

    it 'registers a window attribute with template path' do
      expect do
        described_class.register('data', 'layouts/main.rue:2')
      end.not_to raise_error
    end

    it 'allows registering different window attributes' do
      expect do
        described_class.register('layoutData', 'layouts/main.rue:2')
        described_class.register('pageData', 'home.rue:1')
      end.not_to raise_error
    end

    context 'when registering the same window attribute twice' do
      it 'raises HydrationCollisionError without merge strategy' do
        described_class.register('data', 'layouts/main.rue:2')

        expect do
          described_class.register('data', 'home.rue:1')
        end.to raise_error(Rhales::HydrationCollisionError) do |error|
          expect(error.window_attribute).to eq('data')
          expect(error.first_path).to eq('layouts/main.rue:2')
          expect(error.conflict_path).to eq('home.rue:1')
        end
      end

      it 'allows registration with merge strategy' do
        described_class.register('data', 'layouts/main.rue:2')

        expect do
          described_class.register('data', 'home.rue:1', 'deep')
        end.not_to raise_error
      end
    end

    context 'with merge strategies' do
      it 'stores the merge strategy' do
        described_class.register('appData', 'layouts/main.rue:2')
        described_class.register('appData', 'home.rue:1', 'shallow')

        # We'll need a way to inspect the registry for testing
        registry = described_class.registry
        expect(registry['appData'][:merge_strategy]).to eq('shallow')
      end

      it 'accepts different merge strategies' do
        %w[shallow deep strict].each do |strategy|
          described_class.clear!
          described_class.register('data', 'layouts/main.rue:2')

          expect do
            described_class.register('data', 'home.rue:1', strategy)
          end.not_to raise_error
        end
      end
    end
  end

  describe '.clear!' do
    it 'clears all registered window attributes' do
      described_class.register('data', 'layouts/main.rue:2')
      described_class.register('pageData', 'home.rue:1')

      described_class.clear!

      # Should be able to register the same attributes again
      expect do
        described_class.register('data', 'other.rue:3')
        described_class.register('pageData', 'another.rue:4')
      end.not_to raise_error
    end
  end

  describe 'thread safety' do
    it 'maintains separate registries per thread' do
      main_thread_path = 'main_thread.rue:1'
      other_thread_path = 'other_thread.rue:1'

      # Register in main thread
      described_class.register('threadData', main_thread_path)

      # Register same attribute in another thread
      thread = Thread.new do
        described_class.clear!
        described_class.register('threadData', other_thread_path)

        # Should not see main thread's registration
        registry = described_class.registry
        registry['threadData'][:path]
      end

      result = thread.value
      expect(result).to eq(other_thread_path)

      # Main thread should still have its original registration
      registry = described_class.registry
      expect(registry['threadData'][:path]).to eq(main_thread_path)
    end
  end

  describe 'edge cases' do
    before { described_class.clear! }
    after { described_class.clear! }

    it 'handles nil window attribute' do
      expect do
        described_class.register(nil, 'template.rue:1')
      end.to raise_error(ArgumentError, /window attribute cannot be nil/)
    end

    it 'handles empty window attribute' do
      expect do
        described_class.register('', 'template.rue:1')
      end.to raise_error(ArgumentError, /window attribute cannot be empty/)
    end

    it 'handles nil template path' do
      expect do
        described_class.register('data', nil)
      end.to raise_error(ArgumentError, /template path cannot be nil/)
    end

    it 'allows registering with nil merge strategy' do
      expect do
        described_class.register('data', 'template.rue:1', nil)
      end.not_to raise_error
    end
  end

  describe 'integration with Context' do
    it 'provides a way to get a scoped registry instance' do
      # This test documents expected usage pattern
      # The registry should be scoped to a request/context

      # Future implementation might look like:
      # context = Rhales::Context.new
      # registry = context.hydration_registry
      # registry.register('data', 'template.rue:1')

      # For now, we're using class methods which need manual clearing
      expect(described_class).to respond_to(:clear!)
    end
  end
end
