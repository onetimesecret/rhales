# frozen_string_literal: true

require 'spec_helper'
require 'rhales/view'
require 'rhales/middleware/schema_validator'
require 'rack/mock'

RSpec.describe 'Schema Validation Integration', type: :integration do
  let(:test_fixtures_dir) { File.join(__dir__, '../../fixtures/integration_test') }
  let(:templates_dir) { File.join(test_fixtures_dir, 'templates') }
  let(:schemas_dir) { File.join(test_fixtures_dir, 'schemas') }

  # Helper to create fresh mock request for each test
  def fresh_mock_request
    env = {
      'REQUEST_METHOD' => 'GET',
      'PATH_INFO' => '/test',
      'SCRIPT_NAME' => '',
      'rack.input' => StringIO.new,
      'rack.url_scheme' => 'http',
      'SERVER_NAME' => 'localhost',
      'SERVER_PORT' => '9292'
    }
    Rack::Request.new(env)
  end

  # Mock request object for View (lazily created per test)
  let(:mock_request) { fresh_mock_request }

  before do
    # Ensure directories exist
    FileUtils.mkdir_p(templates_dir)
    FileUtils.mkdir_p(schemas_dir)
  end

  let(:config) do
    Rhales::Configuration.new.tap do |c|
      c.template_paths = [templates_dir]
      c.enable_schema_validation = true
      c.fail_on_validation_error = fail_on_error
      c.schemas_dir = schemas_dir
      c.hydration.reflection_enabled = true
    end
  end

  after do
    # Clean up test fixtures
    FileUtils.rm_rf(test_fixtures_dir) if File.exist?(test_fixtures_dir)
  end

  describe 'End-to-end validation pipeline' do
    context 'with valid template and matching data' do
      let(:fail_on_error) { true }

      before do
        # Create template with schema section
        template_content = <<~RUE
          <template>
            <div>User: {{userName}}</div>
          </template>

          <data window="appState">
          {
            "userName": "{{userName}}",
            "isAuthenticated": true
          }
          </data>
        RUE

        File.write(File.join(templates_dir, 'valid_template.rue'), template_content)

        # Create matching schema
        schema = {
          '$schema' => 'https://json-schema.org/draft/2020-12/schema',
          'type' => 'object',
          'properties' => {
            'userName' => { 'type' => 'string' },
            'isAuthenticated' => { 'type' => 'boolean' }
          },
          'required' => ['userName', 'isAuthenticated'],
          'additionalProperties' => false
        }

        File.write(File.join(schemas_dir, 'valid_template.json'), JSON.generate(schema))
      end

      it 'renders successfully and passes validation' do
        # Create Rack app with middleware
        app = lambda do |env|
          view = Rhales::View.new(mock_request, nil, nil, 'en', props: { userName: 'Alice' }, config: config)
          html = view.render('valid_template')
          [200, { 'Content-Type' => 'text/html' }, [html]]
        end

        validator = Rhales::Middleware::SchemaValidator.new(app,
          schemas_dir: schemas_dir,
          fail_on_error: true
        )

        # Simulate request
        env = mock_request.env
        status, headers, body = validator.call(env)

        expect(status).to eq(200)
        expect(headers['Content-Type']).to eq('text/html')

        html = body.first
        expect(html).to include('User: Alice')
        expect(html).to include('"userName":"Alice"')
        expect(html).to include('"isAuthenticated":true')

        # Check validation stats
        expect(validator.stats[:total_validations]).to eq(1)
        expect(validator.stats[:failures]).to eq(0)
        expect(validator.stats[:success_rate]).to eq(100.0)
      end
    end

    context 'with invalid data in development mode' do
      let(:fail_on_error) { true }

      before do
        # Create template with schema
        template_content = <<~RUE
          <template>
            <div>Count: {{count}}</div>
          </template>

          <data window="appState">
          {
            "count": "{{count}}"
          }
          </data>
        RUE

        File.write(File.join(templates_dir, 'invalid_template.rue'), template_content)

        # Create schema expecting number
        schema = {
          '$schema' => 'https://json-schema.org/draft/2020-12/schema',
          'type' => 'object',
          'properties' => {
            'count' => { 'type' => 'number' }
          },
          'required' => ['count']
        }

        File.write(File.join(schemas_dir, 'invalid_template.json'), JSON.generate(schema))
      end

      it 'raises validation error with helpful message' do
        app = lambda do |env|
          view = Rhales::View.new(mock_request, nil, nil, 'en', props: { count: 'not-a-number' }, config: config)
          html = view.render('invalid_template')
          [200, { 'Content-Type' => 'text/html' }, [html]]
        end

        validator = Rhales::Middleware::SchemaValidator.new(app,
          schemas_dir: schemas_dir,
          fail_on_error: true
        )

        env = mock_request.env

        expect {
          validator.call(env)
        }.to raise_error(Rhales::Middleware::SchemaValidator::ValidationError) do |error|
          expect(error.message).to include('Schema validation failed')
          expect(error.message).to include('invalid_template')
          expect(error.message).to include('appState')
          expect(error.message).to include('did not match the following type: number')
        end
      end
    end

    context 'with invalid data in production mode' do
      let(:fail_on_error) { false }

      before do
        # Same template as above
        template_content = <<~RUE
          <template>
            <div>Count: {{count}}</div>
          </template>

          <data window="appState">
          {
            "count": "{{count}}"
          }
          </data>
        RUE

        File.write(File.join(templates_dir, 'prod_template.rue'), template_content)

        schema = {
          '$schema' => 'https://json-schema.org/draft/2020-12/schema',
          'type' => 'object',
          'properties' => {
            'count' => { 'type' => 'number' }
          }
        }

        File.write(File.join(schemas_dir, 'prod_template.json'), JSON.generate(schema))
      end

      it 'logs warning but continues serving in production' do
        app = lambda do |env|
          view = Rhales::View.new(mock_request, nil, nil, 'en', props: { count: 'bad-value' }, config: config)
          html = view.render('prod_template')
          [200, { 'Content-Type' => 'text/html' }, [html]]
        end

        validator = Rhales::Middleware::SchemaValidator.new(app,
          schemas_dir: schemas_dir,
          fail_on_error: false
        )

        env = mock_request.env

        expect {
          status, headers, body = validator.call(env)
          expect(status).to eq(200) # Still serves page
          expect(body.first).to include('Count: bad-value')
        }.to output(/Schema validation failed/).to_stderr

        # Validation was attempted and failed
        expect(validator.stats[:failures]).to eq(1)
      end
    end

    context 'with multiple templates in sequence' do
      let(:fail_on_error) { true }

      before do
        # Template 1
        File.write(File.join(templates_dir, 'template1.rue'), <<~RUE)
          <template><div>{{message}}</div></template>
          <data window="data1">{"message": "{{message}}"}</data>
        RUE

        File.write(File.join(schemas_dir, 'template1.json'), JSON.generate({
          'type' => 'object',
          'properties' => { 'message' => { 'type' => 'string' } }
        }))

        # Template 2
        File.write(File.join(templates_dir, 'template2.rue'), <<~RUE)
          <template><div>{{count}}</div></template>
          <data window="data2">{"count": {{count}}}</data>
        RUE

        File.write(File.join(schemas_dir, 'template2.json'), JSON.generate({
          'type' => 'object',
          'properties' => { 'count' => { 'type' => 'number' } }
        }))
      end

      it 'validates each template independently' do
        app = lambda do |env|
          template_name = env['rhales.template_name'] || 'template1'
          props = template_name == 'template1' ? { message: 'Hello' } : { count: 42 }

          view = Rhales::View.new(mock_request, nil, nil, 'en', props: props, config: config)
          html = view.render(template_name)
          [200, { 'Content-Type' => 'text/html' }, [html]]
        end

        validator = Rhales::Middleware::SchemaValidator.new(app,
          schemas_dir: schemas_dir,
          fail_on_error: true
        )

        # Request template1
        env1 = mock_request.env.merge('rhales.template_name' => 'template1')
        status1, _, body1 = validator.call(env1)
        expect(status1).to eq(200)
        expect(body1.first).to include('Hello')

        # Request template2
        env2 = mock_request.env.merge('rhales.template_name' => 'template2')
        status2, _, body2 = validator.call(env2)
        expect(status2).to eq(200)
        expect(body2.first).to include('42')

        # Both validated successfully
        expect(validator.stats[:total_validations]).to eq(2)
        expect(validator.stats[:failures]).to eq(0)
      end
    end

    context 'performance characteristics' do
      let(:fail_on_error) { true }

      before do
        template_content = <<~RUE
          <template><div>{{value}}</div></template>
          <data window="perf">{"value": "{{value}}"}</data>
        RUE

        File.write(File.join(templates_dir, 'perf.rue'), template_content)

        schema = {
          'type' => 'object',
          'properties' => { 'value' => { 'type' => 'string' } }
        }

        File.write(File.join(schemas_dir, 'perf.json'), JSON.generate(schema))
      end

      it 'validates with < 5ms overhead on average' do
        app = lambda do |env|
          req = Rack::Request.new(env)
          view = Rhales::View.new(req, nil, nil, 'en', props: { value: 'test' }, config: config)
          html = view.render('perf')
          [200, { 'Content-Type' => 'text/html' }, [html]]
        end

        validator = Rhales::Middleware::SchemaValidator.new(app,
          schemas_dir: schemas_dir,
          fail_on_error: true
        )

        # Run multiple validations with fresh envs
        10.times do
          env = {
            'REQUEST_METHOD' => 'GET',
            'PATH_INFO' => '/test',
            'SCRIPT_NAME' => '',
            'rack.input' => StringIO.new,
            'rack.url_scheme' => 'http',
            'SERVER_NAME' => 'localhost',
            'SERVER_PORT' => '9292'
          }
          validator.call(env)
        end

        stats = validator.stats
        expect(stats[:avg_time_ms]).to be < 5.0
        expect(stats[:total_validations]).to eq(10)
        expect(stats[:success_rate]).to eq(100.0)
      end
    end
  end

  describe 'Schema caching behavior' do
    let(:fail_on_error) { true }

    before do
      File.write(File.join(templates_dir, 'cached.rue'), <<~RUE)
        <template><div>{{test}}</div></template>
        <data window="cache">{"test": true}</data>
      RUE

      schema = {
        'type' => 'object',
        'properties' => { 'test' => { 'type' => 'boolean' } }
      }

      File.write(File.join(schemas_dir, 'cached.json'), JSON.generate(schema))
    end

    it 'caches schemas across multiple requests for performance' do
      app = lambda do |env|
        req = Rack::Request.new(env)
        view = Rhales::View.new(req, nil, nil, 'en', props: { test: true }, config: config)
        html = view.render('cached')
        [200, { 'Content-Type' => 'text/html' }, [html]]
      end

      validator = Rhales::Middleware::SchemaValidator.new(app,
        schemas_dir: schemas_dir,
        fail_on_error: true
      )

      # First request loads schema from file
      env1 = {
        'REQUEST_METHOD' => 'GET',
        'PATH_INFO' => '/test',
        'SCRIPT_NAME' => '',
        'rack.input' => StringIO.new,
        'rack.url_scheme' => 'http',
        'SERVER_NAME' => 'localhost',
        'SERVER_PORT' => '9292'
      }
      validator.call(env1)

      # Modify schema file
      File.write(File.join(schemas_dir, 'cached.json'), JSON.generate({
        'type' => 'object',
        'properties' => { 'different' => { 'type' => 'string' } }
      }))

      # Second request uses cached schema (doesn't see file changes)
      env2 = {
        'REQUEST_METHOD' => 'GET',
        'PATH_INFO' => '/test',
        'SCRIPT_NAME' => '',
        'rack.input' => StringIO.new,
        'rack.url_scheme' => 'http',
        'SERVER_NAME' => 'localhost',
        'SERVER_PORT' => '9292'
      }
      expect { validator.call(env2) }.not_to raise_error

      expect(validator.stats[:total_validations]).to eq(2)
    end
  end
end
