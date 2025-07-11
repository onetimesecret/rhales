require 'spec_helper'

RSpec.describe Rhales::LinkBasedInjectionDetector do
  let(:hydration_config) do
    config = Rhales::HydrationConfiguration.new
    config.api_endpoint_path = '/api/hydration'
    config.link_crossorigin = true
    config.lazy_mount_selector = '#app'
    config
  end

  let(:detector) { described_class.new(hydration_config) }

  describe '#generate_for_strategy' do
    let(:template_name) { 'test_template' }
    let(:window_attr) { 'myData' }
    let(:nonce) { 'test-nonce-123' }

    context 'with :link strategy' do
      it 'generates basic link tag and manual fetch script' do
        result = detector.generate_for_strategy(:link, template_name, window_attr, nonce)

        expect(result).to include('<link href="/api/hydration/test_template" type="application/json">')
        expect(result).to include('data-hydration-target="myData"')
        expect(result).to include('nonce="test-nonce-123"')
        expect(result).to include('window.__rhales__.loadData')
      end

      it 'works without nonce' do
        result = detector.generate_for_strategy(:link, template_name, window_attr, nil)

        expect(result).to include('<link href="/api/hydration/test_template" type="application/json">')
        expect(result).not_to include('nonce=')
      end
    end

    context 'with :prefetch strategy' do
      it 'generates prefetch link tag and background fetch script' do
        result = detector.generate_for_strategy(:prefetch, template_name, window_attr, nonce)

        expect(result).to include('<link rel="prefetch" href="/api/hydration/test_template" as="fetch" crossorigin>')
        expect(result).to include('data-hydration-target="myData"')
        expect(result).to include('nonce="test-nonce-123"')
        expect(result).to include('window.__rhales__.loadPrefetched')
      end

      it 'respects crossorigin configuration' do
        hydration_config.link_crossorigin = false
        result = detector.generate_for_strategy(:prefetch, template_name, window_attr, nonce)

        expect(result).to include('<link rel="prefetch" href="/api/hydration/test_template" as="fetch">')
        expect(result).not_to include('crossorigin')
      end
    end

    context 'with :preload strategy' do
      it 'generates preload link tag and immediate fetch script' do
        result = detector.generate_for_strategy(:preload, template_name, window_attr, nonce)

        expect(result).to include('<link rel="preload" href="/api/hydration/test_template" as="fetch" crossorigin>')
        expect(result).to include('data-hydration-target="myData"')
        expect(result).to include('nonce="test-nonce-123"')
        expect(result).to include('fetch(\'/api/hydration/test_template\')')
        expect(result).to include('window.myData = data')
        expect(result).to include('rhales:hydrated')
      end

      it 'includes error handling' do
        result = detector.generate_for_strategy(:preload, template_name, window_attr, nonce)

        expect(result).to include('.catch(err => console.error(\'Rhales hydration error:\', err))')
      end
    end

    context 'with :modulepreload strategy' do
      it 'generates modulepreload link tag and ES module script' do
        result = detector.generate_for_strategy(:modulepreload, template_name, window_attr, nonce)

        expect(result).to include('<link rel="modulepreload" href="/api/hydration/test_template.js">')
        expect(result).to include('type="module"')
        expect(result).to include('data-hydration-target="myData"')
        expect(result).to include('nonce="test-nonce-123"')
        expect(result).to include('import data from \'/api/hydration/test_template.js\'')
        expect(result).to include('window.myData = data')
        expect(result).to include('rhales:hydrated')
      end

      it 'uses .js extension for module endpoint' do
        result = detector.generate_for_strategy(:modulepreload, template_name, window_attr, nonce)

        expect(result).to include('/api/hydration/test_template.js')
      end
    end

    context 'with :lazy strategy' do
      it 'generates intersection observer script without link tag' do
        result = detector.generate_for_strategy(:lazy, template_name, window_attr, nonce)

        expect(result).not_to include('<link')
        expect(result).to include('data-hydration-target="myData"')
        expect(result).to include('data-lazy-src="/api/hydration/test_template"')
        expect(result).to include('nonce="test-nonce-123"')
        expect(result).to include('IntersectionObserver')
        expect(result).to include('document.querySelector(\'#app\')')
      end

      it 'respects configured mount selector' do
        hydration_config.lazy_mount_selector = '#main-content'
        result = detector.generate_for_strategy(:lazy, template_name, window_attr, nonce)

        expect(result).to include('document.querySelector(\'#main-content\')')
      end

      it 'handles DOM ready states' do
        result = detector.generate_for_strategy(:lazy, template_name, window_attr, nonce)

        expect(result).to include('document.readyState === \'loading\'')
        expect(result).to include('DOMContentLoaded')
        expect(result).to include('window.__rhales__.initLazyLoading')
      end

      it 'includes error handling and warnings' do
        result = detector.generate_for_strategy(:lazy, template_name, window_attr, nonce)

        expect(result).to include('console.warn(\'Rhales: Mount element')
        expect(result).to include('.catch(err => console.error(\'Rhales lazy hydration error:\', err))')
      end
    end

    context 'with unsupported strategy' do
      it 'raises ArgumentError for unknown strategy' do
        expect {
          detector.generate_for_strategy(:unknown, template_name, window_attr, nonce)
        }.to raise_error(ArgumentError, /Unsupported link strategy: unknown/)
      end
    end

    context 'with different API endpoint configurations' do
      it 'respects custom API endpoint path' do
        hydration_config.api_endpoint_path = '/custom/api/path'
        result = detector.generate_for_strategy(:preload, template_name, window_attr, nonce)

        expect(result).to include('/custom/api/path/test_template')
      end

      it 'handles API endpoint path without leading slash' do
        hydration_config.api_endpoint_path = 'api/hydration'
        result = detector.generate_for_strategy(:preload, template_name, window_attr, nonce)

        expect(result).to include('api/hydration/test_template')
      end
    end

    context 'with special characters in template names' do
      it 'handles template names with underscores' do
        result = detector.generate_for_strategy(:preload, 'user_profile', window_attr, nonce)

        expect(result).to include('/api/hydration/user_profile')
      end

      it 'handles template names with dashes' do
        result = detector.generate_for_strategy(:preload, 'user-profile', window_attr, nonce)

        expect(result).to include('/api/hydration/user-profile')
      end
    end

    context 'with different window attributes' do
      it 'handles camelCase window attributes' do
        result = detector.generate_for_strategy(:preload, template_name, 'userData', nonce)

        expect(result).to include('data-hydration-target="userData"')
        expect(result).to include('window.userData = data')
      end

      it 'handles snake_case window attributes' do
        result = detector.generate_for_strategy(:preload, template_name, 'user_data', nonce)

        expect(result).to include('data-hydration-target="user_data"')
        expect(result).to include('window.user_data = data')
      end
    end

    context 'JavaScript utilities' do
      it 'includes __rhales__ namespace initialization' do
        result = detector.generate_for_strategy(:link, template_name, window_attr, nonce)

        expect(result).to include('window.__rhales__ = window.__rhales__ || {}')
      end

      it 'includes event dispatching for active strategies' do
        [:preload, :modulepreload].each do |strategy|
          result = detector.generate_for_strategy(strategy, template_name, window_attr, nonce)

          expect(result).to include('window.dispatchEvent(new CustomEvent(\'rhales:hydrated\'')
          expect(result).to include('detail: { target: \'myData\', data: data }')
        end
      end

      it 'does not include events for passive strategies' do
        [:link, :prefetch].each do |strategy|
          result = detector.generate_for_strategy(strategy, template_name, window_attr, nonce)

          expect(result).not_to include('rhales:hydrated')
        end
      end
    end
  end
end
