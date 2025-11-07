# spec/rhales/hydration/hydration_data_aggregator_spec.rb
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Rhales::HydrationDataAggregator do
  let(:mock_config) do
    config = Rhales::Configuration.new
    config.hydration_mismatch_format = hydration_mismatch_format
    config.hydration_authority = hydration_authority
    config
  end

  let(:hydration_mismatch_format) { :compact }
  let(:hydration_authority) { :schema }

  let(:mock_context) { {} }
  let(:aggregator) { described_class.new(mock_context) }

  describe '#log_hydration_mismatch' do
    let(:template_path) { 'views/app.html' }
    let(:window_attr) { 'app.hydration' }
    let(:expected_keys) { ['user.id', 'user.name', 'settings.theme', 'api_key'] }
    let(:actual_keys) { ['user.id', 'user.email', 'settings.language', 'extra_field'] }
    let(:missing_keys) { ['user.name', 'settings.theme', 'api_key'] }
    let(:extra_keys) { ['user.email', 'settings.language', 'extra_field'] }
    let(:data_size) { 7 }

    before do
      # Allow Rhales.config to return our mock config
      allow(Rhales).to receive(:config).and_return(mock_config)
      # Mock the logger
      allow(Rhales).to receive(:logger).and_return(double('logger', warn: nil))
    end

    context 'with compact format' do
      let(:hydration_mismatch_format) { :compact }

      it 'logs mismatches in compact format' do
        logger = double('logger')
        expect(logger).to receive(:warn) do |message|
          expect(message).to include('Schema mismatch')
          expect(message).to include('3 missing')
          expect(message).to include('3 extra')
          expect(message).to include('template=views/app.html')
          expect(message).to include('window_attribute=app.hydration')
          expect(message).to include('missing_keys=[user.name, settings.theme, api_key]')
          expect(message).to include('extra_keys=[user.email, settings.language, extra_field]')
          expect(message).to include('client_data_size=7')
        end
        allow(Rhales).to receive(:logger).and_return(logger)

        aggregator.send(:log_hydration_mismatch, template_path, window_attr, expected_keys, actual_keys, missing_keys, extra_keys, data_size)
      end

      # Note: Compact format doesn't include authority information in the output
      # Authority is only shown in sidebyside and json formats
    end

    context 'with multiline format' do
      let(:hydration_mismatch_format) { :multiline }

      it 'logs mismatches in multiline format' do
        logger = double('logger')
        expect(logger).to receive(:warn) do |message|
          expect(message).to include('Hydration schema mismatch')
          expect(message).to include('Template: views/app.html')
          expect(message).to include('Window: app.hydration')
          expect(message).to include('Data size: 7')
          expect(message).to include('✗ Schema expects (3)')
          expect(message).to include('user.name')
          expect(message).to include('settings.theme')
          expect(message).to include('+ Data provides (3)')
          expect(message).to include('user.email')
        end
        allow(Rhales).to receive(:logger).and_return(logger)

        aggregator.send(:log_hydration_mismatch, template_path, window_attr, expected_keys, actual_keys, missing_keys, extra_keys, data_size)
      end

      # Note: Multiline format doesn't include authority information
    end

    context 'with sidebyside format' do
      let(:hydration_mismatch_format) { :sidebyside }

      it 'logs mismatches in side-by-side format' do
        logger = double('logger')
        expect(logger).to receive(:warn) do |message|
          expect(message).to include('Hydration schema mismatch')
          expect(message).to include('Template: views/app.html')
          expect(message).to include('Window: app.hydration')
          expect(message).to include('│')
        end
        allow(Rhales).to receive(:logger).and_return(logger)

        aggregator.send(:log_hydration_mismatch, template_path, window_attr, expected_keys, actual_keys, missing_keys, extra_keys, data_size)
      end

      context 'with schema authority' do
        let(:hydration_authority) { :schema }

        it 'shows schema as correct side' do
          logger = double('logger')
          expect(logger).to receive(:warn) do |message|
            expect(message).to include('Schema (correct)')
            expect(message).to include('Data (fix)')
            expect(message).to include('← add to data source')
            expect(message).to include('← remove from data source')
          end
          allow(Rhales).to receive(:logger).and_return(logger)

          aggregator.send(:log_hydration_mismatch, template_path, window_attr, expected_keys, actual_keys, missing_keys, extra_keys, data_size)
        end
      end

      context 'with data authority' do
        let(:hydration_authority) { :data }

        it 'shows data as correct side' do
          logger = double('logger')
          expect(logger).to receive(:warn) do |message|
            expect(message).to include('Schema (fix)')
            expect(message).to include('Data (correct)')
            expect(message).to include('← add to schema')
            expect(message).to include('← remove from schema')
          end
          allow(Rhales).to receive(:logger).and_return(logger)

          aggregator.send(:log_hydration_mismatch, template_path, window_attr, expected_keys, actual_keys, missing_keys, extra_keys, data_size)
        end
      end
    end

    context 'with json format' do
      let(:hydration_mismatch_format) { :json }

      it 'logs mismatches in JSON format' do
        logger = double('logger')
        expect(logger).to receive(:warn) do |message|
          json_data = JSON.parse(message)
          expect(json_data['event']).to eq('hydration_schema_mismatch')
          expect(json_data['template']).to eq('views/app.html')
          expect(json_data['window_attribute']).to eq('app.hydration')
          expect(json_data['authority']).to eq('schema')
          expect(json_data['schema']['key_count']).to eq(4)
          expect(json_data['data']['key_count']).to eq(7)
          expect(json_data['diff']['missing_keys']).to eq(missing_keys)
          expect(json_data['diff']['extra_keys']).to eq(extra_keys)
        end
        allow(Rhales).to receive(:logger).and_return(logger)

        aggregator.send(:log_hydration_mismatch, template_path, window_attr, expected_keys, actual_keys, missing_keys, extra_keys, data_size)
      end
    end

    context 'with invalid format' do
      let(:hydration_mismatch_format) { :invalid_format }

      it 'raises an ArgumentError' do
        # Need to set the format directly since we're testing invalid values
        mock_config.hydration_mismatch_format = :invalid_format

        expect {
          aggregator.send(:log_hydration_mismatch, template_path, window_attr, expected_keys, actual_keys, missing_keys, extra_keys, data_size)
        }.to raise_error(ArgumentError, /Unknown hydration_mismatch_format/)
      end
    end

    context 'edge cases' do
      it 'handles empty missing and extra arrays' do
        expect {
          aggregator.send(:log_hydration_mismatch, template_path, window_attr, expected_keys, expected_keys, [], [], data_size)
        }.not_to raise_error
      end

      it 'handles empty expected and actual arrays' do
        expect {
          aggregator.send(:log_hydration_mismatch, template_path, window_attr, [], [], [], [], 0)
        }.not_to raise_error
      end

      it 'handles very long key names' do
        long_key = 'very.deeply.nested.structure.with.many.levels.of.nesting.that.goes.on.and.on'
        expect {
          aggregator.send(:log_hydration_mismatch, template_path, window_attr, [long_key], [], [long_key], [], 1)
        }.not_to raise_error
      end
    end
  end

  describe '#format_compact' do
    it 'returns a single-line formatted string' do
      result = aggregator.send(:format_compact,
        'test.html',
        'window.data',
        ['key1', 'key2'],
        ['key1', 'key3'],
        ['key2'],
        ['key3'],
        3
      )

      expect(result).to be_a(String)
      expect(result).to include('Schema mismatch')
      expect(result).to include('1 missing')
      expect(result).to include('1 extra')
      expect(result).to include('template=test.html')
      expect(result).to include('window_attribute=window.data')
    end
  end

  describe '#format_multiline' do
    it 'returns a formatted multiline string' do
      result = aggregator.send(:format_multiline,
        'test.html',
        'window.data',
        ['key1', 'key2'],
        ['key1', 'key3'],
        ['key2'],
        ['key3'],
        3
      )

      expect(result).to be_a(String)
      expect(result).to include('Hydration schema mismatch')
      expect(result).to include('✗ Schema expects')
      expect(result).to include('+ Data provides')
      expect(result.lines.count).to be > 3
    end
  end

  describe '#format_sidebyside' do
    it 'returns a table-formatted string' do
      result = aggregator.send(:format_sidebyside,
        'test.html',
        'window.data',
        ['key1', 'key2'],
        ['key1', 'key3'],
        ['key2'],
        ['key3'],
        3
      )

      expect(result).to be_a(String)
      expect(result).to include('│')
      expect(result).to include('correct')
      expect(result).to include('fix')
    end
  end

  describe '#format_json' do
    it 'returns a valid JSON string' do
      result = aggregator.send(:format_json,
        'test.html',
        'window.data',
        ['key1', 'key2'],
        ['key1', 'key3'],
        ['key2'],
        ['key3'],
        3
      )

      expect { JSON.parse(result) }.not_to raise_error

      json_data = JSON.parse(result)
      expect(json_data['event']).to eq('hydration_schema_mismatch')
      expect(json_data['template']).to eq('test.html')
      expect(json_data['window_attribute']).to eq('window.data')
    end
  end

  describe 'configuration integration' do
    it 'respects the configured format from Rhales configuration' do
      # Test that the aggregator uses Rhales.config settings
      [:compact, :multiline, :sidebyside, :json].each do |format|
        allow(Rhales).to receive(:config).and_return(double(
          hydration_mismatch_format: format,
          hydration_authority: :schema
        ))

        test_aggregator = described_class.new({})

        # We test the behavior by calling the log method and checking format
        logger = double('logger')
        expect(logger).to receive(:warn)
        allow(Rhales).to receive(:logger).and_return(logger)

        # This should use the configured format
        test_aggregator.send(:log_hydration_mismatch, 'test', 'window', [], [], [], [], 0)
      end
    end

    it 'respects the configured authority from Rhales configuration' do
      # Test that the aggregator uses Rhales.config authority setting
      [:schema, :data].each do |authority|
        allow(Rhales).to receive(:config).and_return(double(
          hydration_mismatch_format: :json,
          hydration_authority: authority
        ))

        test_aggregator = described_class.new({})

        # Test by checking the JSON output includes the correct authority
        logger = double('logger')
        expect(logger).to receive(:warn) do |message|
          json_data = JSON.parse(message)
          expect(json_data['authority']).to eq(authority.to_s)
        end
        allow(Rhales).to receive(:logger).and_return(logger)

        test_aggregator.send(:log_hydration_mismatch, 'test', 'window', [], [], [], [], 0)
      end
    end
  end
end
