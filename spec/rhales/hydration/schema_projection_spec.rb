# spec/rhales/hydration/schema_projection_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

# Step 1 of RFC 0001: the <schema> can act as a mechanical allowlist for client
# data via the schema_projection config. These tests exercise the projection
# logic in isolation (load_schema_cached is stubbed to stand in for a generated
# JSON Schema file).
RSpec.describe 'Rhales::HydrationDataAggregator schema projection' do
  let(:context) { double('context', client: client_data) }
  let(:aggregator) { Rhales::HydrationDataAggregator.new(context) }
  let(:client_data) { { 'name' => 'Alice', 'password' => 'secret', 'apiKey' => 'xyz' } }

  # A reliable JSON Schema declaring only `name`.
  let(:json_schema) do
    { 'type' => 'object', 'properties' => { 'name' => { 'type' => 'string' } } }
  end

  before do
    allow(Rhales).to receive(:logger).and_return(double('logger', warn: nil, info: nil, debug: nil))
  end

  def configure_projection(mode)
    config = Rhales::Configuration.new
    config.schema_projection = mode
    allow(Rhales).to receive(:config).and_return(config)
    allow(Rhales).to receive(:configuration).and_return(config)
  end

  describe '#project_client_data' do
    context 'when schema_projection is :off (default)' do
      before { configure_projection(:off) }

      it 'returns the client data unchanged' do
        expect(aggregator.send(:project_client_data, 'dash', client_data)).to eq(client_data)
      end
    end

    context 'when schema_projection is :strip with a reliable schema' do
      before do
        configure_projection(:strip)
        allow(aggregator).to receive(:load_schema_cached).with('dash').and_return(json_schema)
      end

      it 'drops keys not declared in the schema' do
        result = aggregator.send(:project_client_data, 'dash', client_data)
        expect(result).to eq({ 'name' => 'Alice' })
      end

      it 'preserves the original key type (symbol keys)' do
        sym = { name: 'Alice', password: 'x' }
        result = aggregator.send(:project_client_data, 'dash', sym)
        expect(result).to eq({ name: 'Alice' })
      end
    end

    context 'when schema_projection is :strict' do
      before do
        configure_projection(:strict)
        allow(aggregator).to receive(:load_schema_cached).with('dash').and_return(json_schema)
      end

      it 'raises HydrationSchemaViolationError listing the undeclared keys' do
        expect { aggregator.send(:project_client_data, 'dash', client_data) }
          .to raise_error(Rhales::HydrationSchemaViolationError) do |error|
            expect(error.undeclared_keys).to contain_exactly('password', 'apiKey')
            expect(error.message).to include('password')
          end
      end

      it 'returns the data unchanged when every key is declared' do
        allow(aggregator).to receive(:load_schema_cached).with('dash')
          .and_return({ 'properties' => { 'name' => {}, 'password' => {}, 'apiKey' => {} } })
        result = aggregator.send(:project_client_data, 'dash', client_data)
        expect(result).to eq(client_data)
      end
    end

    context 'when projection is requested but no reliable JSON Schema exists' do
      before do
        configure_projection(:strict)
        allow(aggregator).to receive(:load_schema_cached).with('dash').and_return(nil)
      end

      it 'does not drop or raise; emits unprojected data and warns' do
        logger = double('logger', info: nil, debug: nil)
        expect(logger).to receive(:warn).at_least(:once)
        allow(Rhales).to receive(:logger).and_return(logger)

        result = aggregator.send(:project_client_data, 'dash', client_data)
        expect(result).to eq(client_data)
      end
    end

    context 'with an empty-object schema' do
      before do
        configure_projection(:strip)
        allow(aggregator).to receive(:load_schema_cached).with('dash').and_return({ 'properties' => {} })
      end

      it 'projects to an empty hash since nothing is declared' do
        expect(aggregator.send(:project_client_data, 'dash', client_data)).to eq({})
      end
    end

    context 'when client data is not a hash' do
      before { configure_projection(:strip) }

      it 'returns it unchanged' do
        expect(aggregator.send(:project_client_data, 'dash', nil)).to be_nil
      end
    end
  end

  describe '#reliable_expected_keys' do
    it 'returns top-level property names from a generated JSON Schema' do
      allow(aggregator).to receive(:load_schema_cached).with('dash').and_return(json_schema)
      expect(aggregator.send(:reliable_expected_keys, 'dash')).to eq(['name'])
    end

    it 'returns nil when no JSON Schema file is present (never guesses from regex)' do
      allow(aggregator).to receive(:load_schema_cached).with('dash').and_return(nil)
      expect(aggregator.send(:reliable_expected_keys, 'dash')).to be_nil
    end
  end
end
