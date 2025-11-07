# spec/rhales/middleware/schema_validator_spec.rb

require 'spec_helper'
require 'rhales/middleware/schema_validator'
require 'json'
require 'fileutils'

RSpec.describe Rhales::Middleware::SchemaValidator do
  let(:app) { ->(env) { [200, { 'Content-Type' => 'text/html' }, [html_response]] } }
  let(:schemas_dir) { File.join(__dir__, '../../fixtures/schemas') }
  let(:html_response) { '<html><body>Test</body></html>' }

  subject(:middleware) do
    described_class.new(app,
      schemas_dir: schemas_dir,
      fail_on_error: fail_on_error,
      enabled: true
    )
  end

  let(:fail_on_error) { true }

  before do
    # Ensure fixtures directory exists
    FileUtils.mkdir_p(schemas_dir)
  end

  describe '#call' do
    context 'when validation is disabled' do
      subject(:middleware) do
        described_class.new(app,
          schemas_dir: schemas_dir,
          fail_on_error: true,
          enabled: false
        )
      end

      it 'passes through without validation' do
        env = { 'PATH_INFO' => '/login' }
        response = middleware.call(env)

        expect(response).to eq([200, { 'Content-Type' => 'text/html' }, [html_response]])
        expect(middleware.stats[:total_validations]).to eq(0)
      end
    end

    context 'when path should be skipped' do
      ['/assets/app.js', '/api/users', '/public/image.png', '/favicon.ico'].each do |path|
        it "skips validation for #{path}" do
          env = { 'PATH_INFO' => path }
          response = middleware.call(env)

          expect(response).to be_an(Array)
          expect(middleware.stats[:total_validations]).to eq(0)
        end
      end
    end

    context 'when custom skip paths are configured' do
      subject(:middleware) do
        described_class.new(app,
          schemas_dir: schemas_dir,
          fail_on_error: true,
          enabled: true,
          skip_paths: ['/health', '/metrics']
        )
      end

      it 'skips validation for custom paths' do
        env = { 'PATH_INFO' => '/health' }
        response = middleware.call(env)

        expect(response).to be_an(Array)
        expect(middleware.stats[:total_validations]).to eq(0)
      end
    end

    context 'when response is not HTML' do
      let(:app) { ->(env) { [200, { 'Content-Type' => 'application/json' }, ['{"data": []}']] } }

      it 'skips validation for non-HTML responses' do
        env = { 'PATH_INFO' => '/api/data', 'rhales.template_name' => 'test' }
        response = middleware.call(env)

        expect(response).to be_an(Array)
        expect(middleware.stats[:total_validations]).to eq(0)
      end
    end

    context 'when template name is not set' do
      it 'skips validation when no template name in env' do
        env = { 'PATH_INFO' => '/test' }
        response = middleware.call(env)

        expect(response).to be_an(Array)
        expect(middleware.stats[:total_validations]).to eq(0)
      end
    end

    context 'when schema file does not exist' do
      it 'skips validation and continues serving' do
        env = { 'PATH_INFO' => '/test', 'rhales.template_name' => 'nonexistent' }
        response = middleware.call(env)

        expect(response).to be_an(Array)
        expect(middleware.stats[:total_validations]).to eq(0)
      end
    end

    context 'when HTML has no hydration data' do
      let(:html_response) { '<html><body>No hydration here</body></html>' }

      before do
        # Create a valid schema file
        schema = {
          '$schema' => 'https://json-schema.org/draft/2020-12/schema',
          'type' => 'object',
          'properties' => { 'test' => { 'type' => 'string' } }
        }
        File.write(File.join(schemas_dir, 'test.json'), JSON.generate(schema))
      end

      it 'skips validation when no hydration blocks found' do
        env = { 'PATH_INFO' => '/test', 'rhales.template_name' => 'test' }
        response = middleware.call(env)

        expect(response).to be_an(Array)
        expect(middleware.stats[:total_validations]).to eq(0)
      end
    end

    context 'with valid hydration data' do
      let(:html_response) do
        <<~HTML
          <html>
          <body>
            <script id="data-1" type="application/json" data-window="testData">{"message":"hello","count":42}</script>
            <script>window['testData'] = JSON.parse(document.getElementById('data-1').textContent);</script>
          </body>
          </html>
        HTML
      end

      before do
        # Create matching schema
        schema = {
          '$schema' => 'https://json-schema.org/draft/2020-12/schema',
          'type' => 'object',
          'properties' => {
            'message' => { 'type' => 'string' },
            'count' => { 'type' => 'number' }
          },
          'required' => ['message', 'count']
        }
        File.write(File.join(schemas_dir, 'test.json'), JSON.generate(schema))
      end

      it 'validates successfully and returns response' do
        env = { 'PATH_INFO' => '/test', 'rhales.template_name' => 'test' }
        response = middleware.call(env)

        expect(response).to be_an(Array)
        expect(response[0]).to eq(200)
        expect(middleware.stats[:total_validations]).to eq(1)
        expect(middleware.stats[:failures]).to eq(0)
      end

      it 'tracks validation time' do
        env = { 'PATH_INFO' => '/test', 'rhales.template_name' => 'test' }
        middleware.call(env)

        stats = middleware.stats
        expect(stats[:avg_time_ms]).to be > 0
        expect(stats[:avg_time_ms]).to be < 100 # Should be fast
      end
    end

    context 'with invalid hydration data in development mode' do
      let(:fail_on_error) { true }
      let(:html_response) do
        <<~HTML
          <html>
          <body>
            <script id="data-1" type="application/json" data-window="testData">{"message":123,"missing":"field"}</script>
            <script>window['testData'] = JSON.parse(document.getElementById('data-1').textContent);</script>
          </body>
          </html>
        HTML
      end

      before do
        # Create schema requiring string message and count field
        schema = {
          '$schema' => 'https://json-schema.org/draft/2020-12/schema',
          'type' => 'object',
          'properties' => {
            'message' => { 'type' => 'string' },
            'count' => { 'type' => 'number' }
          },
          'required' => ['message', 'count'],
          'additionalProperties' => false
        }
        File.write(File.join(schemas_dir, 'test.json'), JSON.generate(schema))
      end

      it 'raises ValidationError with helpful message' do
        env = { 'PATH_INFO' => '/test', 'rhales.template_name' => 'test' }

        expect {
          middleware.call(env)
        }.to raise_error(Rhales::Middleware::SchemaValidator::ValidationError) do |error|
          expect(error.message).to include('Schema validation failed')
          expect(error.message).to include('template: test')
          expect(error.message).to include('Window variable: testData')
          expect(error.message).to include('To fix:')
        end
      end

      it 'tracks validation failures' do
        env = { 'PATH_INFO' => '/test', 'rhales.template_name' => 'test' }

        begin
          middleware.call(env)
        rescue Rhales::Middleware::SchemaValidator::ValidationError
          # Expected
        end

        expect(middleware.stats[:total_validations]).to eq(1)
        expect(middleware.stats[:failures]).to eq(1)
        expect(middleware.stats[:success_rate]).to eq(0)
      end
    end

    context 'with invalid hydration data in production mode' do
      let(:fail_on_error) { false }
      let(:html_response) do
        <<~HTML
          <html>
          <body>
            <script id="data-1" type="application/json" data-window="testData">{"wrong":"type"}</script>
            <script>window['testData'] = JSON.parse(document.getElementById('data-1').textContent);</script>
          </body>
          </html>
        HTML
      end

      before do
        schema = {
          '$schema' => 'https://json-schema.org/draft/2020-12/schema',
          'type' => 'object',
          'properties' => {
            'message' => { 'type' => 'string' }
          },
          'required' => ['message']
        }
        File.write(File.join(schemas_dir, 'test.json'), JSON.generate(schema))
      end

      it 'logs warning but continues serving' do
        env = { 'PATH_INFO' => '/test', 'rhales.template_name' => 'test' }

        expect {
          response = middleware.call(env)
          expect(response[0]).to eq(200) # Still returns 200
        }.to output(/Schema validation failed/).to_stderr
      end
    end

    context 'with multiple hydration blocks' do
      let(:html_response) do
        <<~HTML
          <html>
          <body>
            <script id="data-1" type="application/json" data-window="appData">{"user":"john"}</script>
            <script>window['appData'] = JSON.parse(document.getElementById('data-1').textContent);</script>
            <script id="data-2" type="application/json" data-window="configData">{"theme":"dark"}</script>
            <script>window['configData'] = JSON.parse(document.getElementById('data-2').textContent);</script>
          </body>
          </html>
        HTML
      end

      before do
        # Schema allows both blocks
        schema = {
          '$schema' => 'https://json-schema.org/draft/2020-12/schema',
          'type' => 'object',
          'properties' => {
            'user' => { 'type' => 'string' },
            'theme' => { 'type' => 'string' }
          }
        }
        File.write(File.join(schemas_dir, 'test.json'), JSON.generate(schema))
      end

      it 'validates all hydration blocks' do
        env = { 'PATH_INFO' => '/test', 'rhales.template_name' => 'test' }
        response = middleware.call(env)

        expect(response[0]).to eq(200)
        expect(middleware.stats[:total_validations]).to eq(1)
        expect(middleware.stats[:failures]).to eq(0)
      end
    end
  end

  describe '#stats' do
    let(:html_response) do
      <<~HTML
        <html>
        <body>
          <script id="data-1" type="application/json" data-window="test">{"valid":true}</script>
        </body>
        </html>
      HTML
    end

    before do
      schema = {
        '$schema' => 'https://json-schema.org/draft/2020-12/schema',
        'type' => 'object',
        'properties' => { 'valid' => { 'type' => 'boolean' } }
      }
      File.write(File.join(schemas_dir, 'test.json'), JSON.generate(schema))
    end

    it 'returns comprehensive statistics' do
      env = { 'PATH_INFO' => '/test', 'rhales.template_name' => 'test' }
      3.times { middleware.call(env) }

      stats = middleware.stats
      expect(stats[:total_validations]).to eq(3)
      expect(stats[:failures]).to eq(0)
      expect(stats[:avg_time_ms]).to be > 0
      expect(stats[:success_rate]).to eq(100.0)
    end

    it 'calculates success rate correctly' do
      # Create invalid HTML for second request
      allow(app).to receive(:call).and_return(
        [200, { 'Content-Type' => 'text/html' }, [html_response]],
        [200, { 'Content-Type' => 'text/html' }, ['<html><script type="application/json" data-window="test">{"valid":"wrong"}</script></html>']]
      )

      env = { 'PATH_INFO' => '/test', 'rhales.template_name' => 'test' }
      middleware.call(env)

      begin
        middleware.call(env)
      rescue Rhales::Middleware::SchemaValidator::ValidationError
        # Expected
      end

      stats = middleware.stats
      expect(stats[:total_validations]).to eq(2)
      expect(stats[:failures]).to eq(1)
      expect(stats[:success_rate]).to eq(50.0)
    end
  end

  describe 'schema caching' do
    let(:html_response) do
      '<html><body><script type="application/json" data-window="test">{"test":true}</script></body></html>'
    end

    before do
      schema = {
        '$schema' => 'https://json-schema.org/draft/2020-12/schema',
        'type' => 'object',
        'properties' => { 'test' => { 'type' => 'boolean' } }
      }
      File.write(File.join(schemas_dir, 'cached.json'), JSON.generate(schema))
    end

    it 'caches schemas across multiple requests' do
      env = { 'PATH_INFO' => '/test', 'rhales.template_name' => 'cached' }

      # First call loads schema
      middleware.call(env)

      # Delete schema file to prove it's cached
      File.delete(File.join(schemas_dir, 'cached.json'))

      # Second call should use cached schema
      expect {
        middleware.call(env)
      }.not_to raise_error

      expect(middleware.stats[:total_validations]).to eq(2)
    end
  end

  describe 'malformed JSON in hydration blocks' do
    let(:html_response) do
      '<html><body><script type="application/json" data-window="test">{invalid json}</script></body></html>'
    end

    before do
      schema = { 'type' => 'object' }
      File.write(File.join(schemas_dir, 'test.json'), JSON.generate(schema))
    end

    it 'logs warning and skips validation for that block' do
      env = { 'PATH_INFO' => '/test', 'rhales.template_name' => 'test' }

      expect {
        response = middleware.call(env)
        expect(response[0]).to eq(200)
      }.to output(/Failed to parse hydration JSON/).to_stderr
    end
  end

  after do
    # Clean up fixture schemas
    FileUtils.rm_rf(schemas_dir) if File.exist?(schemas_dir)
  end
end
