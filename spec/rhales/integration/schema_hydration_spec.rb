# spec/rhales/integration/schema_hydration_spec.rb

require 'spec_helper'
require 'fileutils'

RSpec.describe 'Schema-based Hydration Integration' do
  let(:templates_dir) { File.join(__dir__, '../../fixtures/templates/schema_test') }

  before(:all) do
    # Create test template directory
    @templates_dir = File.join(__dir__, '../../fixtures/templates/schema_test')
    FileUtils.mkdir_p(@templates_dir)

    # Create a simple schema-based template
    File.write(File.join(@templates_dir, 'simple_schema.rue'), <<~RUE)
      <schema lang="js-zod" window="testData">
      const schema = z.object({
        title: z.string(),
        count: z.number(),
        active: z.boolean()
      });
      </schema>

      <template>
      <h1>{{title}}</h1>
      <p>Count: {{count}}</p>
      <p>Active: {{active}}</p>
      </template>
    RUE

    # Create a template with nested objects
    File.write(File.join(@templates_dir, 'nested_schema.rue'), <<~RUE)
      <schema lang="js-zod" window="appData">
      const schema = z.object({
        user: z.object({
          id: z.number(),
          name: z.string(),
          email: z.string()
        }),
        settings: z.object({
          theme: z.string(),
          notifications: z.boolean()
        })
      });
      </schema>

      <template>
      <div>
        <h2>User: {{user.name}}</h2>
        <p>Email: {{user.email}}</p>
        <p>Theme: {{settings.theme}}</p>
      </div>
      </template>
    RUE

    # Create a template with custom window attribute
    File.write(File.join(@templates_dir, 'custom_window.rue'), <<~RUE)
      <schema lang="js-zod" window="myCustomData">
      const schema = z.object({
        message: z.string()
      });
      </schema>

      <template>
      <p>{{message}}</p>
      </template>
    RUE

    # Create a deprecated data section template for comparison
    File.write(File.join(@templates_dir, 'legacy_data.rue'), <<~RUE)
      <data window="legacyData">
      {
        "title": "{{title}}",
        "interpolated": "Hello {{name}}"
      }
      </data>

      <template>
      <h1>{{title}}</h1>
      </template>
    RUE
  end

  after(:all) do
    # Clean up test templates
    FileUtils.rm_rf(@templates_dir) if @templates_dir && File.exist?(@templates_dir)
  end

  describe 'rendering with schema sections' do
    it 'renders template with schema hydration and direct props serialization' do
      config = Rhales::Configuration.new do |c|
        c.template_paths = [@templates_dir]
      end

      view = Rhales::View.new(
        nil, nil, nil, 'en',
        props: { title: 'Test Page', count: 42, active: true },
        config: config
      )

      html = view.render('simple_schema')

      # Check template rendering
      expect(html).to include('<h1>Test Page</h1>')
      expect(html).to include('Count: 42')
      expect(html).to include('Active: true')

      # Check hydration script exists
      expect(html).to include('<script id="rsfc-data-')
      expect(html).to include('type="application/json"')

      # Check that data is serialized correctly
      expect(html).to include('"title":"Test Page"')
      expect(html).to include('"count":42')
      expect(html).to include('"active":true')

      # Check window variable assignment
      expect(html).to include('window[\'testData\']')
    end

    it 'handles nested objects correctly' do
      config = Rhales::Configuration.new do |c|
        c.template_paths = [@templates_dir]
      end

      view = Rhales::View.new(
        nil, nil, nil, 'en',
        props: {
          user: { id: 1, name: 'Alice', email: 'alice@example.com' },
          settings: { theme: 'dark', notifications: true }
        },
        config: config
      )

      html = view.render('nested_schema')

      # Check template rendering with nested access
      expect(html).to include('User: Alice')
      expect(html).to include('Email: alice@example.com')
      expect(html).to include('Theme: dark')

      # Check nested object serialization
      expect(html).to include('"user":{"id":1,"name":"Alice","email":"alice@example.com"}')
      expect(html).to include('"settings":{"theme":"dark","notifications":true}')
    end

    it 'uses custom window attribute from schema section' do
      config = Rhales::Configuration.new do |c|
        c.template_paths = [@templates_dir]
      end

      view = Rhales::View.new(
        nil, nil, nil, 'en',
        props: { message: 'Hello from custom window' },
        config: config
      )

      html = view.render('custom_window')

      # Check custom window variable
      expect(html).to include('window[\'myCustomData\']')
      expect(html).not_to include('window[\'data\']')
    end

    it 'does not perform template interpolation on schema data' do
      config = Rhales::Configuration.new do |c|
        c.template_paths = [@templates_dir]
      end

      # Props contain strings that look like template variables
      view = Rhales::View.new(
        nil, nil, nil, 'en',
        props: { title: '{{should.not.interpolate}}', count: 99 },
        config: config
      )

      html = view.render('simple_schema')

      # Template syntax in props should NOT be interpolated in hydration data
      expect(html).to include('"title":"{{should.not.interpolate}}"')
    end
  end

  describe 'data_hash method with schema sections' do
    it 'returns props directly for schema sections' do
      config = Rhales::Configuration.new do |c|
        c.template_paths = [@templates_dir]
      end

      view = Rhales::View.new(
        nil, nil, nil, 'en',
        props: { title: 'Data Hash Test', count: 123, active: false },
        config: config
      )

      data = view.data_hash('simple_schema')

      expect(data).to have_key('testData')
      expect(data['testData']).to eq({
        title: 'Data Hash Test',
        count: 123,
        active: false
      })
    end
  end

  describe 'legacy data section behavior' do
    it 'still works with data sections and shows deprecation warning' do
      config = Rhales::Configuration.new do |c|
        c.template_paths = [@templates_dir]
      end

      view = Rhales::View.new(
        nil, nil, nil, 'en',
        props: { title: 'Legacy Test', name: 'World' },
        config: config
      )

      # Should show deprecation warning
      expect { view.render('legacy_data') }.to output(/DEPRECATION WARNING/).to_stderr
    end

    it 'performs template interpolation for data sections' do
      config = Rhales::Configuration.new do |c|
        c.template_paths = [@templates_dir]
      end

      view = Rhales::View.new(
        nil, nil, nil, 'en',
        props: { title: 'Interpolated Title', name: 'Bob' },
        config: config
      )

      # Suppress deprecation warning for this test
      allow($stderr).to receive(:write)

      data = view.data_hash('legacy_data')

      expect(data['legacyData']['title']).to eq('Interpolated Title')
      expect(data['legacyData']['interpolated']).to eq('Hello Bob')
    end
  end

  describe 'schema section priority over data section' do
    it 'uses schema section when both are present' do
      # Create a template with both sections (edge case)
      File.write(File.join(@templates_dir, 'both_sections.rue'), <<~RUE)
        <schema lang="js-zod" window="schemaData">
        const schema = z.object({
          value: z.string()
        });
        </schema>

        <data window="dataData">
        {
          "value": "{{value}}"
        }
        </data>

        <template>
        <p>{{value}}</p>
        </template>
      RUE

      config = Rhales::Configuration.new do |c|
        c.template_paths = [@templates_dir]
      end

      view = Rhales::View.new(
        nil, nil, nil, 'en',
        props: { value: 'test' },
        config: config
      )

      data = view.data_hash('both_sections')

      # Schema should take priority
      expect(data).to have_key('schemaData')
      expect(data).not_to have_key('dataData')
      expect(data['schemaData']['value']).to eq('test')
    end
  end
end
