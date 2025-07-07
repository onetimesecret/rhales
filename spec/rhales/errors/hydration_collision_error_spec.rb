# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Rhales::HydrationCollisionError do
  # TDD - no implementation yet
  describe '#initialize' do
    it 'accepts window attribute name and conflicting template paths' do
      error = described_class.new('data', 'layouts/main.rue:2', 'home.rue:1')
      expect(error).to be_a(Rhales::Error)
    end
  end

  describe '#message' do
    context 'with basic collision' do
      let(:error) do
        described_class.new(
          'data',
          'layouts/main.rue:2',
          'home.rue:1'
        )
      end

      it 'generates a detailed error message' do
        message = error.message

        expect(message).to include('Window attribute collision detected')
        expect(message).to include("Attribute: 'data'")
        expect(message).to include('First defined: layouts/main.rue:2')
        expect(message).to include('Conflict with: home.rue:1')
      end

      it 'includes helpful quick fixes' do
        message = error.message

        expect(message).to include('Quick fixes:')
        expect(message).to include('1. Rename one: <data window="homeData">')
        expect(message).to include('2. Enable merging: <data window="data" merge="deep">')
      end

      it 'includes documentation link' do
        message = error.message

        expect(message).to include('Learn more: https://rhales.dev/docs/data-boundaries#collisions')
      end
    end

    context 'with custom window attributes' do
      let(:error) do
        described_class.new(
          'appState',
          'components/header.rue:5',
          'components/footer.rue:10'
        )
      end

      it 'uses the custom attribute name in suggestions' do
        message = error.message

        expect(message).to include("Attribute: 'appState'")
        expect(message).to include('<data window="headerState">')
        expect(message).to include('<data window="appState" merge="deep">')
      end
    end

    context 'with full file paths' do
      let(:error) do
        described_class.new(
          'config',
          '/app/views/layouts/application.rue:15',
          '/app/views/dashboard/index.rue:3'
        )
      end

      it 'preserves full paths in error message' do
        message = error.message

        expect(message).to include('First defined: /app/views/layouts/application.rue:15')
        expect(message).to include('Conflict with: /app/views/dashboard/index.rue:3')
      end
    end
  end

  describe '#to_s' do
    it 'returns the same as message' do
      error = described_class.new('data', 'a.rue:1', 'b.rue:2')
      expect(error.to_s).to eq(error.message)
    end
  end

  describe 'inheritance' do
    it 'inherits from Rhales::Error' do
      expect(described_class.superclass).to eq(Rhales::Error)
    end

    it 'can be rescued as Rhales::Error' do
      expect do
        raise described_class.new('data', 'a.rue:1', 'b.rue:2')
      end.to raise_error(Rhales::Error)
    end
  end

  describe 'error context' do
    context 'when paths include <data> tag content' do
      let(:error) do
        described_class.new(
          'userData',
          'layouts/main.rue:2:<data window="userData">',
          'profile.rue:1:<data window="userData">'
        )
      end

      it 'includes the actual tag content in the message' do
        message = error.message

        expect(message).to include('<data window="userData">')
        expect(message).to match(/First defined:.*<data window="userData">/)
        expect(message).to match(/Conflict with:.*<data window="userData">/)
      end
    end
  end
end
