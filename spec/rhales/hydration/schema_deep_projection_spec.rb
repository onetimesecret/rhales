# spec/rhales/hydration/schema_deep_projection_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

# RFC-001 Step 2a: projection follows the generated JSON Schema's nested
# structure (objects, arrays, records, $ref) instead of stopping at top-level
# keys. load_schema_cached is stubbed to stand in for a generated schema file.
RSpec.describe 'Rhales::HydrationDataAggregator deep schema projection' do
  let(:context) { double('context', client: nil) }
  let(:aggregator) { Rhales::HydrationDataAggregator.new(context) }

  before do
    allow(Rhales).to receive(:logger).and_return(double('logger', warn: nil, info: nil, debug: nil))
  end

  def configure_projection(mode)
    config = Rhales::Configuration.new
    config.schema_projection = mode
    allow(Rhales).to receive(:config).and_return(config)
    allow(Rhales).to receive(:configuration).and_return(config)
  end

  def with_schema(schema)
    allow(aggregator).to receive(:load_schema_cached).and_return(schema)
  end

  def project(data)
    aggregator.send(:project_client_data, 'tpl', data)
  end

  describe 'nested objects' do
    let(:schema) do
      {
        'type' => 'object',
        'properties' => {
          'user' => {
            'type' => 'object',
            'properties' => { 'name' => { 'type' => 'string' } },
          },
        },
      }
    end

    it 'drops undeclared keys nested inside objects (:strip)' do
      configure_projection(:strip)
      with_schema(schema)
      result = project({ 'user' => { 'name' => 'Alice', 'password' => 'secret' }, 'extra' => 1 })
      expect(result).to eq({ 'user' => { 'name' => 'Alice' } })
    end

    it 'reports the dotted path of nested undeclared keys (:strict)' do
      configure_projection(:strict)
      with_schema(schema)
      expect { project({ 'user' => { 'name' => 'Alice', 'password' => 'secret' } }) }
        .to raise_error(Rhales::HydrationSchemaViolationError) do |error|
          expect(error.undeclared_keys).to include('user.password')
        end
    end
  end

  describe 'arrays of objects' do
    let(:schema) do
      {
        'type' => 'object',
        'properties' => {
          'items' => {
            'type' => 'array',
            'items' => { 'type' => 'object', 'properties' => { 'id' => { 'type' => 'number' } } },
          },
        },
      }
    end

    it 'projects each array element through the item schema' do
      configure_projection(:strip)
      with_schema(schema)
      result = project({ 'items' => [{ 'id' => 1, 'secret' => 'x' }, { 'id' => 2, 'secret' => 'y' }] })
      expect(result).to eq({ 'items' => [{ 'id' => 1 }, { 'id' => 2 }] })
    end
  end

  describe '$ref resolution' do
    let(:schema) do
      {
        '$ref' => '#/$defs/State',
        '$defs' => {
          'State' => {
            'type' => 'object',
            'properties' => { 'token' => { 'type' => 'string' } },
          },
        },
      }
    end

    it 'follows a local $ref at the root before projecting' do
      configure_projection(:strip)
      with_schema(schema)
      result = project({ 'token' => 'abc', 'leak' => 'no' })
      expect(result).to eq({ 'token' => 'abc' })
    end
  end

  describe 'typed records (additionalProperties)' do
    let(:schema) do
      {
        'type' => 'object',
        'properties' => {
          'flags' => {
            'type' => 'object',
            'additionalProperties' => {
              'type' => 'object',
              'properties' => { 'on' => { 'type' => 'boolean' } },
            },
          },
        },
      }
    end

    it 'keeps arbitrary record keys but projects their values' do
      configure_projection(:strip)
      with_schema(schema)
      result = project({ 'flags' => { 'a' => { 'on' => true, 'x' => 1 }, 'b' => { 'on' => false } } })
      expect(result).to eq({ 'flags' => { 'a' => { 'on' => true }, 'b' => { 'on' => false } } })
    end
  end

  describe 'conservative on subschemas it cannot interpret' do
    let(:schema) do
      {
        'type' => 'object',
        'properties' => {
          'payload' => { 'anyOf' => [{ 'type' => 'object' }, { 'type' => 'string' }] },
        },
      }
    end

    it 'does not drop inside an anyOf/oneOf/allOf subschema' do
      configure_projection(:strict)
      with_schema(schema)
      data = { 'payload' => { 'anything' => 1, 'nested' => { 'deep' => true } } }
      expect { project(data) }.not_to raise_error
      expect(project(data)).to eq(data)
    end
  end

  describe 'symbol keys' do
    let(:schema) do
      {
        'type' => 'object',
        'properties' => { 'user' => { 'type' => 'object', 'properties' => { 'name' => {} } } },
      }
    end

    it 'preserves the original key type while projecting nested data' do
      configure_projection(:strip)
      with_schema(schema)
      result = project({ user: { name: 'Alice', password: 'x' } })
      expect(result).to eq({ user: { name: 'Alice' } })
    end
  end
end
