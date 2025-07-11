require 'spec_helper'

RSpec.describe 'Hydration Strategies Integration' do
  let(:base_config) do
    config = Rhales::Configuration.new
    config.hydration.fallback_to_late = true
    config.hydration.fallback_when_unsafe = true
    config.hydration.api_endpoint_path = '/api/hydration'
    config.hydration.api_cache_enabled = true
    config.hydration.cors_enabled = true
    config
  end

  let(:context) do
    double('Context',
      to_h: {
        user: { name: 'John Doe', role: 'admin' },
        app_config: { theme: 'dark', api_url: 'https://api.example.com' }
      },
      get: proc { |key|
        data = { user: { name: 'John Doe' }, app_config: { theme: 'dark' } }
        key.split('.').reduce(data) { |obj, k| obj[k.to_sym] }
      },
      props: {
        user: { name: 'John Doe', role: 'admin' },
        app_config: { theme: 'dark', api_url: 'https://api.example.com' }
      },
      req: nil,
      sess: nil,
      cust: nil,
      locale: 'en',
      class: double('ContextClass', for_view: double('Context'))
    )
  end

  let(:react_app_template) do
    <<~HTML
      <!DOCTYPE html>
      <html>
      <head>
        <title>React App</title>
        <link rel="stylesheet" href="/assets/app.css">
        <meta name="viewport" content="width=device-width, initial-scale=1">
      </head>
      <body>
        <noscript>You need to enable JavaScript to run this app.</noscript>
        <div id="root"></div>
        <script src="/assets/react.min.js"></script>
        <script src="/assets/app.js"></script>
      </body>
      </html>
    HTML
  end

  let(:vue_app_template) do
    <<~HTML
      <!DOCTYPE html>
      <html>
      <head>
        <title>Vue App</title>
        <script src="https://unpkg.com/vue@3/dist/vue.global.js"></script>
      </head>
      <body>
        <div id="app">
          <h1>{{ message }}</h1>
        </div>
        <script>
          const { createApp } = Vue;
          createApp({
            data() { return { message: 'Hello Vue!' } }
          }).mount('#app');
        </script>
      </body>
      </html>
    HTML
  end

  let(:complex_spa_template) do
    <<~HTML
      <!DOCTYPE html>
      <html>
      <head>
        <meta charset="utf-8">
        <title>Complex SPA</title>
        <link rel="preload" href="/fonts/main.woff2" as="font" type="font/woff2" crossorigin>
        <style>
          .loading { display: flex; justify-content: center; }
          .app-container { max-width: 1200px; margin: 0 auto; }
        </style>
      </head>
      <body>
        <div class="loading">Loading...</div>
        <div id="app" class="app-container"></div>
        <div data-mount="secondary" class="sidebar"></div>
        <footer>
          <script>
            // Analytics tracking
            console.log('Page loaded');
          </script>
        </footer>
      </body>
      </html>
    HTML
  end

  # Mock the necessary classes to avoid dependency issues
  before do
    # Mock View class
    composition_double = double('ViewComposition', resolve!: nil, templates: { 'test_template' => double('Document') })
    view_double = double('View', build_view_composition: composition_double)
    allow(view_double).to receive(:send).with(:build_view_composition, anything).and_return(composition_double)
    allow(Rhales::View).to receive(:new).and_return(view_double)

    # Mock HydrationDataAggregator
    aggregator_double = double('Aggregator')
    allow(aggregator_double).to receive(:aggregate).with(anything).and_return({
      'userData' => { name: 'John', role: 'admin' },
      'appConfig' => { theme: 'dark', api_url: 'https://api.example.com' }
    })
    allow(Rhales::HydrationDataAggregator).to receive(:new).and_return(aggregator_double)
  end

  describe 'Traditional Injection Strategies' do
    describe ':late strategy (backwards compatibility)' do
      let(:config) { base_config.tap { |c| c.hydration.injection_strategy = :late } }

      it 'injects before closing body tag in React app' do
        injector = Rhales::HydrationInjector.new(config.hydration, 'react_app')
        hydration_script = '<script>window.userData = {"name": "John"};</script>'

        result = injector.inject(react_app_template, hydration_script)

        expect(result).to include(hydration_script)
        expect(result.index(hydration_script)).to be < result.index('</body>')
        # Should be after all existing scripts
        expect(result.index(hydration_script)).to be > result.index('/assets/app.js')
      end

      it 'handles templates without body tag gracefully' do
        template_no_body = '<div>Content</div>'
        injector = Rhales::HydrationInjector.new(config.hydration, 'fragment')
        hydration_script = '<script>window.data = {};</script>'

        result = injector.inject(template_no_body, hydration_script)

        expect(result).to end_with("\n#{hydration_script}")
      end
    end

    describe ':early strategy (mount point injection)' do
      let(:config) { base_config.tap { |c| c.hydration.injection_strategy = :early } }

      it 'injects before React root mount point' do
        detector = Rhales::MountPointDetector.new
        mount_point = detector.detect(react_app_template)

        expect(mount_point).not_to be_nil
        expect(mount_point[:selector]).to eq('#root')

        injector = Rhales::HydrationInjector.new(config.hydration, 'react_app')
        hydration_script = '<script>window.reactData = {"user": "John"};</script>'

        result = injector.inject(react_app_template, hydration_script, mount_point)

        expect(result).to include(hydration_script)
        expect(result.index(hydration_script)).to be < result.index('<div id="root">')
      end

      it 'finds earliest mount point in complex SPA' do
        detector = Rhales::MountPointDetector.new
        mount_point = detector.detect(complex_spa_template)

        expect(mount_point).not_to be_nil
        expect(mount_point[:selector]).to eq('#app')  # Should find #app before [data-mount]

        injector = Rhales::HydrationInjector.new(config.hydration, 'complex_spa')
        hydration_script = '<script>window.spaData = {"config": true};</script>'

        result = injector.inject(complex_spa_template, hydration_script, mount_point)

        expect(result.index(hydration_script)).to be < result.index('<div id="app"')
      end

      it 'falls back to late injection when no mount point found' do
        template_no_mount = '<html><body><p>No mount points here</p></body></html>'

        injector = Rhales::HydrationInjector.new(config.hydration, 'no_mount')
        hydration_script = '<script>window.fallbackData = {};</script>'

        result = injector.inject(template_no_mount, hydration_script, nil)

        expect(result).to include(hydration_script)
        expect(result.index(hydration_script)).to be < result.index('</body>')
      end
    end

    describe ':earliest strategy (head injection)' do
      let(:config) { base_config.tap { |c| c.hydration.injection_strategy = :earliest } }

      it 'injects in head section after link tags' do
        injector = Rhales::HydrationInjector.new(config.hydration, 'react_app')
        hydration_script = '<script>window.earlyData = {"loaded": true};</script>'

        result = injector.inject(react_app_template, hydration_script)

        expect(result).to include(hydration_script)
        head_end = result.index('</head>')
        injection_pos = result.index('window.earlyData')

        expect(injection_pos).to be < head_end
        # Should be after link stylesheet tag (earliest detector prioritizes after links)
        expect(injection_pos).to be > result.index('href="/assets/app.css"')
      end

      it 'handles complex head section with preload links' do
        injector = Rhales::HydrationInjector.new(config.hydration, 'complex_spa')
        hydration_script = '<script>window.complexData = {"theme": "dark"};</script>'

        result = injector.inject(complex_spa_template, hydration_script)

        expect(result).to include(hydration_script)
        # Should inject after preload link but before </head>
        preload_end = result.index('crossorigin>')
        injection_pos = result.index('window.complexData')
        head_end = result.index('</head>')

        expect(injection_pos).to be > preload_end
        expect(injection_pos).to be < head_end
      end

      it 'falls back to late injection when head injection fails' do
        template_no_head = '<html><body><div id="app"></div></body></html>'

        injector = Rhales::HydrationInjector.new(config.hydration, 'no_head')
        hydration_script = '<script>window.fallbackEarly = {};</script>'

        result = injector.inject(template_no_head, hydration_script)

        expect(result).to include(hydration_script)
        expect(result.index(hydration_script)).to be < result.index('</body>')
      end
    end
  end

  describe 'Link-Based Strategies' do
    let(:merged_data) do
      {
        'userData' => { name: 'John', role: 'admin' },
        'appConfig' => { theme: 'dark', api_url: 'https://api.example.com' }
      }
    end
    let(:nonce) { 'test-nonce-abc123' }

    describe ':preload strategy' do
      let(:config) { base_config.tap { |c| c.hydration.injection_strategy = :preload } }

      it 'generates preload links with immediate fetch scripts' do
        injector = Rhales::HydrationInjector.new(config.hydration, 'react_app')

        result = injector.inject_link_based_strategy(react_app_template, merged_data, nonce)

        # Should have preload links for each data attribute
        expect(result).to include('<link rel="preload" href="/api/hydration/react_app" as="fetch" crossorigin>')
        expect(result).to include('data-hydration-target="userData"')
        expect(result).to include('data-hydration-target="appConfig"')

        # Should have immediate fetch scripts
        expect(result).to include('fetch(\'/api/hydration/react_app\')')
        expect(result).to include("window['userData'] = data;")
        expect(result).to include("window['appConfig'] = data;")

        # Should include nonce for CSP compliance
        expect(result).to include('nonce="test-nonce-abc123"')

        # Should dispatch ready events
        expect(result).to include('rhales:hydrated')
      end

      it 'injects in head section for optimal performance' do
        injector = Rhales::HydrationInjector.new(config.hydration, 'react_app')

        result = injector.inject_link_based_strategy(react_app_template, merged_data, nonce)

        preload_pos = result.index('<link rel="preload"')
        head_end = result.index('</head>')

        expect(preload_pos).to be < head_end
        # Should be after existing link tags
        expect(preload_pos).to be > result.index('rel="stylesheet"')
      end
    end

    describe ':prefetch strategy' do
      let(:config) { base_config.tap { |c| c.hydration.injection_strategy = :prefetch } }

      it 'generates prefetch links for future page loads' do
        injector = Rhales::HydrationInjector.new(config.hydration, 'vue_app')

        result = injector.inject_link_based_strategy(vue_app_template, merged_data, nonce)

        expect(result).to include('<link rel="prefetch" href="/api/hydration/vue_app" as="fetch" crossorigin>')
        expect(result).to include('loadPrefetched')  # Should use prefetch loading function
        expect(result).not_to include('window.userData = data;')  # Should not auto-load
      end
    end

    describe ':modulepreload strategy' do
      let(:config) { base_config.tap { |c| c.hydration.injection_strategy = :modulepreload } }

      it 'generates ES module imports with .js extension' do
        injector = Rhales::HydrationInjector.new(config.hydration, 'react_app')

        result = injector.inject_link_based_strategy(react_app_template, merged_data, nonce)

        expect(result).to include('<link rel="modulepreload" href="/api/hydration/react_app.js">')
        expect(result).to include('type="module"')
        expect(result).to include('import data from \'/api/hydration/react_app.js\';')
        expect(result).to include("window['userData'] = data;")
        expect(result).to include("window['appConfig'] = data;")
      end
    end

    describe ':lazy strategy' do
      let(:config) { base_config.tap { |c| c.hydration.injection_strategy = :lazy } }

      it 'generates intersection observer for lazy loading' do
        injector = Rhales::HydrationInjector.new(config.hydration, 'complex_spa')

        result = injector.inject_link_based_strategy(complex_spa_template, merged_data, nonce)

        expect(result).to include('IntersectionObserver')
        expect(result).to include('data-lazy-src="/api/hydration/complex_spa"')
        expect(result).to include('querySelector(\'#app\')')  # Default mount selector
        expect(result).to include('entry.isIntersecting')
        expect(result).not_to include('<link rel="prefetch"')  # No preload links for lazy
      end

      it 'uses custom mount selector when configured' do
        config.hydration.lazy_mount_selector = '.app-container'
        injector = Rhales::HydrationInjector.new(config.hydration, 'complex_spa')

        result = injector.inject_link_based_strategy(complex_spa_template, merged_data, nonce)

        expect(result).to include('querySelector(\'.app-container\')')
      end
    end

    describe ':link strategy' do
      let(:config) { base_config.tap { |c| c.hydration.injection_strategy = :link } }

      it 'generates basic link references with manual loading' do
        injector = Rhales::HydrationInjector.new(config.hydration, 'vue_app')

        result = injector.inject_link_based_strategy(vue_app_template, merged_data, nonce)

        expect(result).to include('<link href="/api/hydration/vue_app" type="application/json">')
        expect(result).to include('loadData')  # Manual loading function
        expect(result).to include('window.__rhales__.loadData(\'userData\', \'/api/hydration/vue_app\');')  # Calls load function
        expect(result).to include('window.__rhales__.loadData(\'appConfig\', \'/api/hydration/vue_app\');')  # Calls load function
        expect(result).not_to include('window.userData = data;')  # No automatic assignment
      end
    end
  end

  describe 'API Endpoint Integration' do
    let(:config) { base_config.tap { |c| c.hydration.injection_strategy = :preload } }
    let(:endpoint) { Rhales::HydrationEndpoint.new(config, context) }

    describe 'JSON endpoint' do
      it 'generates proper JSON response with headers' do
        result = endpoint.render_json('react_app')

        expect(result[:content_type]).to eq('application/json')
        expect(result[:headers]['Content-Type']).to eq('application/json')
        expect(result[:headers]['Cache-Control']).to include('public, max-age')
        expect(result[:headers]['ETag']).to match(/^"[a-f0-9]{32}"$/)

        # When CORS enabled
        expect(result[:headers]['Access-Control-Allow-Origin']).to eq('*')

        parsed_content = JSON.parse(result[:content])
        expect(parsed_content).to have_key('userData')
        expect(parsed_content).to have_key('appConfig')
      end
    end

    describe 'ES Module endpoint' do
      it 'generates valid ES module syntax' do
        result = endpoint.render_module('vue_app')

        expect(result[:content_type]).to eq('text/javascript')
        expect(result[:content]).to start_with('export default ')
        expect(result[:content]).to end_with(';')
        expect(result[:content]).to match(/^export default \{.*\};$/)
      end
    end

    describe 'JSONP endpoint' do
      it 'wraps data in callback function' do
        result = endpoint.render_jsonp('complex_spa', 'myCallback')

        expect(result[:content_type]).to eq('application/javascript')
        expect(result[:content]).to start_with('myCallback(')
        expect(result[:content]).to end_with(');')

        # Extract and validate JSON
        json_part = result[:content].match(/myCallback\((.*)\);$/)[1]
        parsed_json = JSON.parse(json_part)
        expect(parsed_json).to have_key('userData')
      end
    end
  end

  describe 'Error Handling and Edge Cases' do
    let(:config) { base_config.tap { |c| c.hydration.injection_strategy = :early } }

    it 'handles malformed HTML gracefully' do
      malformed_html = '<html><head><title>Test</head><body><div id="app">'

      detector = Rhales::MountPointDetector.new
      mount_point = detector.detect(malformed_html)

      injector = Rhales::HydrationInjector.new(config.hydration, 'malformed')
      hydration_script = '<script>window.data = {};</script>'

      expect {
        result = injector.inject(malformed_html, hydration_script, mount_point)
        expect(result).to include(hydration_script)
      }.not_to raise_error
    end

    it 'handles empty or nil hydration content' do
      injector = Rhales::HydrationInjector.new(config.hydration, 'empty')

      expect(injector.inject(react_app_template, nil)).to eq(react_app_template)
      expect(injector.inject(react_app_template, '')).to eq(react_app_template)
      expect(injector.inject(react_app_template, "   \n  ")).to eq(react_app_template)
    end

    it 'falls back gracefully when detectors fail' do
      # Mock detector to raise an error
      allow_any_instance_of(Rhales::EarliestInjectionDetector).to receive(:detect).and_raise(StandardError.new('Detector error'))

      config.hydration.injection_strategy = :earliest
      injector = Rhales::HydrationInjector.new(config.hydration, 'error_test')
      hydration_script = '<script>window.errorData = {};</script>'

      result = injector.inject(react_app_template, hydration_script)

      # Should fall back to late injection
      expect(result).to include(hydration_script)
      expect(result.index(hydration_script)).to be < result.index('</body>')
    end

    it 'respects template disable lists' do
      config.hydration.disable_early_for_templates = ['react_app']
      config.hydration.injection_strategy = :earliest

      injector = Rhales::HydrationInjector.new(config.hydration, 'react_app')
      hydration_script = '<script>window.disabledData = {};</script>'

      result = injector.inject(react_app_template, hydration_script)

      # Should fall back to late injection
      expect(result.index(hydration_script)).to be < result.index('</body>')
    end
  end

  describe 'Performance Characteristics' do
    let(:config) { base_config.dup }
    let(:large_template) do
      # Generate a large template with many elements
      elements = (1..1000).map { |i| "  <div class='item-#{i}'>Item #{i}</div>" }.join("\n")
      <<~HTML
        <!DOCTYPE html>
        <html>
        <head><title>Large App</title></head>
        <body>
        #{elements}
        <div id="app">Mount point</div>
        </body>
        </html>
      HTML
    end

    it 'handles large templates efficiently' do
      detector = Rhales::MountPointDetector.new

      start_time = Time.now
      mount_point = detector.detect(large_template)
      detection_time = Time.now - start_time

      expect(mount_point).not_to be_nil
      expect(detection_time).to be < 0.1  # Should complete in under 100ms

      config.hydration.injection_strategy = :early
      injector = Rhales::HydrationInjector.new(config.hydration, 'large_app')
      hydration_script = '<script>window.largeAppData = {};</script>'

      start_time = Time.now
      result = injector.inject(large_template, hydration_script, mount_point)
      injection_time = Time.now - start_time

      expect(result).to include(hydration_script)
      expect(injection_time).to be < 0.1  # Should complete in under 100ms
    end
  end

  describe 'Cross-Strategy Compatibility' do
    let(:config) { base_config.dup }

    it 'allows runtime strategy switching' do
      hydration_script = '<script>window.flexData = {};</script>'

      # Test late injection
      config.hydration.injection_strategy = :late
      late_injector = Rhales::HydrationInjector.new(config.hydration, 'flexible_app')
      late_result = late_injector.inject(react_app_template, hydration_script)

      # Test earliest injection
      config.hydration.injection_strategy = :earliest
      earliest_injector = Rhales::HydrationInjector.new(config.hydration, 'flexible_app')
      earliest_result = earliest_injector.inject(react_app_template, hydration_script)

      # Should inject in different positions
      late_pos = late_result.index(hydration_script)
      earliest_pos = earliest_result.index(hydration_script)

      expect(earliest_pos).to be < late_pos
      expect(late_result.index('</body>')).to be > late_pos
      expect(earliest_result.index('</head>')).to be > earliest_pos
    end

    it 'maintains consistent data output across strategies' do
      merged_data = { 'testData' => { value: 'consistent' } }
      nonce = 'test-nonce'

      [:preload, :prefetch, :modulepreload, :lazy, :link].each do |strategy|
        config.hydration.injection_strategy = strategy
        injector = Rhales::HydrationInjector.new(config.hydration, 'consistency_test')

        result = injector.inject_link_based_strategy(react_app_template, merged_data, nonce)

        # All strategies should reference the same endpoint
        expect(result).to include('/api/hydration/consistency_test')
        # All should include data target attributes
        expect(result).to include('data-hydration-target="testData"')
        # All should include the nonce
        expect(result).to include('nonce="test-nonce"')
      end
    end
  end
end
