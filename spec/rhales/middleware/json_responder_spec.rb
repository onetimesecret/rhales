# frozen_string_literal: true

require 'spec_helper'
require 'rhales/middleware/json_responder'
require 'json'

RSpec.describe Rhales::Middleware::JsonResponder do
  let(:app) { ->(env) { [200, { 'Content-Type' => 'text/html' }, [html_response]] } }
  let(:html_response) { '<html><body>Test</body></html>' }

  subject(:middleware) do
    described_class.new(app, enabled: true, include_metadata: false)
  end

  describe '#call' do
    context 'when middleware is disabled' do
      subject(:middleware) do
        described_class.new(app, enabled: false)
      end

      it 'passes through without modification when disabled' do
        env = { 'HTTP_ACCEPT' => 'application/json' }
        response = middleware.call(env)

        expect(response).to eq([200, { 'Content-Type' => 'text/html' }, [html_response]])
      end
    end

    context 'HTML requests (default behavior)' do
      it 'passes through when Accept header is text/html' do
        env = { 'HTTP_ACCEPT' => 'text/html' }
        response = middleware.call(env)

        expect(response).to eq([200, { 'Content-Type' => 'text/html' }, [html_response]])
      end

      it 'passes through when Accept header is missing' do
        env = {}
        response = middleware.call(env)

        expect(response).to eq([200, { 'Content-Type' => 'text/html' }, [html_response]])
      end

      it 'passes through when Accept header is */*' do
        env = { 'HTTP_ACCEPT' => '*/*' }
        response = middleware.call(env)

        expect(response).to eq([200, { 'Content-Type' => 'text/html' }, [html_response]])
      end
    end

    context 'JSON requests with no hydration data' do
      let(:html_response) { '<html><body>No hydration data</body></html>' }

      it 'returns empty JSON object when no hydration blocks found' do
        env = { 'HTTP_ACCEPT' => 'application/json' }
        status, headers, body = middleware.call(env)

        expect(status).to eq(200)
        expect(headers['content-type']).to eq('application/json')

        json_data = JSON.parse(body.first)
        expect(json_data).to eq({})
      end
    end

    context 'JSON requests with single hydration window' do
      let(:html_response) do
        <<~HTML
          <html>
          <head><title>Test</title></head>
          <body>
            <div id="app"></div>
            <script id="data-1" type="application/json" data-window="appData">
            {"user":"Alice","count":42,"active":true}
            </script>
            <script nonce="abc123">
              window['appData'] = JSON.parse(document.getElementById('data-1').textContent);
            </script>
          </body>
          </html>
        HTML
      end

      it 'extracts and returns flattened hydration data as JSON' do
        env = {
          'HTTP_ACCEPT' => 'application/json',
          'rhales.template_name' => 'test'
        }

        status, headers, body = middleware.call(env)

        expect(status).to eq(200)
        expect(headers['content-type']).to eq('application/json')
        expect(headers['cache-control']).to eq('no-cache')

        json_data = JSON.parse(body.first)
        expect(json_data['user']).to eq('Alice')
        expect(json_data['count']).to eq(42)
        expect(json_data['active']).to eq(true)
      end

      it 'sets correct Content-Length header' do
        env = { 'HTTP_ACCEPT' => 'application/json' }
        status, headers, body = middleware.call(env)

        expect(headers['content-length'].to_i).to eq(body.first.bytesize)
      end
    end

    context 'JSON requests with multiple hydration windows' do
      let(:html_response) do
        <<~HTML
          <html>
          <body>
            <script id="data-1" type="application/json" data-window="appData">
            {"user":"John"}
            </script>
            <script>window['appData'] = JSON.parse(document.getElementById('data-1').textContent);</script>
            <script id="data-2" type="application/json" data-window="config">
            {"theme":"dark","locale":"en"}
            </script>
            <script>window['config'] = JSON.parse(document.getElementById('data-2').textContent);</script>
          </body>
          </html>
        HTML
      end

      it 'returns keyed object with all hydration windows' do
        env = { 'HTTP_ACCEPT' => 'application/json' }
        status, headers, body = middleware.call(env)

        expect(status).to eq(200)
        expect(headers['content-type']).to eq('application/json')

        json_data = JSON.parse(body.first)
        expect(json_data.keys).to contain_exactly('appData', 'config')
        expect(json_data['appData']['user']).to eq('John')
        expect(json_data['config']['theme']).to eq('dark')
        expect(json_data['config']['locale']).to eq('en')
      end
    end

    context 'JSON requests with metadata enabled' do
      subject(:middleware) do
        described_class.new(app, enabled: true, include_metadata: true)
      end

      let(:html_response) do
        <<~HTML
          <html>
          <body>
            <script type="application/json" data-window="testData">{"test":true}</script>
          </body>
          </html>
        HTML
      end

      it 'includes template name and wraps data in metadata' do
        env = {
          'HTTP_ACCEPT' => 'application/json',
          'rhales.template_name' => 'dashboard'
        }

        status, headers, body = middleware.call(env)

        expect(status).to eq(200)
        json_data = JSON.parse(body.first)

        expect(json_data.keys).to contain_exactly('template', 'data')
        expect(json_data['template']).to eq('dashboard')
        expect(json_data['data']).to be_a(Hash)
        expect(json_data['data']['testData']).to eq({ 'test' => true })
      end
    end

    context 'Accept header parsing' do
      let(:html_response) do
        '<html><body><script type="application/json" data-window="test">{"data":1}</script></body></html>'
      end

      it 'handles weighted preferences' do
        env = { 'HTTP_ACCEPT' => 'text/html, application/json;q=0.9' }
        status, headers, body = middleware.call(env)

        # Still returns JSON since application/json is present
        expect(headers['content-type']).to eq('application/json')
      end

      it 'handles complex Accept headers' do
        env = { 'HTTP_ACCEPT' => 'application/xml, application/json, text/plain' }
        status, headers, body = middleware.call(env)

        expect(headers['content-type']).to eq('application/json')
      end

      it 'handles application/json with charset' do
        env = { 'HTTP_ACCEPT' => 'application/json;charset=utf-8' }
        status, headers, body = middleware.call(env)

        expect(headers['content-type']).to eq('application/json')
      end
    end

    context 'non-200 status codes' do
      let(:app) { ->(env) { [404, { 'Content-Type' => 'text/html' }, ['Not Found']] } }

      it 'passes through non-200 responses unchanged' do
        env = { 'HTTP_ACCEPT' => 'application/json' }
        response = middleware.call(env)

        expect(response).to eq([404, { 'Content-Type' => 'text/html' }, ['Not Found']])
      end
    end

    context 'non-HTML responses' do
      let(:app) { ->(env) { [200, { 'Content-Type' => 'application/json' }, ['{"api":true}']] } }

      it 'passes through non-HTML responses unchanged' do
        env = { 'HTTP_ACCEPT' => 'application/json' }
        response = middleware.call(env)

        expect(response).to eq([200, { 'Content-Type' => 'application/json' }, ['{"api":true}']])
      end
    end

    context 'malformed JSON in hydration blocks' do
      let(:html_response) do
        <<~HTML
          <html>
          <body>
            <script type="application/json" data-window="good">{"valid":true}</script>
            <script type="application/json" data-window="bad">{invalid json}</script>
          </body>
          </html>
        HTML
      end

      it 'logs warning and skips malformed blocks but returns valid ones' do
        env = { 'HTTP_ACCEPT' => 'application/json' }

        expect {
          status, headers, body = middleware.call(env)

          json_data = JSON.parse(body.first)
          expect(json_data['valid']).to eq(true)
          expect(json_data).not_to have_key('bad')
        }.to output(/Failed to parse hydration JSON for window\.bad/).to_stderr
      end
    end

    context 'complex nested JSON data' do
      let(:html_response) do
        <<~HTML
          <html>
          <body>
            <script type="application/json" data-window="complexData">
            {
              "user": {
                "id": 123,
                "name": "Alice",
                "roles": ["admin", "user"],
                "metadata": {
                  "created_at": "2024-01-01",
                  "updated_at": "2024-01-15"
                }
              },
              "posts": [
                {"id": 1, "title": "First Post"},
                {"id": 2, "title": "Second Post"}
              ],
              "flags": {
                "feature_a": true,
                "feature_b": false
              }
            }
            </script>
          </body>
          </html>
        HTML
      end

      it 'preserves complex nested structures' do
        env = { 'HTTP_ACCEPT' => 'application/json' }
        status, headers, body = middleware.call(env)

        json_data = JSON.parse(body.first)

        expect(json_data['user']['id']).to eq(123)
        expect(json_data['user']['roles']).to eq(['admin', 'user'])
        expect(json_data['user']['metadata']['created_at']).to eq('2024-01-01')
        expect(json_data['posts'].size).to eq(2)
        expect(json_data['flags']['feature_a']).to eq(true)
      end
    end

    context 'different Rack body types' do
      it 'handles Array body' do
        app_with_array = ->(env) {
          [200, { 'Content-Type' => 'text/html' }, ['<html><script type="application/json" data-window="test">{"arr":1}</script></html>']]
        }
        middleware = described_class.new(app_with_array)
        env = { 'HTTP_ACCEPT' => 'application/json' }

        status, headers, body = middleware.call(env)

        json_data = JSON.parse(body.first)
        expect(json_data['arr']).to eq(1)
      end

      it 'handles StringIO body' do
        app_with_io = ->(env) {
          [200, { 'Content-Type' => 'text/html' }, StringIO.new('<html><script type="application/json" data-window="test">{"io":1}</script></html>')]
        }
        middleware = described_class.new(app_with_io)
        env = { 'HTTP_ACCEPT' => 'application/json' }

        status, headers, body = middleware.call(env)

        json_data = JSON.parse(body.first)
        expect(json_data['io']).to eq(1)
      end
    end

    context 'edge cases' do
      it 'handles empty script content' do
        html = '<html><script type="application/json" data-window="test"></script></html>'
        app_empty = ->(env) { [200, { 'Content-Type' => 'text/html' }, [html]] }
        middleware = described_class.new(app_empty)

        env = { 'HTTP_ACCEPT' => 'application/json' }

        expect {
          status, headers, body = middleware.call(env)
          json_data = JSON.parse(body.first)
          expect(json_data).to eq({})
        }.to output(/Failed to parse hydration JSON/).to_stderr
      end

      it 'handles script tags with single quotes' do
        html = "<html><script type='application/json' data-window='test'>{\"sq\":true}</script></html>"
        app_sq = ->(env) { [200, { 'Content-Type' => 'text/html' }, [html]] }
        middleware = described_class.new(app_sq)

        env = { 'HTTP_ACCEPT' => 'application/json' }
        status, headers, body = middleware.call(env)

        json_data = JSON.parse(body.first)
        expect(json_data['sq']).to eq(true)
      end
    end
  end
end
