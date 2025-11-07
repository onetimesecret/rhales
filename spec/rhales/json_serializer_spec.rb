# spec/rhales/json_serializer_spec.rb

require 'spec_helper'

RSpec.describe Rhales::JSONSerializer do
  describe '.dump' do
    it 'serializes a hash to JSON string' do
      data = { 'user' => 'Alice', 'count' => 42 }
      result = described_class.dump(data)

      expect(result).to be_a(String)
      expect(result).to include('"user"')
      expect(result).to include('"Alice"')
      expect(result).to include('"count"')
      expect(result).to include('42')
    end

    it 'serializes arrays' do
      data = [1, 2, 3]
      result = described_class.dump(data)

      expect(result).to eq('[1,2,3]')
    end

    it 'serializes nested structures' do
      data = {
        'user' => {
          'id' => 1,
          'name' => 'Alice'
        },
        'items' => [
          { 'id' => 1, 'name' => 'Widget' },
          { 'id' => 2, 'name' => 'Gadget' }
        ]
      }
      result = described_class.dump(data)

      expect(result).to be_a(String)
      expect(result).to include('"user"')
      expect(result).to include('"items"')
      expect(result).to include('"Widget"')
    end

    it 'handles nil values' do
      result = described_class.dump(nil)
      expect(result).to eq('null')
    end

    it 'produces compact output' do
      data = { 'user' => 'Alice', 'count' => 42 }
      result = described_class.dump(data)

      # Compact format should not have extra whitespace
      expect(result).not_to match(/\n/)
      expect(result).not_to match(/\s{2,}/)
    end
  end

  describe '.pretty_dump' do
    it 'serializes with pretty formatting' do
      data = { 'user' => 'Alice', 'count' => 42 }
      result = described_class.pretty_dump(data)

      expect(result).to be_a(String)
      expect(result).to include('"user"')
      expect(result).to include('"Alice"')
      expect(result).to include('"count"')
      expect(result).to include('42')
      # Pretty format should have newlines and indentation
      expect(result).to match(/\n/)
    end

    it 'formats nested structures with indentation' do
      data = {
        'user' => {
          'id' => 1,
          'name' => 'Alice'
        }
      }
      result = described_class.pretty_dump(data)

      expect(result).to include("\n")
      expect(result).to include('"user"')
      expect(result).to include('"id"')
      expect(result).to include('"name"')
    end

    it 'handles arrays with pretty formatting' do
      data = { 'items' => [1, 2, 3] }
      result = described_class.pretty_dump(data)

      expect(result).to include("\n")
      expect(result).to include('"items"')
    end

    it 'handles empty structures' do
      expect(described_class.pretty_dump({})).to include("{")
      expect(described_class.pretty_dump([])).to include("[")
    end
  end

  describe '.parse' do
    it 'parses JSON string to hash' do
      json = '{"user":"Alice","count":42}'
      result = described_class.parse(json)

      expect(result).to be_a(Hash)
      expect(result['user']).to eq('Alice')
      expect(result['count']).to eq(42)
    end

    it 'parses JSON arrays' do
      json = '[1,2,3]'
      result = described_class.parse(json)

      expect(result).to eq([1, 2, 3])
    end

    it 'parses nested structures' do
      json = '{"user":{"id":1,"name":"Alice"},"items":[{"id":1,"name":"Widget"}]}'
      result = described_class.parse(json)

      expect(result['user']).to be_a(Hash)
      expect(result['user']['id']).to eq(1)
      expect(result['user']['name']).to eq('Alice')
      expect(result['items']).to be_a(Array)
      expect(result['items'][0]['name']).to eq('Widget')
    end

    it 'returns hashes with string keys (not symbols)' do
      json = '{"user":"Alice","count":42}'
      result = described_class.parse(json)

      expect(result.keys).to all(be_a(String))
      expect(result.keys).not_to include(:user)
      expect(result.keys).to include('user')
    end

    it 'raises error for malformed JSON' do
      expect {
        described_class.parse('invalid json')
      }.to raise_error(JSON::ParserError)
    end
  end

  describe '.backend' do
    it 'returns the active backend' do
      backend = described_class.backend

      expect(backend).to be_a(Symbol)
      expect([:oj, :json]).to include(backend)
    end

    it 'returns consistent backend across calls' do
      backend1 = described_class.backend
      backend2 = described_class.backend

      expect(backend1).to eq(backend2)
    end
  end

  describe 'round-trip serialization' do
    it 'preserves data through dump and parse' do
      original = {
        'user' => 'Alice',
        'count' => 42,
        'active' => true,
        'metadata' => {
          'theme' => 'dark',
          'locale' => 'en'
        },
        'items' => [1, 2, 3]
      }

      json = described_class.dump(original)
      result = described_class.parse(json)

      expect(result).to eq(original)
    end

    it 'handles empty structures' do
      empty_hash = {}
      empty_array = []

      expect(described_class.parse(described_class.dump(empty_hash))).to eq(empty_hash)
      expect(described_class.parse(described_class.dump(empty_array))).to eq(empty_array)
    end

    it 'handles special characters and unicode' do
      data = {
        'text' => 'Hello "world" with \'quotes\'',
        'unicode' => '🐳 Two Whales Kissing',
        'escaped' => "Line 1\nLine 2\tTabbed"
      }

      json = described_class.dump(data)
      result = described_class.parse(json)

      expect(result['text']).to eq(data['text'])
      expect(result['unicode']).to eq(data['unicode'])
      expect(result['escaped']).to eq(data['escaped'])
    end
  end

  describe 'backend consistency' do
    it 'uses the same backend for dump and parse' do
      # Both operations should use the same underlying implementation
      data = { 'test' => 'value' }
      json = described_class.dump(data)
      result = described_class.parse(json)

      expect(result).to eq(data)
    end
  end

  describe '.reset!' do
    it 'reconfigures the backend' do
      original_backend = described_class.backend

      described_class.reset!

      expect(described_class.backend).to eq(original_backend)
    end

    it 'preserves functionality after reset' do
      data = { 'user' => 'Alice' }

      described_class.reset!

      json = described_class.dump(data)
      result = described_class.parse(json)

      expect(result).to eq(data)
    end
  end
end
