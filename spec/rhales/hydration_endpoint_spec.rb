require 'spec_helper'

RSpec.describe Rhales::HydrationEndpoint do
  let(:config) do
    config = Rhales::Configuration.new
    config.hydration.api_cache_enabled = true
    config.hydration.api_cache_ttl = 300
    config.hydration.cors_enabled = true
    config.hydration.cors_origin = '*'
    config
  end

  let(:context) do
    double('Context',
      to_h: { user: 'john', role: 'admin' },
      get: proc { |key| { user: 'john', role: 'admin' }[key] }
    )
  end

  let(:endpoint) { described_class.new(config, context) }
  let(:template_name) { 'test_template' }

  before do
    # Mock the View and aggregator classes
    allow(Rhales::View).to receive(:new).and_return(double('View', collect_template_dependencies: ['test_template']))
    allow(Rhales::HydrationDataAggregator).to receive(:new).and_return(
      double('Aggregator',
        merged_data: { 'userData' => { user: 'john' }, 'config' => { theme: 'dark' } },
        collect_from_template: nil
      )
    )
  end

  describe '#render_json' do
    it 'returns JSON response with correct content type' do
      result = endpoint.render_json(template_name)

      expect(result[:content_type]).to eq('application/json')
      expect(result[:content]).to be_a(String)

      parsed_content = JSON.parse(result[:content])
      expect(parsed_content).to have_key('userData')
      expect(parsed_content).to have_key('config')
    end

    it 'includes proper headers' do
      result = endpoint.render_json(template_name)

      headers = result[:headers]
      expect(headers['Content-Type']).to eq('application/json')
      expect(headers['Cache-Control']).to include('public, max-age=300')
      expect(headers['Vary']).to eq('Accept, Accept-Encoding')
      expect(headers['ETag']).to match(/^"[a-f0-9]{32}"$/)
    end

    it 'includes CORS headers when enabled' do
      result = endpoint.render_json(template_name)

      headers = result[:headers]
      expect(headers['Access-Control-Allow-Origin']).to eq('*')
      expect(headers['Access-Control-Allow-Methods']).to eq('GET, HEAD, OPTIONS')
      expect(headers['Access-Control-Allow-Headers']).to eq('Accept, Accept-Encoding, Authorization')
      expect(headers['Access-Control-Max-Age']).to eq('86400')
    end

    it 'handles additional context' do
      additional_context = { page_title: 'Test Page' }

      # Mock Context.new to return a double with the merged context
      allow(Rhales::Context).to receive(:new).with(hash_including(additional_context)).and_return(context)

      result = endpoint.render_json(template_name, additional_context)

      expect(result[:content_type]).to eq('application/json')
    end

    it 'handles caching disabled' do
      config.hydration.api_cache_enabled = false

      result = endpoint.render_json(template_name)

      headers = result[:headers]
      expect(headers['Cache-Control']).to eq('no-cache, no-store, must-revalidate')
    end

    it 'handles CORS disabled' do
      config.hydration.cors_enabled = false

      result = endpoint.render_json(template_name)

      headers = result[:headers]
      expect(headers).not_to have_key('Access-Control-Allow-Origin')
    end
  end

  describe '#render_module' do
    it 'returns ES module response with correct content type' do
      result = endpoint.render_module(template_name)

      expect(result[:content_type]).to eq('text/javascript')
      expect(result[:content]).to start_with('export default ')
      expect(result[:content]).to end_with(';')
    end

    it 'generates valid ES module syntax' do
      result = endpoint.render_module(template_name)

      # Should be parseable as JavaScript module export
      expect(result[:content]).to match(/^export default \{.*\};$/)
    end

    it 'includes same headers as JSON with different content type' do
      json_result = endpoint.render_json(template_name)
      module_result = endpoint.render_module(template_name)

      # Headers should be the same except for Content-Type
      json_headers = json_result[:headers].dup
      module_headers = module_result[:headers].dup

      json_headers.delete('Content-Type')
      module_headers.delete('Content-Type')

      expect(json_headers).to eq(module_headers)
    end
  end

  describe '#render_jsonp' do
    let(:callback_name) { 'myCallback' }

    it 'returns JSONP response with correct content type' do
      result = endpoint.render_jsonp(template_name, callback_name)

      expect(result[:content_type]).to eq('application/javascript')
      expect(result[:content]).to start_with("#{callback_name}(")
      expect(result[:content]).to end_with(');')
    end

    it 'wraps JSON data in callback function' do
      result = endpoint.render_jsonp(template_name, callback_name)

      # Extract JSON from JSONP
      json_part = result[:content].match(/myCallback\((.*)\);$/)[1]
      parsed_json = JSON.parse(json_part)

      expect(parsed_json).to have_key('userData')
      expect(parsed_json).to have_key('config')
    end

    it 'handles different callback names' do
      result = endpoint.render_jsonp(template_name, 'customCallback')

      expect(result[:content]).to start_with('customCallback(')
    end
  end

  describe '#data_changed?' do
    it 'returns false for same data' do
      etag = endpoint.calculate_etag(template_name)

      changed = endpoint.data_changed?(template_name, etag)

      expect(changed).to be false
    end

    it 'returns true for different ETags' do
      different_etag = 'different-etag-value'

      changed = endpoint.data_changed?(template_name, different_etag)

      expect(changed).to be true
    end
  end

  describe '#calculate_etag' do
    it 'returns consistent ETag for same data' do
      etag1 = endpoint.calculate_etag(template_name)
      etag2 = endpoint.calculate_etag(template_name)

      expect(etag1).to eq(etag2)
      expect(etag1).to be_a(String)
      expect(etag1.length).to eq(32)  # MD5 hash length
    end

    it 'returns different ETag for different data' do
      # Calculate first ETag
      etag1 = endpoint.calculate_etag(template_name)

      # Mock different data and calculate second ETag
      allow(Rhales::HydrationDataAggregator).to receive(:new).and_return(
        double('Aggregator',
          merged_data: { 'userData' => { user: 'jane' } },
          collect_from_template: nil
        )
      )

      etag2 = endpoint.calculate_etag(template_name)

      expect(etag1).not_to eq(etag2)
    end
  end

  describe 'error handling' do
    it 'handles template processing errors gracefully' do
      # Mock an error in the aggregation process
      allow(Rhales::HydrationDataAggregator).to receive(:new).and_raise(StandardError.new('Test error'))

      result = endpoint.render_json(template_name)

      parsed_content = JSON.parse(result[:content])
      expect(parsed_content).to have_key('error')
      expect(parsed_content['error']['message']).to include('Failed to process template data: Test error')
      expect(parsed_content['error']['template']).to eq(template_name)
      expect(parsed_content['error']).to have_key('timestamp')
    end

    it 'includes error details in error response' do
      allow(Rhales::HydrationDataAggregator).to receive(:new).and_raise(StandardError.new('Specific error'))

      result = endpoint.render_json(template_name)

      parsed_content = JSON.parse(result[:content])
      expect(parsed_content['error']['message']).to include('Specific error')
      expect(parsed_content['error']['template']).to eq(template_name)
    end

    it 'handles JSON serialization errors' do
      # Mock data that can't be serialized to JSON
      circular_data = {}
      circular_data[:self] = circular_data

      allow(Rhales::HydrationDataAggregator).to receive(:new).and_return(
        double('Aggregator',
          merged_data: circular_data,
          collect_from_template: nil
        )
      )

      expect {
        endpoint.render_json(template_name)
      }.not_to raise_error
    end
  end

  describe 'context handling' do
    context 'with existing context' do
      it 'merges additional context with existing context' do
        additional_context = { extra_data: 'test' }

        # Expect the context class to be instantiated with merged data
        expect(context.class).to receive(:new).with(context.to_h.merge(additional_context)).and_return(context)

        endpoint.render_json(template_name, additional_context)
      end
    end

    context 'without existing context' do
      let(:endpoint_no_context) { described_class.new(config, nil) }

      it 'creates minimal context with additional data' do
        additional_context = { extra_data: 'test' }

        expect(Rhales::Context).to receive(:new).with(additional_context).and_return(context)

        endpoint_no_context.render_json(template_name, additional_context)
      end
    end
  end

  describe 'caching configuration' do
    it 'respects custom cache TTL' do
      config.hydration.api_cache_ttl = 600

      result = endpoint.render_json(template_name)

      expect(result[:headers]['Cache-Control']).to include('max-age=600')
    end

    it 'handles nil cache TTL' do
      config.hydration.api_cache_ttl = nil

      result = endpoint.render_json(template_name)

      expect(result[:headers]['Cache-Control']).to include('max-age=300')  # Default fallback
    end
  end

  describe 'CORS configuration' do
    it 'respects custom CORS origin' do
      config.hydration.cors_origin = 'https://example.com'

      result = endpoint.render_json(template_name)

      expect(result[:headers]['Access-Control-Allow-Origin']).to eq('https://example.com')
    end

    it 'handles nil CORS origin with default' do
      config.hydration.cors_origin = nil

      result = endpoint.render_json(template_name)

      expect(result[:headers]['Access-Control-Allow-Origin']).to eq('*')
    end
  end
end
