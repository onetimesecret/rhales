# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Hydrator Collision Detection Integration' do
  let(:context) { Rhales::Context.minimal }

  before do
    Rhales::HydrationRegistry.clear!
  end

  after do
    Rhales::HydrationRegistry.clear!
  end

  describe 'window attribute collision detection' do
    context 'when two templates use the same window attribute' do
      let(:layout_content) do
        <<~RUE
          <data window="data">
          {
            "user": "John",
            "csrf": "abc123"
          }
          </data>
          <template>
          <div class="layout">
            {{> content}}
          </div>
          </template>
        RUE
      end

      let(:page_content) do
        <<~RUE
          <data window="data">
          {
            "features": ["feature1", "feature2"],
            "demo": {
              "email": "demo@example.com"
            }
          }
          </data>
          <template>
          <h1>Welcome</h1>
          </template>
        RUE
      end

      it 'raises HydrationCollisionError with helpful message' do
        # First template registers successfully
        layout_parser = Rhales::Parser.new(layout_content, 'layouts/main.rue')
        layout_parser.parse!

        layout_hydrator = Rhales::Hydrator.new(layout_parser, context)
        expect { layout_hydrator.generate_hydration_html }.not_to raise_error

        # Second template with same window attribute should raise error
        page_parser = Rhales::Parser.new(page_content, 'home.rue')
        page_parser.parse!

        page_hydrator = Rhales::Hydrator.new(page_parser, context)

        expect do
          page_hydrator.generate_hydration_html
        end.to raise_error(Rhales::HydrationCollisionError) do |error|
          expect(error.message).to include("Window attribute collision detected")
          expect(error.message).to include("Attribute: 'data'")
          expect(error.message).to include("First defined: layouts/main.rue:1")
          expect(error.message).to include("Conflict with: home.rue:1")
          expect(error.message).to include('1. Rename one: <data window="homeData">')
          expect(error.message).to include('2. Enable merging: <data window="data" merge="deep">')
        end
      end
    end

    context 'when templates use different window attributes' do
      let(:layout_content) do
        <<~RUE
          <data window="layoutData">
          {
            "user": "John",
            "csrf": "abc123"
          }
          </data>
          <template>
          <div class="layout">
            {{> content}}
          </div>
          </template>
        RUE
      end

      let(:page_content) do
        <<~RUE
          <data window="pageData">
          {
            "features": ["feature1", "feature2"]
          }
          </data>
          <template>
          <h1>Welcome</h1>
          </template>
        RUE
      end

      it 'renders both without collision' do
        # First template
        layout_parser = Rhales::Parser.new(layout_content, 'layouts/main.rue')
        layout_parser.parse!

        layout_hydrator = Rhales::Hydrator.new(layout_parser, context)
        layout_html = layout_hydrator.generate_hydration_html

        expect(layout_html).to include('window.layoutData')
        expect(layout_html).not_to include('window.pageData')

        # Second template
        page_parser = Rhales::Parser.new(page_content, 'home.rue')
        page_parser.parse!

        page_hydrator = Rhales::Hydrator.new(page_parser, context)
        page_html = page_hydrator.generate_hydration_html

        expect(page_html).to include('window.pageData')
        expect(page_html).not_to include('window.layoutData')
      end
    end

    context 'when using View#render' do
      it 'clears registry between renders' do
        # Create test templates
        template1_path = File.join(Rhales.configuration.template_paths.first, 'test1.rue')
        template2_path = File.join(Rhales.configuration.template_paths.first, 'test2.rue')

        File.write(template1_path, <<~RUE)
          <data window="appData">
          {"page": "test1"}
          </data>
          <template>
          <h1>Test 1</h1>
          </template>
        RUE

        File.write(template2_path, <<~RUE)
          <data window="appData">
          {"page": "test2"}
          </data>
          <template>
          <h1>Test 2</h1>
          </template>
        RUE

        begin
          view = Rhales::View.new(nil) # nil request

          # First render should work
          html1 = view.render('test1')
          expect(html1).to include('window.appData')
          expect(html1).to include('"page": "test1"')

          # Second render should also work (registry cleared)
          html2 = view.render('test2')
          expect(html2).to include('window.appData')
          expect(html2).to include('"page": "test2"')

        ensure
          File.delete(template1_path) if File.exist?(template1_path)
          File.delete(template2_path) if File.exist?(template2_path)
        end
      end
    end

    # Note: Partial collision detection would require additional implementation
    # to handle template composition. For now, collision detection works
    # within single template rendering.

    context 'error message quality' do
      it 'includes actual data tag content when available' do
        content_with_tag = <<~RUE
          <data window="userData" schema="/schemas/user.json">
          {"name": "John"}
          </data>
          <template>
          <h1>User: {{name}}</h1>
          </template>
        RUE

        # First registration
        parser1 = Rhales::Parser.new(content_with_tag, 'components/user.rue')
        parser1.parse!
        hydrator1 = Rhales::Hydrator.new(parser1, context)
        hydrator1.generate_hydration_html

        # Second registration should show collision
        parser2 = Rhales::Parser.new(content_with_tag, 'pages/profile.rue')
        parser2.parse!
        hydrator2 = Rhales::Hydrator.new(parser2, context)

        expect do
          hydrator2.generate_hydration_html
        end.to raise_error(Rhales::HydrationCollisionError) do |error|
          expect(error.message).to include('components/user.rue:1')
          expect(error.message).to include('pages/profile.rue:1')
        end
      end
    end
  end
end
