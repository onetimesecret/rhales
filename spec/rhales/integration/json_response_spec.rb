# frozen_string_literal: true

require 'spec_helper'
require 'rhales/view'
require 'rhales/middleware/json_responder'
require 'fileutils'

RSpec.describe 'JSON Response Integration' do
  let(:template_path) { File.join(__dir__, '../../fixtures/templates') }
  let(:config) do
    Rhales::Configuration.new do |c|
      c.template_paths = [template_path]
      c.cache_templates = false
      c.enable_json_responder = true
      c.json_responder_include_metadata = false
    end
  end

  before do
    # Create test template with hydration data
    FileUtils.mkdir_p(template_path)
    File.write(File.join(template_path, 'json_test.rue'), <<~TEMPLATE)
      <template>
        <div id="app">
          <h1>{{title}}</h1>
          <p>User: {{user.name}}</p>
        </div>
      </template>

      <data window="appData">
        {
          "title": "{{title}}",
          "user": {{{user}}},
          "authenticated": {{authenticated}},
          "count": {{count}}
        }
      </data>
    TEMPLATE
  end

  after do
    # Clean up test template
    FileUtils.rm_f(File.join(template_path, 'json_test.rue'))
  end

  describe 'end-to-end JSON response flow' do
    it 'renders HTML with extractable hydration data' do
      view = Rhales::View.new(nil, 'en',
        props: {
          title: 'Dashboard',
          user: { id: 1, name: 'Alice', email: 'alice@example.com' },
          authenticated: true,
          count: 42
        },
        config: config
      )

      html = view.render('json_test')

      # Verify HTML contains hydration script
      expect(html).to include('<script')
      expect(html).to include('type="application/json"')
      expect(html).to include('data-window="appData"')
      expect(html).to include('"title":"Dashboard"')
      expect(html).to include('"authenticated":true')
      expect(html).to include('"count":42')
    end

    it 'middleware can extract and return JSON from rendered HTML' do
      # Simulate a Rack app that renders with Rhales
      app = lambda do |env|
        view = Rhales::View.new(nil, 'en',
          props: {
            title: 'Dashboard',
            user: { id: 1, name: 'Alice', email: 'alice@example.com' },
            authenticated: true,
            count: 42
          },
          config: config
        )

        html = view.render('json_test')
        [200, { 'content-type' => 'text/html' }, [html]]
      end

      # Wrap with JsonResponder middleware
      middleware = Rhales::Middleware::JsonResponder.new(app, enabled: true)

      # Make request with JSON Accept header
      env = { 'HTTP_ACCEPT' => 'application/json' }
      status, headers, body = middleware.call(env)

      # Verify JSON response
      expect(status).to eq(200)
      expect(headers['content-type']).to eq('application/json')

      json_data = JSON.parse(body.first)
      expect(json_data['title']).to eq('Dashboard')
      expect(json_data['user']['id']).to eq(1)
      expect(json_data['user']['name']).to eq('Alice')
      expect(json_data['authenticated']).to eq(true)
      expect(json_data['count']).to eq(42)
    end

    it 'returns HTML when Accept header is text/html' do
      app = lambda do |env|
        view = Rhales::View.new(nil, 'en',
          props: {
            title: 'Dashboard',
            user: { id: 1, name: 'Alice' },
            authenticated: true,
            count: 42
          },
          config: config
        )

        html = view.render('json_test')
        [200, { 'content-type' => 'text/html' }, [html]]
      end

      middleware = Rhales::Middleware::JsonResponder.new(app, enabled: true)

      # Request HTML
      env = { 'HTTP_ACCEPT' => 'text/html' }
      status, headers, body = middleware.call(env)

      # Verify HTML response
      expect(status).to eq(200)
      expect(headers['content-type']).to eq('text/html')
      expect(body.first).to include('<div id="app">')
      expect(body.first).to include('<h1>Dashboard</h1>')
    end
  end

  describe 'multiple hydration windows' do
    before do
      # Note: Multiple <data> sections not supported - use <schema> instead
      # This test demonstrates single-window behavior
      File.write(File.join(template_path, 'multi_window.rue'), <<~TEMPLATE)
        <template>
          <div id="app">Test</div>
        </template>

        <data window="appData">
          {
            "user": {{{user}}},
            "theme": "{{theme}}",
            "locale": "{{locale}}"
          }
        </data>
      TEMPLATE
    end

    after do
      FileUtils.rm_f(File.join(template_path, 'multi_window.rue'))
    end

    it 'returns flattened data for single window' do
      app = lambda do |env|
        view = Rhales::View.new(nil, 'en',
          props: {
            user: { id: 1, name: 'Bob' },
            theme: 'dark',
            locale: 'en'
          },
          config: config
        )

        html = view.render('multi_window')
        [200, { 'content-type' => 'text/html' }, [html]]
      end

      middleware = Rhales::Middleware::JsonResponder.new(app, enabled: true)

      env = { 'HTTP_ACCEPT' => 'application/json' }
      status, headers, body = middleware.call(env)

      json_data = JSON.parse(body.first)
      # Single window returns flattened data
      expect(json_data['user']['name']).to eq('Bob')
      expect(json_data['theme']).to eq('dark')
      expect(json_data['locale']).to eq('en')
    end
  end

  describe 'metadata mode' do
    it 'includes template name when metadata is enabled' do
      app = lambda do |env|
        view = Rhales::View.new(nil, 'en',
          props: {
            title: 'Test',
            user: { name: 'Charlie' },
            authenticated: false,
            count: 0
          },
          config: config
        )

        html = view.render('json_test')

        # Set template name in env (normally done by View)
        env['rhales.template_name'] = 'json_test'

        [200, { 'content-type' => 'text/html' }, [html]]
      end

      middleware = Rhales::Middleware::JsonResponder.new(app,
        enabled: true,
        include_metadata: true
      )

      env = { 'HTTP_ACCEPT' => 'application/json' }
      status, headers, body = middleware.call(env)

      json_data = JSON.parse(body.first)
      expect(json_data.keys).to contain_exactly('template', 'data')
      expect(json_data['template']).to eq('json_test')
      expect(json_data['data']['appData']['title']).to eq('Test')
    end
  end

  describe 'real-world scenarios' do
    it 'handles boolean and null values correctly' do
      File.write(File.join(template_path, 'edge_cases.rue'), <<~TEMPLATE)
        <template>
          <div>Edge cases</div>
        </template>

        <data window="testData">
          {
            "is_active": {{is_active}},
            "is_deleted": {{is_deleted}},
            "optional_field": null,
            "zero_value": {{zero_value}},
            "empty_string": "{{empty_string}}"
          }
        </data>
      TEMPLATE

      app = lambda do |env|
        view = Rhales::View.new(nil, 'en',
          props: {
            is_active: true,
            is_deleted: false,
            optional_field: nil,
            zero_value: 0,
            empty_string: ''
          },
          config: config
        )

        html = view.render('edge_cases')
        [200, { 'content-type' => 'text/html' }, [html]]
      end

      middleware = Rhales::Middleware::JsonResponder.new(app, enabled: true)

      env = { 'HTTP_ACCEPT' => 'application/json' }
      status, headers, body = middleware.call(env)

      json_data = JSON.parse(body.first)
      expect(json_data['is_active']).to eq(true)
      expect(json_data['is_deleted']).to eq(false)
      expect(json_data['optional_field']).to be_nil
      expect(json_data['zero_value']).to eq(0)
      expect(json_data['empty_string']).to eq('')

      FileUtils.rm_f(File.join(template_path, 'edge_cases.rue'))
    end

    it 'handles arrays and nested objects' do
      File.write(File.join(template_path, 'complex.rue'), <<~TEMPLATE)
        <template>
          <div>Complex data</div>
        </template>

        <data window="complexData">
          {
            "posts": {{{posts}}},
            "settings": {{{settings}}}
          }
        </data>
      TEMPLATE

      app = lambda do |env|
        view = Rhales::View.new(nil, 'en',
          props: {
            posts: [
              { id: 1, title: 'First', tags: ['ruby', 'rails'] },
              { id: 2, title: 'Second', tags: ['javascript'] }
            ],
            settings: {
              notifications: { email: true, sms: false },
              privacy: { public: false }
            }
          },
          config: config
        )

        html = view.render('complex')
        [200, { 'content-type' => 'text/html' }, [html]]
      end

      middleware = Rhales::Middleware::JsonResponder.new(app, enabled: true)

      env = { 'HTTP_ACCEPT' => 'application/json' }
      status, headers, body = middleware.call(env)

      json_data = JSON.parse(body.first)
      expect(json_data['posts'].size).to eq(2)
      expect(json_data['posts'][0]['tags']).to eq(['ruby', 'rails'])
      expect(json_data['settings']['notifications']['email']).to eq(true)
      expect(json_data['settings']['privacy']['public']).to eq(false)

      FileUtils.rm_f(File.join(template_path, 'complex.rue'))
    end
  end
end
