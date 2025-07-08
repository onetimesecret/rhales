# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Rue Parser Improvements' do
  let(:context) { Rhales::Context.minimal }

  describe 'Empty data section handling' do
    it 'handles empty <data></data> sections' do
      content = <<~RUE
        <data></data>
        <template>
          <h1>Hello World</h1>
        </template>
      RUE

      document = Rhales::RueDocument.new(content)
      expect { document.parse! }.not_to raise_error
      expect(document.section('data')).to eq('')
    end

    it 'handles missing <data> section' do
      content = <<~RUE
        <template>
          <h1>Hello World</h1>
        </template>
      RUE

      document = Rhales::RueDocument.new(content)
      expect { document.parse! }.not_to raise_error
      expect(document.section('data')).to be_nil
    end

    it 'handles <data>{}</data> sections' do
      content = <<~RUE
        <data>{}</data>
        <template>
          <h1>Hello World</h1>
        </template>
      RUE

      document = Rhales::RueDocument.new(content)
      expect { document.parse! }.not_to raise_error
      expect(document.section('data')).to eq('{}')
    end
  end

  describe 'Empty JSON object hydration' do
    it 'does not raise collision error for empty JSON objects' do
      template1 = double('template1')
      allow(template1).to receive(:section).with('data').and_return('{}')
      allow(template1).to receive(:window_attribute).and_return('data')
      allow(template1).to receive(:merge_strategy).and_return(nil)
      allow(template1).to receive(:section_node).with('data').and_return(
        double('data_node', location: double(start_line: 1))
      )
      allow(template1).to receive(:file_path).and_return('template1.rue')

      template2 = double('template2')
      allow(template2).to receive(:section).with('data').and_return('{}')
      allow(template2).to receive(:window_attribute).and_return('data')
      allow(template2).to receive(:merge_strategy).and_return(nil)
      allow(template2).to receive(:section_node).with('data').and_return(
        double('data_node', location: double(start_line: 1))
      )
      allow(template2).to receive(:file_path).and_return('template2.rue')

      composition = double('composition')
      allow(composition).to receive(:each_document_in_render_order)
        .and_yield('template1', template1)
        .and_yield('template2', template2)

      aggregator = Rhales::HydrationDataAggregator.new(context)
      expect { aggregator.aggregate(composition) }.not_to raise_error
    end
  end

  describe 'JSON object dumping in data sections' do
    it 'supports direct JSON object interpolation' do
      require 'json'
      context = Rhales::Context.minimal(props: {
        'onetimeWindow' => { 'csrf' => 'abc123', 'user' => 'john' }.to_json
      })

      content = <<~RUE
        <data>{{{onetimeWindow}}}</data>
        <template>
          <h1>Hello World</h1>
        </template>
      RUE

      document = Rhales::RueDocument.new(content)
      document.parse!

      # Process the data section through the aggregator
      aggregator = Rhales::HydrationDataAggregator.new(context)
      processed_data = aggregator.send(:process_data_section, document.section('data'), document)

      expect(processed_data).to eq({ 'csrf' => 'abc123', 'user' => 'john' })
    end
  end

  describe 'JSON parsing flexibility' do
    it 'handles JSON with extra whitespace' do
      content = <<~RUE
        <data>
        {
          "user": "john",
          "csrf": "abc123"
        }
        </data>
        <template>
          <h1>Hello World</h1>
        </template>
      RUE

      document = Rhales::RueDocument.new(content)
      expect { document.parse! }.not_to raise_error
      expect(document.section('data')).to include('"user": "john"')
    end

    it 'handles JSON arrays' do
      content = <<~RUE
        <data>[{"name": "item1"}, {"name": "item2"}]</data>
        <template>
          <h1>Hello World</h1>
        </template>
      RUE

      document = Rhales::RueDocument.new(content)
      expect { document.parse! }.not_to raise_error

      aggregator = Rhales::HydrationDataAggregator.new(context)
      processed_data = aggregator.send(:process_data_section, document.section('data'), document)

      expect(processed_data).to eq([{"name" => "item1"}, {"name" => "item2"}])
    end
  end

  describe 'XML/HTML comment handling' do
    it 'ignores comments outside of sections' do
      content = <<~RUE
        <!-- This is a comment -->
        <data>{"user": "john"}</data>
        <!-- Another comment -->
        <template>
          <h1>Hello World</h1>
        </template>
        <!-- Final comment -->
      RUE

      document = Rhales::RueDocument.new(content)
      expect { document.parse! }.not_to raise_error
      expect(document.section('data')).to eq('{"user": "john"}')
      expect(document.section('template')).to include('<h1>Hello World</h1>')
    end

    it 'preserves comments within template sections' do
      content = <<~RUE
        <data>{"user": "john"}</data>
        <template>
          <!-- This comment should be preserved -->
          <h1>Hello World</h1>
        </template>
      RUE

      document = Rhales::RueDocument.new(content)
      expect { document.parse! }.not_to raise_error
      expect(document.section('template')).to include('<!-- This comment should be preserved -->')
    end
  end
end
