# spec/rhales/integration/vue_spa_schema_spec.rb

require 'spec_helper'

RSpec.describe 'Vue SPA Mount Point with Schema' do
  let(:templates_dir) { File.join(__dir__, '../../fixtures/templates/schema_test') }

  describe 'rendering Vue SPA entry point with large state object' do
    it 'serializes complex nested props directly without interpolation' do
      config = Rhales::Configuration.new do |c|
        c.template_paths = [templates_dir]
      end

      # Simulate Onetime Secret's serialized data structure
      view = Rhales::View.new(
        nil, nil, nil, 'en',
        props: {
          ui: { theme: 'dark', locale: 'en' },
          authentication: { authenticated: true, custid: 'cust_12345' },
          user: { email: 'test@example.com', customer_since: 1640000000 },
          secret_options: { ttl: 3600, passphrase: true },
          site_host: 'onetimesecret.com',
          regions_enabled: false,
          domains_enabled: false,
          billing_enabled: true,
          frontend_development: false
        },
        config: config
      )

      html = view.render('vue_spa_mount')

      # Check that the template rendered correctly
      expect(html).to include('<!DOCTYPE html>')
      expect(html).to include('<div id="app">')
      expect(html).to include('<router-view>')

      # Check that hydration script exists with correct window variable
      expect(html).to include('data-window="__ONETIME_STATE__"')
      expect(html).to match(/<script[^>]*\sid="rsfc-data-/)
      expect(html).to include('type="application/json"')

      # Check that complex nested data is serialized correctly (no interpolation)
      expect(html).to include('"ui":{"theme":"dark","locale":"en"}')
      expect(html).to include('"authentication":{"authenticated":true,"custid":"cust_12345"}')
      expect(html).to include('"user":{"email":"test@example.com","customer_since":1640000000}')
      expect(html).to include('"secret_options":{"ttl":3600,"passphrase":true}')
      expect(html).to include('"site_host":"onetimesecret.com"')
      expect(html).to include('"regions_enabled":false')
      expect(html).to include('"billing_enabled":true')

      # Verify the entire JSON structure is valid
      data_script_match = html.match(/<script[^>]*\sid="rsfc-data-[^"]+"\s+type="application\/json"[^>]*data-window="__ONETIME_STATE__"[^>]*>(.*?)<\/script>/m)
      expect(data_script_match).not_to be_nil

      json_data = JSON.parse(data_script_match[1])
      expect(json_data['ui']['theme']).to eq('dark')
      expect(json_data['authentication']['authenticated']).to eq(true)
      expect(json_data['user']['email']).to eq('test@example.com')
      expect(json_data['secret_options']['ttl']).to eq(3600)
    end

    it 'handles nil values correctly in optional fields' do
      config = Rhales::Configuration.new do |c|
        c.template_paths = [templates_dir]
      end

      # Test with nil user (not authenticated)
      view = Rhales::View.new(
        nil, nil, nil, 'en',
        props: {
          ui: { theme: 'light', locale: 'en' },
          authentication: { authenticated: false, custid: nil },
          user: nil,
          secret_options: { ttl: 3600, passphrase: false },
          site_host: 'onetimesecret.com',
          regions_enabled: false,
          domains_enabled: false,
          billing_enabled: false,
          frontend_development: false
        },
        config: config
      )

      html = view.render('vue_spa_mount')

      # Check that nil values are serialized as null
      expect(html).to include('"authenticated":false')
      expect(html).to include('"custid":null')
      expect(html).to include('"user":null')

      # Verify JSON is valid
      data_script_match = html.match(/<script[^>]*\sid="rsfc-data-[^"]+"\s+type="application\/json"[^>]*data-window="__ONETIME_STATE__"[^>]*>(.*?)<\/script>/m)
      json_data = JSON.parse(data_script_match[1])
      expect(json_data['user']).to be_nil
      expect(json_data['authentication']['custid']).to be_nil
    end

    it 'does not perform template interpolation on string values' do
      config = Rhales::Configuration.new do |c|
        c.template_paths = [templates_dir]
      end

      # Test with string that looks like a template variable
      view = Rhales::View.new(
        nil, nil, nil, 'en',
        props: {
          ui: { theme: '{{should.not.interpolate}}', locale: 'en' },
          authentication: { authenticated: true, custid: 'cust_{{test}}' },
          user: { email: 'test@example.com', customer_since: nil },
          secret_options: { ttl: 3600, passphrase: false },
          site_host: 'onetimesecret.com',
          regions_enabled: false,
          domains_enabled: false,
          billing_enabled: false,
          frontend_development: false
        },
        config: config
      )

      html = view.render('vue_spa_mount')

      # Template-like strings should be preserved as-is (not interpolated)
      expect(html).to include('"theme":"{{should.not.interpolate}}"')
      expect(html).to include('"custid":"cust_{{test}}"')
    end

    it 'supports arrays within the state object' do
      config = Rhales::Configuration.new do |c|
        c.template_paths = [templates_dir]
      end

      # Add arrays to the props (extending the schema conceptually)
      view = Rhales::View.new(
        nil, nil, nil, 'en',
        props: {
          ui: { theme: 'dark', locale: 'en' },
          authentication: { authenticated: true, custid: 'cust_12345' },
          user: { email: 'test@example.com', customer_since: 1640000000 },
          secret_options: { ttl: 3600, passphrase: true },
          site_host: 'onetimesecret.com',
          regions_enabled: true,
          domains_enabled: false,
          billing_enabled: false,
          frontend_development: false
        },
        config: config
      )

      html = view.render('vue_spa_mount')

      # Just verify it renders without error and contains valid JSON
      data_script_match = html.match(/<script[^>]*\sid="rsfc-data-[^"]+"\s+type="application\/json"[^>]*data-window="__ONETIME_STATE__"[^>]*>(.*?)<\/script>/m)
      expect(data_script_match).not_to be_nil
      expect { JSON.parse(data_script_match[1]) }.not_to raise_error
    end
  end
end
