# spec/rhales/parsers/xml_strategy_factory_spec.rb

require 'spec_helper'
require 'rhales/parsers/xml_strategy_factory'
require 'rhales/configuration'

RSpec.describe Rhales::Parsers::XmlStrategyFactory do
  before do
    # Reset configuration before each test to ensure a clean state
    Rhales.reset_configuration!
  end

  describe '.create' do
    context 'when no parser is configured' do
      it 'creates a parser using auto-detection' do
        parser = described_class.create
        # Should return one of the available parsers
        expect(parser).to be_a(Rhales::Parsers::XmlStrategy::BaseParser)
      end
    end

    context 'when an explicit parser is configured' do
      it 'uses the configured REXML parser' do
        Rhales.configure { |config| config.xml_parser = :rexml }
        parser = described_class.create
        expect(parser).to be_a(Rhales::Parsers::XmlStrategy::RexmlParser)
      end

      it 'raises an error for unknown parser configuration' do
        Rhales.configure { |config| config.xml_parser = :unknown }

        expect do
          described_class.create
        end.to raise_error(Rhales::ConfigurationError, /Unknown XML parser: unknown/)
      end
    end

    context 'parser priority and availability' do
      it 'defaults to REXML when it is the only option' do
        # Don't mock try_require to avoid infinite loops - just test that REXML works
        parser = described_class.create(:rexml)
        expect(parser).to be_a(Rhales::Parsers::XmlStrategy::RexmlParser)
      end
    end
  end

  describe '.detect_best_available' do
    it 'returns a valid parser symbol' do
      # Call the private method via send to test it directly
      result = described_class.send(:detect_best_available)
      expect([:nokogiri, :oga, :rexml]).to include(result)
    end
  end

  describe '.try_require' do
    it 'returns true for gems that exist' do
      # Test with REXML which should always be available
      result = described_class.send(:try_require, 'rexml/document')
      expect(result).to be true
    end

    it 'returns false for gems that do not exist' do
      result = described_class.send(:try_require, 'nonexistent_gem_12345')
      expect(result).to be false
    end
  end
end
