# spec/rhales/hydration_data_aggregator_spec.rb

require 'spec_helper'

RSpec.describe Rhales::HydrationDataAggregator do
  let(:props) { { title: 'Test', count: 42, active: true } }
  let(:context) { Rhales::Context.minimal(client: props) }

  describe '#aggregate' do
    context 'with schema sections' do
      it 'directly serializes props without interpolation' do
        # Create mock schema template
        schema_node = double('schema_node', location: double(start_line: 1))

        template1 = double('template1')
        allow(template1).to receive(:schema_lang).and_return('js-zod')
        allow(template1).to receive(:schema_window).and_return('appData')
        allow(template1).to receive(:schema_merge_strategy).and_return(nil)
        allow(template1).to receive(:section).with('data').and_return(nil)
        allow(template1).to receive(:section_node).with('schema').and_return(schema_node)
        allow(template1).to receive(:file_path).and_return('templates/test.rue')

        # Create mock composition
        composition = double('composition')
        allow(composition).to receive(:each_document_in_render_order).and_yield('test', template1)

        aggregator = described_class.new(context)
        result = aggregator.aggregate(composition)

        expect(result).to have_key('appData')
        # Client data is stored in the aggregated data with string keys (from context.client)
        expect(result['appData']).to be_a(Hash)
        expect(result['appData']).to have_key('title')
        expect(result['appData']['title']).to eq('Test')
        expect(result['appData']['count']).to eq(42)
        expect(result['appData']['active']).to eq(true)
      end

      it 'uses default window attribute if not specified' do
        schema_node = double('schema_node', location: double(start_line: 1))

        template1 = double('template1')
        allow(template1).to receive(:schema_lang).and_return('js-zod')
        allow(template1).to receive(:schema_window).and_return(nil)  # Will default to 'data'
        allow(template1).to receive(:schema_merge_strategy).and_return(nil)
        allow(template1).to receive(:section).with('data').and_return(nil)
        allow(template1).to receive(:section_node).with('schema').and_return(schema_node)
        allow(template1).to receive(:file_path).and_return('templates/test.rue')

        composition = double('composition')
        allow(composition).to receive(:each_document_in_render_order).and_yield('test', template1)

        aggregator = described_class.new(context)
        result = aggregator.aggregate(composition)

        expect(result).to have_key('data')
        # Props are stored in the aggregated data with string keys
        expect(result['data']).to be_a(Hash)
        expect(result['data']['title']).to eq('Test')
        expect(result['data']['count']).to eq(42)
        expect(result['data']['active']).to eq(true)
      end

      it 'supports deep merge strategy for schema sections' do
        schema_node = double('schema_node', location: double(start_line: 1))

        # First template with some props
        template1 = double('template1')
        allow(template1).to receive(:schema_lang).and_return('js-zod')
        allow(template1).to receive(:schema_window).and_return('appData')
        allow(template1).to receive(:schema_merge_strategy).and_return(nil)
        allow(template1).to receive(:section).with('data').and_return(nil)
        allow(template1).to receive(:section_node).with('schema').and_return(schema_node)
        allow(template1).to receive(:file_path).and_return('templates/layout.rue')

        # Second template with merge strategy
        template2 = double('template2')
        allow(template2).to receive(:schema_lang).and_return('js-zod')
        allow(template2).to receive(:schema_window).and_return('appData')
        allow(template2).to receive(:schema_merge_strategy).and_return('deep')
        allow(template2).to receive(:section).with('data').and_return(nil)
        allow(template2).to receive(:section_node).with('schema').and_return(schema_node)
        allow(template2).to receive(:file_path).and_return('templates/page.rue')

        composition = double('composition')
        allow(composition).to receive(:each_document_in_render_order)
          .and_yield('layout', template1)
          .and_yield('page', template2)

        aggregator = described_class.new(context)
        result = aggregator.aggregate(composition)

        expect(result).to have_key('appData')
        # Both templates share same props, so result should still match
        expect(result['appData']).to be_a(Hash)
        expect(result['appData']['title']).to eq('Test')
        expect(result['appData']['count']).to eq(42)
        expect(result['appData']['active']).to eq(true)
      end
    end

    context 'with data sections' do
      it 'processes data sections correctly' do
        data_node = double('data_node', location: double(start_line: 1))

        template1 = double('template1')
        allow(template1).to receive(:schema_lang).and_return(nil)
        allow(template1).to receive(:section).with('data').and_return('{"user": "John"}')
        allow(template1).to receive(:window_attribute).and_return('data')
        allow(template1).to receive(:merge_strategy).and_return(nil)
        allow(template1).to receive(:section_node).with('data').and_return(data_node)
        allow(template1).to receive(:file_path).and_return('templates/old.rue')

        composition = double('composition')
        allow(composition).to receive(:each_document_in_render_order).and_yield('old', template1)

        aggregator = described_class.new(context)
        result = aggregator.aggregate(composition)

        expect(result).to have_key('data')
        expect(result['data']).to eq({ 'user' => 'John' })
      end
    end

    context 'when templates have different window attributes' do
      it 'merges data correctly' do
        # Create mock templates
        data_node = double('data_node', location: double(start_line: 1))

        template1 = double('template1')
        allow(template1).to receive(:schema_lang).and_return(nil)
        allow(template1).to receive(:section).with('data').and_return('{"user": "John", "csrf": "abc123"}')
        allow(template1).to receive(:window_attribute).and_return('data')
        allow(template1).to receive(:merge_strategy).and_return(nil)
        allow(template1).to receive(:section_node).with('data').and_return(data_node)
        allow(template1).to receive(:file_path).and_return('template1.rue')

        template2 = double('template2')
        allow(template2).to receive(:schema_lang).and_return(nil)
        allow(template2).to receive(:section).with('data').and_return('{"theme": "dark", "locale": "en"}')
        allow(template2).to receive(:window_attribute).and_return('config')
        allow(template2).to receive(:merge_strategy).and_return(nil)
        allow(template2).to receive(:section_node).with('data').and_return(data_node)
        allow(template2).to receive(:file_path).and_return('template2.rue')

        # Create mock composition
        composition = double('composition')
        allow(composition).to receive(:each_document_in_render_order).and_yield('template1', template1).and_yield('template2', template2)

        aggregator = described_class.new(context)
        result = aggregator.aggregate(composition)

        expect(result).to have_key('data')
        expect(result).to have_key('config')
        expect(result['data']).to include('user' => 'John', 'csrf' => 'abc123')
        expect(result['config']).to include('theme' => 'dark', 'locale' => 'en')
      end
    end

    context 'when templates have colliding window attributes' do
      it 'raises HydrationCollisionError' do
        # Create mock templates with same window attribute
        data_node = double('data_node', location: double(start_line: 1))

        template1 = double('template1')
        allow(template1).to receive(:schema_lang).and_return(nil)
        allow(template1).to receive(:section).with('data').and_return('{"user": "John"}')
        allow(template1).to receive(:window_attribute).and_return('data')
        allow(template1).to receive(:merge_strategy).and_return(nil)
        allow(template1).to receive(:section_node).with('data').and_return(data_node)
        allow(template1).to receive(:file_path).and_return('layouts/main.rue')

        template2 = double('template2')
        allow(template2).to receive(:schema_lang).and_return(nil)
        allow(template2).to receive(:section).with('data').and_return('{"email": "test@example.com"}')
        allow(template2).to receive(:window_attribute).and_return('data')
        allow(template2).to receive(:merge_strategy).and_return(nil)
        allow(template2).to receive(:section_node).with('data').and_return(data_node)
        allow(template2).to receive(:file_path).and_return('pages/home.rue')

        # Create mock composition
        composition = double('composition')
        allow(composition).to receive(:each_document_in_render_order).and_yield('template1', template1).and_yield('template2', template2)

        aggregator = described_class.new(context)

        expect { aggregator.aggregate(composition) }.to raise_error(Rhales::HydrationCollisionError) do |error|
          expect(error.window_attribute).to eq('data')
          expect(error.first_path).to include('layouts/main.rue')
          expect(error.conflict_path).to include('pages/home.rue')
        end
      end
    end

    context 'with merge strategies' do
      it 'performs deep merge when specified' do
        data_node = double('data_node', location: double(start_line: 1))

        template1 = double('template1')
        allow(template1).to receive(:schema_lang).and_return(nil)
        allow(template1).to receive(:section).with('data').and_return('{"user": {"name": "John", "id": 1}}')
        allow(template1).to receive(:window_attribute).and_return('data')
        allow(template1).to receive(:merge_strategy).and_return(nil)
        allow(template1).to receive(:section_node).with('data').and_return(data_node)
        allow(template1).to receive(:file_path).and_return('layouts/main.rue')

        template2 = double('template2')
        allow(template2).to receive(:schema_lang).and_return(nil)
        allow(template2).to receive(:section).with('data').and_return('{"user": {"email": "john@example.com"}}')
        allow(template2).to receive(:window_attribute).and_return('data')
        allow(template2).to receive(:merge_strategy).and_return('deep')
        allow(template2).to receive(:section_node).with('data').and_return(data_node)
        allow(template2).to receive(:file_path).and_return('pages/home.rue')

        # Create mock composition
        composition = double('composition')
        allow(composition).to receive(:each_document_in_render_order).and_yield('template1', template1).and_yield('template2', template2)

        aggregator = described_class.new(context)
        result = aggregator.aggregate(composition)

        expect(result['data']['user']).to eq({
          'name' => 'John',
          'id' => 1,
          'email' => 'john@example.com'
        })
      end
    end
  end
end
