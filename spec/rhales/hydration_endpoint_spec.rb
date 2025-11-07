# spec/rhales/hydration_endpoint_spec.rb
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Rhales::HydrationEndpoint do
  let(:mock_config) do
    config = double('config')
    allow(config).to receive(:hydration).and_return(hydration_config)
    config
  end

  let(:hydration_config) do
    double('hydration_config',
      api_cache_enabled: true,
      api_cache_ttl: 600,
      cors_enabled: false,
      cors_origin: nil
    )
  end

  let(:mock_context) do
    double('context',
      req: mock_request,
      client: { 'user_id' => 123, 'theme' => 'dark' },
      locale: 'en'
    )
  end

  let(:mock_request) { double('request') }

  describe '#initialize' do
    it 'initializes with config and context' do
      endpoint = described_class.new(mock_config, mock_context)
      expect(endpoint.instance_variable_get(:@config)).to eq(mock_config)
      expect(endpoint.instance_variable_get(:@context)).to eq(mock_context)
    end

    it 'initializes with config only' do
      endpoint = described_class.new(mock_config)
      expect(endpoint.instance_variable_get(:@config)).to eq(mock_config)
      expect(endpoint.instance_variable_get(:@context)).to be_nil
    end
  end

  describe '#render_json' do
    let(:endpoint) { described_class.new(mock_config, mock_context) }
    let(:template_name) { 'test_template' }
    let(:mock_data) { { 'data' => { 'count' => 42 }, 'config' => { 'api_url' => 'test.com' } } }

    before do
      allow(endpoint).to receive(:process_template_data).and_return(mock_data)
    end

    it 'returns JSON response with correct structure' do
      result = endpoint.render_json(template_name)

      expect(result[:content]).to eq(JSON.generate(mock_data))
      expect(result[:content_type]).to eq('application/json')
      expect(result[:headers]).to be_a(Hash)
    end

    it 'includes proper headers' do
      result = endpoint.render_json(template_name)
      headers = result[:headers]

      expect(headers['Content-Type']).to eq('application/json')
      expect(headers['Cache-Control']).to eq('public, max-age=600')
      expect(headers['Vary']).to eq('Accept, Accept-Encoding')
      expect(headers['ETag']).to match(/^"[a-f0-9]{32}"$/)
    end

    it 'processes template with additional context' do
      additional_context = { 'extra_data' => 'value' }

      expect(endpoint).to receive(:process_template_data)
        .with(template_name, additional_context)
        .and_return(mock_data)

      endpoint.render_json(template_name, additional_context)
    end

    context 'with JSON serialization errors' do
      it 'handles JSON::GeneratorError' do
        allow(endpoint).to receive(:process_template_data).and_raise(JSON::GeneratorError, 'Invalid encoding')

        result = endpoint.render_json(template_name)
        parsed_content = JSON.parse(result[:content])

        expect(parsed_content['error']['message']).to include('Failed to serialize data to JSON')
        expect(parsed_content['error']['template']).to eq(template_name)
        expect(parsed_content['error']['timestamp']).to be_a(String)
        expect(result[:content_type]).to eq('application/json')
      end

      it 'handles JSON::NestingError' do
        allow(endpoint).to receive(:process_template_data).and_raise(JSON::NestingError, 'Nesting too deep')

        result = endpoint.render_json(template_name)
        parsed_content = JSON.parse(result[:content])

        expect(parsed_content['error']['message']).to include('Failed to serialize data to JSON')
        expect(parsed_content['error']['message']).to include('Nesting too deep')
      end

      it 'handles ArgumentError from JSON' do
        allow(endpoint).to receive(:process_template_data).and_raise(ArgumentError, 'Invalid JSON argument')

        result = endpoint.render_json(template_name)
        parsed_content = JSON.parse(result[:content])

        expect(parsed_content['error']['message']).to include('Failed to serialize data to JSON')
        expect(parsed_content['error']['template']).to eq(template_name)
      end

      it 'handles Encoding::UndefinedConversionError' do
        allow(endpoint).to receive(:process_template_data).and_raise(Encoding::UndefinedConversionError, 'Cannot convert')

        result = endpoint.render_json(template_name)
        parsed_content = JSON.parse(result[:content])

        expect(parsed_content['error']['message']).to include('Failed to serialize data to JSON')
        expect(result[:content_type]).to eq('application/json')
        expect(result[:headers]['Content-Type']).to eq('application/json')
      end

      it 'error response is valid JSON and has proper headers' do
        allow(endpoint).to receive(:process_template_data).and_raise(JSON::GeneratorError, 'Test error')

        result = endpoint.render_json(template_name)

        # Verify it's valid JSON
        expect { JSON.parse(result[:content]) }.not_to raise_error

        # Verify headers are still set correctly
        expect(result[:headers]['Content-Type']).to eq('application/json')
        expect(result[:headers]['ETag']).to match(/^"[a-f0-9]{32}"$/)
      end
    end

    context 'with unexpected error' do
      before do
        allow(endpoint).to receive(:process_template_data).and_raise(StandardError, 'Unexpected issue')
      end

      it 'returns generic error response' do
        result = endpoint.render_json(template_name)
        parsed_content = JSON.parse(result[:content])

        expect(parsed_content['error']['message']).to include('Unexpected error during JSON generation')
        expect(parsed_content['error']['template']).to eq(template_name)
        expect(parsed_content['error']['timestamp']).to be_a(String)
      end

      it 'maintains proper response structure for unexpected errors' do
        result = endpoint.render_json(template_name)

        expect(result[:content_type]).to eq('application/json')
        expect(result[:headers]).to be_a(Hash)
        expect { JSON.parse(result[:content]) }.not_to raise_error
      end
    end

    context 'with CORS enabled' do
      before do
        allow(hydration_config).to receive(:cors_enabled).and_return(true)
        allow(hydration_config).to receive(:cors_origin).and_return('https://example.com')
      end

      it 'includes CORS headers' do
        result = endpoint.render_json(template_name)
        headers = result[:headers]

        expect(headers['Access-Control-Allow-Origin']).to eq('https://example.com')
        expect(headers['Access-Control-Allow-Methods']).to eq('GET, HEAD, OPTIONS')
        expect(headers['Access-Control-Allow-Headers']).to eq('Accept, Accept-Encoding, Authorization')
        expect(headers['Access-Control-Max-Age']).to eq('86400')
      end
    end

    context 'with caching disabled' do
      before do
        allow(hydration_config).to receive(:api_cache_enabled).and_return(false)
      end

      it 'sets no-cache headers' do
        result = endpoint.render_json(template_name)
        headers = result[:headers]

        expect(headers['Cache-Control']).to eq('no-cache, no-store, must-revalidate')
      end
    end
  end

  describe '#render_module' do
    let(:endpoint) { described_class.new(mock_config, mock_context) }
    let(:template_name) { 'test_template' }
    let(:mock_data) { { 'data' => { 'count' => 42 } } }

    before do
      allow(endpoint).to receive(:process_template_data).and_return(mock_data)
    end

    it 'returns ES module response' do
      result = endpoint.render_module(template_name)

      expected_content = "export default #{JSON.generate(mock_data)};"
      expect(result[:content]).to eq(expected_content)
      expect(result[:content_type]).to eq('text/javascript')
    end

    it 'includes module-specific headers' do
      result = endpoint.render_module(template_name)
      headers = result[:headers]

      expect(headers['Content-Type']).to eq('text/javascript')
      expect(headers['Cache-Control']).to eq('public, max-age=600')
      expect(headers['ETag']).not_to be_nil
    end

    it 'processes template with additional context' do
      additional_context = { 'module_data' => 'value' }

      expect(endpoint).to receive(:process_template_data)
        .with(template_name, additional_context)
        .and_return(mock_data)

      endpoint.render_module(template_name, additional_context)
    end
  end

  describe '#render_jsonp' do
    let(:endpoint) { described_class.new(mock_config, mock_context) }
    let(:template_name) { 'test_template' }
    let(:callback_name) { 'myCallback' }
    let(:mock_data) { { 'data' => { 'count' => 42 } } }

    before do
      allow(endpoint).to receive(:process_template_data).and_return(mock_data)
    end

    it 'returns JSONP response with callback' do
      result = endpoint.render_jsonp(template_name, callback_name)

      expected_content = "#{callback_name}(#{JSON.generate(mock_data)});"
      expect(result[:content]).to eq(expected_content)
      expect(result[:content_type]).to eq('application/javascript')
    end

    it 'includes JSONP-specific headers' do
      result = endpoint.render_jsonp(template_name, callback_name)
      headers = result[:headers]

      expect(headers['Content-Type']).to eq('application/javascript')
      expect(headers['Cache-Control']).to eq('public, max-age=600')
    end

    it 'processes template with additional context' do
      additional_context = { 'jsonp_data' => 'value' }

      expect(endpoint).to receive(:process_template_data)
        .with(template_name, additional_context)
        .and_return(mock_data)

      endpoint.render_jsonp(template_name, callback_name, additional_context)
    end
  end

  describe '#data_changed?' do
    let(:endpoint) { described_class.new(mock_config, mock_context) }
    let(:template_name) { 'test_template' }

    it 'returns true when ETags differ' do
      allow(endpoint).to receive(:calculate_etag).and_return('new_etag')

      result = endpoint.data_changed?(template_name, 'old_etag')
      expect(result).to be(true)
    end

    it 'returns false when ETags match' do
      etag = 'same_etag'
      allow(endpoint).to receive(:calculate_etag).and_return(etag)

      result = endpoint.data_changed?(template_name, etag)
      expect(result).to be(false)
    end

    it 'passes additional context to ETag calculation' do
      additional_context = { 'etag_data' => 'value' }

      expect(endpoint).to receive(:calculate_etag)
        .with(template_name, additional_context)
        .and_return('etag')

      endpoint.data_changed?(template_name, 'old_etag', additional_context)
    end
  end

  describe '#calculate_etag' do
    let(:endpoint) { described_class.new(mock_config, mock_context) }
    let(:template_name) { 'test_template' }
    let(:mock_data) { { 'data' => { 'count' => 42 } } }

    before do
      allow(endpoint).to receive(:process_template_data).and_return(mock_data)
    end

    it 'calculates MD5 hash of JSON data' do
      result = endpoint.calculate_etag(template_name)
      expected_etag = Digest::MD5.hexdigest(JSON.generate(mock_data))

      expect(result).to eq(expected_etag)
      expect(result).to match(/^[a-f0-9]{32}$/)
    end

    it 'returns same ETag for same data' do
      etag1 = endpoint.calculate_etag(template_name)
      etag2 = endpoint.calculate_etag(template_name)

      expect(etag1).to eq(etag2)
    end

    it 'returns different ETag for different data' do
      etag1 = endpoint.calculate_etag(template_name)

      allow(endpoint).to receive(:process_template_data)
        .and_return({ 'data' => { 'count' => 99 } })

      etag2 = endpoint.calculate_etag(template_name)
      expect(etag1).not_to eq(etag2)
    end

    it 'passes template name and additional context to process_template_data' do
      additional_context = { 'etag_test' => 'value' }

      expect(endpoint).to receive(:process_template_data)
        .with(template_name, additional_context)
        .and_return(mock_data)

      endpoint.calculate_etag(template_name, additional_context)
    end

    it 'handles complex nested data structures' do
      complex_data = {
        'users' => [
          { 'id' => 1, 'name' => 'John', 'settings' => { 'theme' => 'dark' } },
          { 'id' => 2, 'name' => 'Jane', 'settings' => { 'theme' => 'light' } }
        ],
        'metadata' => { 'timestamp' => '2023-01-01T00:00:00Z', 'version' => '1.0' }
      }

      allow(endpoint).to receive(:process_template_data).and_return(complex_data)

      result = endpoint.calculate_etag(template_name)
      expected_etag = Digest::MD5.hexdigest(JSON.generate(complex_data))

      expect(result).to eq(expected_etag)
    end

    it 'produces consistent ETags for same logical data' do
      data1 = { 'a' => 1, 'b' => 2 }
      data2 = { 'a' => 1, 'b' => 2 } # Same data, same order

      allow(endpoint).to receive(:process_template_data).and_return(data1)
      etag1 = endpoint.calculate_etag(template_name)

      allow(endpoint).to receive(:process_template_data).and_return(data2)
      etag2 = endpoint.calculate_etag(template_name)

      # Same data should produce same ETag
      expect(etag1).to eq(etag2)
    end

    it 'handles empty data' do
      allow(endpoint).to receive(:process_template_data).and_return({})

      result = endpoint.calculate_etag(template_name)
      expected_etag = Digest::MD5.hexdigest('{}')

      expect(result).to eq(expected_etag)
    end

    it 'handles nil values in data' do
      data_with_nils = { 'value' => nil, 'count' => 0, 'enabled' => false }
      allow(endpoint).to receive(:process_template_data).and_return(data_with_nils)

      result = endpoint.calculate_etag(template_name)
      expected_etag = Digest::MD5.hexdigest(JSON.generate(data_with_nils))

      expect(result).to eq(expected_etag)
    end
  end

  describe '#process_template_data (private)' do
    let(:endpoint) { described_class.new(mock_config, mock_context) }
    let(:template_name) { 'test_template' }
    let(:mock_view) { double('view') }
    let(:mock_aggregator) { double('aggregator') }
    let(:mock_composition) { double('composition') }

    before do
      allow(Rhales::View).to receive(:new).and_return(mock_view)
      allow(Rhales::HydrationDataAggregator).to receive(:new).and_return(mock_aggregator)
      allow(mock_view).to receive(:send).with(:build_view_composition, template_name).and_return(mock_composition)
      allow(mock_composition).to receive(:resolve!)
      allow(mock_aggregator).to receive(:aggregate).and_return({ 'processed' => 'data' })
      allow(endpoint).to receive(:create_template_context).and_return(mock_context)
    end

    it 'processes template through full pipeline' do
      result = endpoint.send(:process_template_data, template_name, {})

      expect(result).to eq({ 'processed' => 'data' })
      expect(mock_composition).to have_received(:resolve!)
      expect(mock_aggregator).to have_received(:aggregate).with(mock_composition)
    end

    it 'creates template context from additional context' do
      additional_context = { 'extra' => 'data' }

      expect(endpoint).to receive(:create_template_context)
        .with(additional_context)
        .and_return(mock_context)

      endpoint.send(:process_template_data, template_name, additional_context)
    end

    it 'creates View with correct parameters' do
      expect(Rhales::View).to receive(:new)
        .with(mock_context.req, client: {})
        .and_return(mock_view)

      endpoint.send(:process_template_data, template_name, {})
    end

    it 'creates HydrationDataAggregator with template context' do
      expect(Rhales::HydrationDataAggregator).to receive(:new)
        .with(mock_context)
        .and_return(mock_aggregator)

      endpoint.send(:process_template_data, template_name, {})
    end

    it 'calls build_view_composition with template name' do
      expect(mock_view).to receive(:send)
        .with(:build_view_composition, template_name)
        .and_return(mock_composition)

      endpoint.send(:process_template_data, template_name, {})
    end

    it 'resolves composition before aggregating' do
      expect(mock_composition).to receive(:resolve!).ordered
      expect(mock_aggregator).to receive(:aggregate).with(mock_composition).ordered

      endpoint.send(:process_template_data, template_name, {})
    end

    context 'with processing errors' do
      it 'handles View creation error' do
        allow(Rhales::View).to receive(:new).and_raise(StandardError, 'View creation failed')

        result = endpoint.send(:process_template_data, template_name, {})

        expect(result[:error]).not_to be_nil
        expect(result[:error][:message]).to include('Failed to process template data')
        expect(result[:error][:message]).to include('View creation failed')
      end

      it 'handles composition building error' do
        allow(mock_view).to receive(:send).and_raise(StandardError, 'Composition error')

        result = endpoint.send(:process_template_data, template_name, {})

        expect(result[:error]).not_to be_nil
        expect(result[:error][:template]).to eq(template_name)
        expect(result[:error][:timestamp]).to match(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
      end

      it 'handles composition resolve error' do
        allow(mock_composition).to receive(:resolve!).and_raise(StandardError, 'Resolution failed')

        result = endpoint.send(:process_template_data, template_name, {})

        expect(result[:error][:message]).to include('Failed to process template data')
        expect(result[:error][:message]).to include('Resolution failed')
      end

      it 'handles aggregation error' do
        allow(mock_aggregator).to receive(:aggregate).and_raise(StandardError, 'Aggregation failed')

        result = endpoint.send(:process_template_data, template_name, {})

        expect(result[:error][:message]).to include('Failed to process template data')
        expect(result[:error][:template]).to eq(template_name)
      end

      it 'returns proper error structure for any error' do
        allow(mock_view).to receive(:send).and_raise(RuntimeError, 'Test runtime error')

        result = endpoint.send(:process_template_data, template_name, {})

        expect(result).to have_key(:error)
        expect(result[:error]).to have_key(:message)
        expect(result[:error]).to have_key(:template)
        expect(result[:error]).to have_key(:timestamp)
        expect(result[:error][:template]).to eq(template_name)
      end

      it 'error structure is JSON serializable' do
        allow(mock_view).to receive(:send).and_raise(StandardError, 'Serialization test')

        result = endpoint.send(:process_template_data, template_name, {})

        expect { JSON.generate(result) }.not_to raise_error
      end
    end

    context 'with different template contexts' do
      it 'processes with empty additional context' do
        result = endpoint.send(:process_template_data, template_name, {})
        expect(result).to eq({ 'processed' => 'data' })
      end

      it 'processes with complex additional context' do
        complex_context = {
          'user_data' => { 'id' => 123, 'role' => 'admin' },
          'settings' => { 'theme' => 'dark', 'notifications' => true }
        }

        endpoint.send(:process_template_data, template_name, complex_context)

        expect(endpoint).to have_received(:create_template_context).with(complex_context)
      end
    end
  end

  describe '#create_template_context (private)' do
    let(:endpoint) { described_class.new(mock_config, mock_context) }

    context 'with existing context' do
      it 'merges additional context with existing context' do
        additional_context = { 'new_key' => 'new_value' }
        merged_props = mock_context.client.merge(additional_context)

        expect(mock_context.class).to receive(:for_view)
          .with(mock_context.req, mock_context.locale, **merged_props)
          .and_return('merged_context')

        result = endpoint.send(:create_template_context, additional_context)
        expect(result).to eq('merged_context')
      end
    end

    context 'without existing context' do
      let(:endpoint) { described_class.new(mock_config) }

      it 'creates minimal context with additional data' do
        additional_context = { 'standalone' => 'data' }

        expect(Rhales::Context).to receive(:minimal)
          .with(client: additional_context)
          .and_return('minimal_context')

        result = endpoint.send(:create_template_context, additional_context)
        expect(result).to eq('minimal_context')
      end
    end
  end

  describe 'header generation methods (private)' do
    let(:endpoint) { described_class.new(mock_config, mock_context) }
    let(:mock_data) { { 'test' => 'data' } }

    describe '#json_headers' do
      it 'generates basic JSON headers' do
        headers = endpoint.send(:json_headers, mock_data)

        expect(headers['Content-Type']).to eq('application/json')
        expect(headers['Cache-Control']).to eq('public, max-age=600')
        expect(headers['Vary']).to eq('Accept, Accept-Encoding')
        expect(headers['ETag']).to match(/^"[a-f0-9]{32}"$/)
      end
    end

    describe '#module_headers' do
      it 'generates JavaScript module headers' do
        headers = endpoint.send(:module_headers, mock_data)

        expect(headers['Content-Type']).to eq('text/javascript')
        expect(headers['Cache-Control']).to eq('public, max-age=600')
        expect(headers['ETag']).not_to be_nil
      end
    end

    describe '#jsonp_headers' do
      it 'generates JSONP JavaScript headers' do
        headers = endpoint.send(:jsonp_headers, mock_data)

        expect(headers['Content-Type']).to eq('application/javascript')
        expect(headers['Cache-Control']).to eq('public, max-age=600')
      end
    end

    describe '#cache_control_header' do
      context 'with caching enabled' do
        it 'returns public cache header with TTL' do
          header = endpoint.send(:cache_control_header)
          expect(header).to eq('public, max-age=600')
        end
      end

      context 'with caching disabled' do
        before do
          allow(hydration_config).to receive(:api_cache_enabled).and_return(false)
        end

        it 'returns no-cache header' do
          header = endpoint.send(:cache_control_header)
          expect(header).to eq('no-cache, no-store, must-revalidate')
        end
      end

      context 'with custom TTL' do
        before do
          allow(hydration_config).to receive(:api_cache_ttl).and_return(1200)
        end

        it 'uses custom TTL value' do
          header = endpoint.send(:cache_control_header)
          expect(header).to eq('public, max-age=1200')
        end
      end

      context 'with nil TTL' do
        before do
          allow(hydration_config).to receive(:api_cache_ttl).and_return(nil)
        end

        it 'uses default TTL fallback' do
          header = endpoint.send(:cache_control_header)
          expect(header).to eq('public, max-age=300')
        end
      end
    end

    describe '#cors_enabled?' do
      it 'returns false by default' do
        result = endpoint.send(:cors_enabled?)
        expect(result).to be(false)
      end

      context 'when CORS is enabled' do
        before do
          allow(hydration_config).to receive(:cors_enabled).and_return(true)
        end

        it 'returns true' do
          result = endpoint.send(:cors_enabled?)
          expect(result).to be(true)
        end
      end
    end

    describe '#cors_headers' do
      before do
        allow(hydration_config).to receive(:cors_origin).and_return('https://trusted.com')
      end

      it 'returns CORS headers with custom origin' do
        headers = endpoint.send(:cors_headers)

        expect(headers['Access-Control-Allow-Origin']).to eq('https://trusted.com')
        expect(headers['Access-Control-Allow-Methods']).to eq('GET, HEAD, OPTIONS')
        expect(headers['Access-Control-Allow-Headers']).to eq('Accept, Accept-Encoding, Authorization')
        expect(headers['Access-Control-Max-Age']).to eq('86400')
      end

      context 'with nil origin' do
        before do
          allow(hydration_config).to receive(:cors_origin).and_return(nil)
        end

        it 'defaults to wildcard origin' do
          headers = endpoint.send(:cors_headers)
          expect(headers['Access-Control-Allow-Origin']).to eq('*')
        end
      end
    end
  end

  describe 'integration scenarios' do
    let(:endpoint) { described_class.new(mock_config, mock_context) }

    context 'with real JSON data' do
      let(:complex_data) do
        {
          'user' => { 'id' => 123, 'name' => 'John', 'preferences' => { 'theme' => 'dark' } },
          'config' => { 'api_url' => 'https://api.example.com', 'timeout' => 5000 },
          'features' => ['feature_a', 'feature_b'],
          'metadata' => { 'timestamp' => Time.now.iso8601, 'version' => '1.0.0' }
        }
      end

      before do
        allow(endpoint).to receive(:process_template_data).and_return(complex_data)
      end

      it 'handles complex nested data structures in JSON' do
        result = endpoint.render_json('complex_template')
        parsed = JSON.parse(result[:content])

        expect(parsed['user']['preferences']['theme']).to eq('dark')
        expect(parsed['features']).to eq(['feature_a', 'feature_b'])
        expect(parsed['config']['api_url']).to eq('https://api.example.com')
      end

      it 'handles complex data in ES module format' do
        result = endpoint.render_module('complex_template')

        expect(result[:content]).to start_with('export default ')
        expect(result[:content]).to end_with(';')
        expect(result[:content]).to include('"theme":"dark"')
      end

      it 'handles complex data in JSONP format' do
        result = endpoint.render_jsonp('complex_template', 'handleData')

        expect(result[:content]).to start_with('handleData(')
        expect(result[:content]).to end_with(');')
        expect(result[:content]).to include('"api_url":"https://api.example.com"')
      end
    end

    context 'ETag consistency' do
      let(:template_name) { 'consistent_template' }
      let(:test_data) { { 'counter' => 1, 'message' => 'hello' } }

      before do
        allow(endpoint).to receive(:process_template_data).and_return(test_data)
      end

      it 'generates consistent ETags across response types' do
        json_result = endpoint.render_json(template_name)
        module_result = endpoint.render_module(template_name)
        calculated_etag = endpoint.calculate_etag(template_name)

        # All should have same ETag since they use same underlying data
        json_etag = json_result[:headers]['ETag'].gsub('"', '')
        module_etag = module_result[:headers]['ETag'].gsub('"', '')

        expect(json_etag).to eq(module_etag)
        expect(json_etag).to eq(calculated_etag)
      end
    end
  end
end
