# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Hydrator Merge Strategies' do
  let(:context) { Rhales::Context.minimal }

  before do
    Rhales::HydrationRegistry.clear!
  end

  after do
    Rhales::HydrationRegistry.clear!
  end

  describe 'shallow merge strategy' do
    context 'when there are no conflicting keys' do
      let(:layout_content) do
        <<~RUE
          <data window="appData">
          {
            "user": "John",
            "csrf": "abc123"
          }
          </data>
          <template>
          <div class="layout">{{> content}}</div>
          </template>
        RUE
      end

      let(:page_content) do
        <<~RUE
          <data window="appData" merge="shallow">
          {
            "page": "home",
            "features": ["feature1", "feature2"]
          }
          </data>
          <template>
          <h1>Welcome</h1>
          </template>
        RUE
      end

      it 'generates merge JavaScript for the second template' do
        # First template (no merge strategy)
        layout_parser = Rhales::RueDocument.new(layout_content, 'layouts/main.rue')
        layout_parser.parse!

        layout_hydrator = Rhales::Hydrator.new(layout_parser, context)
        layout_html = layout_hydrator.generate_hydration_html

        expect(layout_html).to include('window.appData = JSON.parse(')
        expect(layout_html).not_to include('shallow_merge')

        # Second template (with merge strategy)
        page_parser = Rhales::RueDocument.new(page_content, 'pages/home.rue')
        page_parser.parse!

        page_hydrator = Rhales::Hydrator.new(page_parser, context)
        page_html = page_hydrator.generate_hydration_html

        expect(page_html).to include('function shallow_merge(')
        expect(page_html).to include('window.appData = shallow_merge(window.appData || {}, newData);')
        expect(page_html).to include('"page": "home"')
        expect(page_html).to include('"features": ["feature1", "feature2"]')
      end
    end

    context 'when there are conflicting keys' do
      let(:layout_content) do
        <<~RUE
          <data window="appData">
          {"shared": "layout_value"}
          </data>
          <template>
          <div>Layout</div>
          </template>
        RUE
      end

      let(:page_content) do
        <<~RUE
          <data window="appData" merge="shallow">
          {"shared": "page_value"}
          </data>
          <template>
          <div>Page</div>
          </template>
        RUE
      end

      it 'generates JavaScript that will throw error on conflict' do
        # Register first template
        layout_parser = Rhales::RueDocument.new(layout_content, 'layouts/main.rue')
        layout_parser.parse!
        layout_hydrator = Rhales::Hydrator.new(layout_parser, context)
        layout_hydrator.generate_hydration_html

        # Generate second template with merge strategy
        page_parser = Rhales::RueDocument.new(page_content, 'pages/home.rue')
        page_parser.parse!
        page_hydrator = Rhales::Hydrator.new(page_parser, context)
        page_html = page_hydrator.generate_hydration_html

        expect(page_html).to include('throw new Error(\'Shallow merge conflict: key')
      end
    end
  end

  describe 'deep merge strategy' do
    let(:layout_content) do
      <<~RUE
        <data window="appData">
        {
          "user": {"name": "John", "role": "admin"},
          "config": {"theme": "dark"}
        }
        </data>
        <template>
        <div>Layout</div>
        </template>
      RUE
    end

    let(:page_content) do
      <<~RUE
        <data window="appData" merge="deep">
        {
          "user": {"email": "john@example.com"},
          "page": {"title": "Home"}
        }
        </data>
        <template>
        <div>Page</div>
        </template>
      RUE
    end

    it 'generates deep merge JavaScript' do
      # First template
      layout_parser = Rhales::RueDocument.new(layout_content, 'layouts/main.rue')
      layout_parser.parse!
      layout_hydrator = Rhales::Hydrator.new(layout_parser, context)
      layout_hydrator.generate_hydration_html

      # Second template with deep merge
      page_parser = Rhales::RueDocument.new(page_content, 'pages/home.rue')
      page_parser.parse!
      page_hydrator = Rhales::Hydrator.new(page_parser, context)
      page_html = page_hydrator.generate_hydration_html

      expect(page_html).to include('function deep_merge(')
      expect(page_html).to include('window.appData = deep_merge(window.appData || {}, newData);')
      expect(page_html).to include('result[key] = deep_merge(target[key], source[key]);')
      expect(page_html).to include('result[key] = source[key]; // Last wins')
    end
  end

  describe 'strict merge strategy' do
    let(:layout_content) do
      <<~RUE
        <data window="appData">
        {
          "user": {"name": "John"},
          "csrf": "abc123"
        }
        </data>
        <template>
        <div>Layout</div>
        </template>
      RUE
    end

    let(:page_content) do
      <<~RUE
        <data window="appData" merge="strict">
        {
          "user": {"email": "john@example.com"},
          "page": {"title": "Home"}
        }
        </data>
        <template>
        <div>Page</div>
        </template>
      RUE
    end

    it 'generates strict merge JavaScript' do
      # First template
      layout_parser = Rhales::RueDocument.new(layout_content, 'layouts/main.rue')
      layout_parser.parse!
      layout_hydrator = Rhales::Hydrator.new(layout_parser, context)
      layout_hydrator.generate_hydration_html

      # Second template with strict merge
      page_parser = Rhales::RueDocument.new(page_content, 'pages/home.rue')
      page_parser.parse!
      page_hydrator = Rhales::Hydrator.new(page_parser, context)
      page_html = page_hydrator.generate_hydration_html

      expect(page_html).to include('function strict_merge(')
      expect(page_html).to include('window.appData = strict_merge(window.appData || {}, newData);')
      expect(page_html).to include('throw new Error(\'Strict merge conflict: key')
    end
  end

  describe 'merge strategy extraction' do
    it 'correctly extracts merge strategy from RueDocument' do
      content_with_merge = <<~RUE
        <data window="testData" merge="deep">
        {"test": "value"}
        </data>
        <template>
        <div>Test</div>
        </template>
      RUE

      parser = Rhales::RueDocument.new(content_with_merge)
      parser.parse!

      expect(parser.merge_strategy).to eq('deep')
      expect(parser.window_attribute).to eq('testData')
    end

    it 'returns nil when no merge strategy is specified' do
      content_without_merge = <<~RUE
        <data window="testData">
        {"test": "value"}
        </data>
        <template>
        <div>Test</div>
        </template>
      RUE

      parser = Rhales::RueDocument.new(content_without_merge)
      parser.parse!

      expect(parser.merge_strategy).to be_nil
      expect(parser.window_attribute).to eq('testData')
    end
  end

  describe 'merge strategy validation' do
    %w[shallow deep strict].each do |strategy|
      it "accepts #{strategy} as a valid merge strategy" do
        content = <<~RUE
          <data window="appData" merge="#{strategy}">
          {"test": "value"}
          </data>
          <template>
          <div>Test</div>
          </template>
        RUE

        parser = Rhales::RueDocument.new(content, 'test.rue')
        parser.parse!

        expect do
          hydrator = Rhales::Hydrator.new(parser, context)
          html = hydrator.generate_hydration_html
          expect(html).to include("function #{strategy}_merge(")
        end.not_to raise_error
      end
    end
  end
end
