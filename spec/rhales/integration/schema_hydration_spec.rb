# spec/rhales/integration/schema_hydration_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'

RSpec.describe 'Schema-based Hydration Integration' do
  let(:templates_dir) { File.join(__dir__, '../../fixtures/templates/schema_test') }

  describe 'rendering with schema sections' do
    it 'renders template with schema hydration and direct props serialization' do
      config = Rhales::Configuration.new do |c|
        c.template_paths = [templates_dir]
      end

      view = Rhales::View.new(nil,
        client: { title: 'Test Page', count: 42, active: true },
        config: config
      )

      html = view.render('simple_schema')

      # Check template rendering
      expect(html).to include('<h1>Test Page</h1>')
      expect(html).to include('Count: 42')
      expect(html).to include('Active: true')

      # Check hydration script exists
      expect(html).to match(/<script[^>]*\sid="rsfc-data-/)
      expect(html).to include('type="application/json"')

      # Check that data is serialized correctly
      expect(html).to include('"title":"Test Page"')
      expect(html).to include('"count":42')
      expect(html).to include('"active":true')

      # Check window variable assignment (uses dynamic targetName pattern)
      expect(html).to include('data-window="testData"')
      expect(html).to include('window[targetName] = JSON.parse(dataScript.textContent);')
    end

    it 'handles nested objects correctly' do
      config = Rhales::Configuration.new do |c|
        c.template_paths = [templates_dir]
      end

      view = Rhales::View.new(nil,
        client: {
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
        c.template_paths = [templates_dir]
      end

      view = Rhales::View.new(nil,
        client: { message: 'Hello from custom window' },
        config: config
      )

      html = view.render('custom_window')

      # Check custom window variable (uses dynamic targetName pattern)
      expect(html).to include('data-window="myCustomData"')
      expect(html).not_to include('data-window="data"')
    end

    it 'does not perform template interpolation on schema data' do
      config = Rhales::Configuration.new do |c|
        c.template_paths = [templates_dir]
      end

      # Props contain strings that look like template variables
      view = Rhales::View.new(nil,
        client: { title: '{{should.not.interpolate}}', count: 99 },
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
        c.template_paths = [templates_dir]
      end

      view = Rhales::View.new(nil,
        client: { title: 'Data Hash Test', count: 123, active: false },
        config: config
      )

      data = view.data_hash('simple_schema')

      expect(data).to have_key('testData')
      # JSON parsing returns string keys, not symbols
      expect(data['testData']).to eq({
        'title' => 'Data Hash Test',
        'count' => 123,
        'active' => false
      })
    end
  end

end
