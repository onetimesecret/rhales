# spec/rhales/hydrator_spec.rb

require 'spec_helper'

RSpec.describe Rhales::Hydrator do
  let(:props) { { title: 'Test Page', count: 42, active: true } }
  let(:context) { Rhales::Context.minimal(props: props) }

  describe '#process_data_section' do
    context 'with schema section' do
      it 'directly serializes props without interpolation' do
        # Create mock parser with schema section
        parser = double('parser')
        allow(parser).to receive(:schema_lang).and_return('js-zod')
        allow(parser).to receive(:section).with('data').and_return(nil)
        allow(parser).to receive(:window_attribute).and_return('appData')

        hydrator = described_class.new(parser, context)
        json_string = hydrator.process_data_section

        # Should be valid JSON
        data = JSON.parse(json_string)

        expect(data).to eq('title' => 'Test Page', 'count' => 42, 'active' => true)
      end

      it 'does not perform template interpolation for schema sections' do
        # Even if props contain strings that look like template variables,
        # they should not be interpolated
        special_props = { message: '{{user.name}}', count: 123 }
        special_context = Rhales::Context.minimal(props: special_props)

        parser = double('parser')
        allow(parser).to receive(:schema_lang).and_return('js-zod')
        allow(parser).to receive(:section).with('data').and_return(nil)
        allow(parser).to receive(:window_attribute).and_return('data')

        hydrator = described_class.new(parser, special_context)
        json_string = hydrator.process_data_section

        data = JSON.parse(json_string)

        # Template syntax should be preserved as-is (not interpolated)
        expect(data['message']).to eq('{{user.name}}')
      end

      it 'handles nested objects in props' do
        nested_props = {
          user: { id: 1, name: 'Alice', email: 'alice@example.com' },
          settings: { theme: 'dark', notifications: true }
        }
        nested_context = Rhales::Context.minimal(props: nested_props)

        parser = double('parser')
        allow(parser).to receive(:schema_lang).and_return('js-zod')
        allow(parser).to receive(:section).with('data').and_return(nil)
        allow(parser).to receive(:window_attribute).and_return('data')

        hydrator = described_class.new(parser, nested_context)
        json_string = hydrator.process_data_section

        data = JSON.parse(json_string)

        expect(data['user']).to eq('id' => 1, 'name' => 'Alice', 'email' => 'alice@example.com')
        expect(data['settings']).to eq('theme' => 'dark', 'notifications' => true)
      end

      it 'handles arrays in props' do
        array_props = {
          items: [
            { id: 1, name: 'Item 1' },
            { id: 2, name: 'Item 2' },
            { id: 3, name: 'Item 3' }
          ],
          tags: %w[ruby rails testing]
        }
        array_context = Rhales::Context.minimal(props: array_props)

        parser = double('parser')
        allow(parser).to receive(:schema_lang).and_return('js-zod')
        allow(parser).to receive(:section).with('data').and_return(nil)
        allow(parser).to receive(:window_attribute).and_return('data')

        hydrator = described_class.new(parser, array_context)
        json_string = hydrator.process_data_section

        data = JSON.parse(json_string)

        expect(data['items']).to be_an(Array)
        expect(data['items'].length).to eq(3)
        expect(data['tags']).to eq(%w[ruby rails testing])
      end
    end

    context 'with data section (deprecated)' do
      it 'performs template interpolation' do
        data_content = '{"title": "{{title}}", "count": {{count}}}'

        parser = double('parser')
        allow(parser).to receive(:schema_lang).and_return(nil)
        allow(parser).to receive(:section).with('data').and_return(data_content)
        allow(parser).to receive(:window_attribute).and_return('data')

        hydrator = described_class.new(parser, context)
        json_string = hydrator.process_data_section

        data = JSON.parse(json_string)

        expect(data).to eq('title' => 'Test Page', 'count' => 42)
      end

      it 'returns empty object when no data section exists' do
        parser = double('parser')
        allow(parser).to receive(:schema_lang).and_return(nil)
        allow(parser).to receive(:section).with('data').and_return(nil)
        allow(parser).to receive(:window_attribute).and_return('data')

        hydrator = described_class.new(parser, context)
        json_string = hydrator.process_data_section

        data = JSON.parse(json_string)

        expect(data).to eq({})
      end
    end
  end

  describe '#processed_data_hash' do
    context 'with schema section' do
      it 'returns props as hash' do
        parser = double('parser')
        allow(parser).to receive(:schema_lang).and_return('js-zod')
        allow(parser).to receive(:section).with('data').and_return(nil)
        allow(parser).to receive(:window_attribute).and_return('data')

        hydrator = described_class.new(parser, context)
        data_hash = hydrator.processed_data_hash

        expect(data_hash).to be_a(Hash)
        expect(data_hash).to eq('title' => 'Test Page', 'count' => 42, 'active' => true)
      end
    end

    context 'with data section' do
      it 'returns interpolated data as hash' do
        data_content = '{"message": "Hello {{title}}"}'

        parser = double('parser')
        allow(parser).to receive(:schema_lang).and_return(nil)
        allow(parser).to receive(:section).with('data').and_return(data_content)
        allow(parser).to receive(:window_attribute).and_return('data')

        hydrator = described_class.new(parser, context)
        data_hash = hydrator.processed_data_hash

        expect(data_hash).to eq('message' => 'Hello Test Page')
      end
    end
  end

  describe 'error handling' do
    context 'with invalid JSON in data section' do
      it 'raises JSONSerializationError' do
        invalid_data = '{"title": "{{title}}"'  # Missing closing brace

        parser = double('parser')
        allow(parser).to receive(:schema_lang).and_return(nil)
        allow(parser).to receive(:section).with('data').and_return(invalid_data)
        allow(parser).to receive(:window_attribute).and_return('data')

        hydrator = described_class.new(parser, context)

        expect { hydrator.process_data_section }.to raise_error(Rhales::Hydrator::JSONSerializationError)
      end
    end
  end
end
