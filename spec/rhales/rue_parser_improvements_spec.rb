# spec/rhales/rue_parser_improvements_spec.rb

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

    it 'handles multiple complex comments outside sections' do
      content = <<~RUE
        <!--
          Multi-line comment
          with lots of content
        -->
        <!-- Another comment -->
        <!-- Yet another -->
        <data>{"user": "john"}</data>
        <!-- Comment between sections -->
        <!--
          Another multi-line
          comment
        -->
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
  end

  describe 'JSON object interpolation in data sections' do
    it 'supports Ruby Hash object interpolation' do
      context = Rhales::Context.minimal(props: {
        'onetime_window' => { 'csrf' => 'abc123', 'user' => { 'id' => 123, 'name' => 'Alice' } }
      })

      content = <<~RUE
        <data>{{{onetime_window}}}</data>
        <template>
          <h1>Hello World</h1>
        </template>
      RUE

      document = Rhales::RueDocument.new(content)
      document.parse!

      # Process the data section through the aggregator
      aggregator = Rhales::HydrationDataAggregator.new(context)
      processed_data = aggregator.send(:process_data_section, document.section('data'), document)

      expect(processed_data).to eq({
        'csrf' => 'abc123',
        'user' => { 'id' => 123, 'name' => 'Alice' }
      })
    end

    it 'supports Ruby Array object interpolation' do
      context = Rhales::Context.minimal(props: {
        'items' => [{ 'id' => 1, 'name' => 'Item 1' }, { 'id' => 2, 'name' => 'Item 2' }]
      })

      content = <<~RUE
        <data>{{{items}}}</data>
        <template>
          <h1>Items</h1>
        </template>
      RUE

      document = Rhales::RueDocument.new(content)
      document.parse!

      aggregator = Rhales::HydrationDataAggregator.new(context)
      processed_data = aggregator.send(:process_data_section, document.section('data'), document)

      expect(processed_data).to eq([
        { 'id' => 1, 'name' => 'Item 1' },
        { 'id' => 2, 'name' => 'Item 2' }
      ])
    end

    it 'maintains backward compatibility with string values' do
      context = Rhales::Context.minimal(props: {
        'simple_string' => 'hello world'
      })

      content = <<~RUE
        <data>"{{simple_string}}"</data>
        <template>
          <h1>Test</h1>
        </template>
      RUE

      document = Rhales::RueDocument.new(content)
      document.parse!

      aggregator = Rhales::HydrationDataAggregator.new(context)
      processed_data = aggregator.send(:process_data_section, document.section('data'), document)

      expect(processed_data).to eq('hello world')
    end
  end

  describe 'Unknown attribute warnings' do
    it 'warns about unknown data section attributes' do
      content = <<~RUE
        <data window="onetime" schema="@/types/window.d.ts" unknown="value">
        {"test": "data"}
        </data>
        <template>
          <h1>Test</h1>
        </template>
      RUE

      expect {
        document = Rhales::RueDocument.new(content, 'test_shared_context.rue')
        document.parse!
      }.to output(/Warning: data section encountered '(schema|unknown)' attribute - not yet supported, ignoring in test_shared_context.rue/).to_stderr
    end

    it 'does not warn about known attributes' do
      content = <<~RUE
        <data window="onetime" merge="deep" layout="main">
        {"test": "data"}
        </data>
        <template>
          <h1>Test</h1>
        </template>
      RUE

      expect {
        document = Rhales::RueDocument.new(content)
        document.parse!
      }.not_to output(/Warning: data section encountered '.+?' attribute - not yet supported, ignoring in /).to_stderr
    end
  end

  describe 'Flexible section requirements' do
    it 'allows data-only files' do
      content = <<~RUE
        <data window="onetime">
        {"csrf": "abc123", "user": "john"}
        </data>
      RUE

      document = Rhales::RueDocument.new(content)
      expect { document.parse! }.not_to raise_error
      expect(document.section('data')).to include('"csrf": "abc123"')
      expect(document.section('template')).to be_nil
    end

    it 'allows template-only files' do
      content = <<~RUE
        <template>
          <h1>Hello World</h1>
          <p>Template only content</p>
        </template>
      RUE

      document = Rhales::RueDocument.new(content)
      expect { document.parse! }.not_to raise_error
      expect(document.section('template')).to include('<h1>Hello World</h1>')
      expect(document.section('data')).to be_nil
    end

    it 'requires at least one of data or template' do
      content = <<~RUE
        <logic>
        # Just logic, no data or template
        </logic>
      RUE

      document = Rhales::RueDocument.new(content)
      expect { document.parse! }.to raise_error(Rhales::RueDocument::ParseError) do |error|
        expect(error.message).to include('Must have at least one of: schema, data, template')
      end
    end

    it 'rejects unknown sections' do
      content = <<~RUE
        <unknown>
        Content
        </unknown>
        <template>
          <h1>Test</h1>
        </template>
      RUE

      document = Rhales::RueDocument.new(content)
      expect { document.parse! }.to raise_error(Rhales::RueDocument::ParseError) do |error|
        expect(error.message).to include('Unknown sections: unknown')
      end
    end
  end
end
