require 'spec_helper'

RSpec.describe Rhales::HydrationInjector do
  let(:hydration_config) do
    config = Rhales::HydrationConfiguration.new
    config.injection_strategy = :late
    config.fallback_to_late = true
    config.fallback_when_unsafe = true
    config.disable_early_for_templates = []
    config.api_endpoint_path = '/api/hydration'
    config.link_crossorigin = true
    config.lazy_mount_selector = '#app'
    config
  end

  let(:template_name) { 'test_template' }
  let(:injector) { described_class.new(hydration_config, template_name) }

  let(:simple_html) do
    <<~HTML
      <html>
      <head>
        <title>Test</title>
        <link rel="stylesheet" href="style.css">
        <meta name="description" content="test">
      </head>
      <body>
        <div id="app"></div>
      </body>
      </html>
    HTML
  end

  let(:hydration_script) do
    <<~HTML
      <script id="rsfc-data-123" type="application/json">{"user": "john"}</script>
      <script nonce="test123">
      window.data = JSON.parse(document.getElementById('rsfc-data-123').textContent);
      </script>
    HTML
  end

  describe '#inject' do
    context 'with :earliest strategy' do
      before { hydration_config.injection_strategy = :earliest }

      it 'injects in head section for best performance' do
        result = injector.inject(simple_html, hydration_script)

        # Should inject after the link tag (earliest detector chooses after links)
        head_end_pos = result.index('</head>')
        injection_pos = result.index('rsfc-data-123')
        link_end = result.index('<link rel="stylesheet" href="style.css">') + 37  # link tag length

        expect(injection_pos).to be < head_end_pos
        expect(injection_pos).to be >= link_end
      end

      it 'falls back to late injection when earliest fails' do
        # HTML without head section
        html_without_head = '<html><body><div id="app"></div></body></html>'

        result = injector.inject(html_without_head, hydration_script)

        # Should fall back to late injection (before </body>)
        expect(result).to include(hydration_script.strip)
        expect(result).to include("</body>")
        expect(result.index(hydration_script.strip)).to be < result.index("</body>")
      end

      it 'respects template disable list' do
        hydration_config.disable_early_for_templates = ['test_template']

        result = injector.inject(simple_html, hydration_script)

        # Should fall back to late injection
        expect(result).to include(hydration_script.strip)
        expect(result).to include("</body>")
        expect(result.index(hydration_script.strip)).to be < result.index("</body>")
      end
    end

    context 'with :early strategy (existing behavior)' do
      before { hydration_config.injection_strategy = :early }

      it 'injects before mount points' do
        mount_point_data = { position: simple_html.index('<div id="app">'), selector: '#app' }

        result = injector.inject(simple_html, hydration_script, mount_point_data)

        app_div_pos = result.index('<div id="app">')
        injection_pos = result.index('rsfc-data-123')

        expect(injection_pos).to be < app_div_pos
      end

      it 'falls back to late when no mount point' do
        result = injector.inject(simple_html, hydration_script, nil)

        expect(result).to include(hydration_script.strip)
        expect(result).to include("</body>")
        expect(result.index(hydration_script.strip)).to be < result.index("</body>")
      end
    end

    context 'with :late strategy (existing behavior)' do
      before { hydration_config.injection_strategy = :late }

      it 'injects before closing body tag' do
        result = injector.inject(simple_html, hydration_script)

        # Should inject the script before </body>
        expect(result).to include(hydration_script.strip)
        expect(result.index(hydration_script.strip)).to be < result.index('</body>')
      end

      it 'appends to end when no body tag' do
        html_no_body = '<html><div id="app"></div></html>'

        result = injector.inject(html_no_body, hydration_script)

        # Should append with newline
        expect(result).to include(hydration_script.strip)
        expect(result).to match(/#{Regexp.escape(hydration_script.strip)}\s*$/)
      end
    end

    context 'with empty or nil hydration content' do
      it 'returns original template for nil hydration' do
        result = injector.inject(simple_html, nil)
        expect(result).to eq(simple_html)
      end

      it 'returns original template for empty hydration' do
        result = injector.inject(simple_html, '')
        expect(result).to eq(simple_html)
      end

      it 'returns original template for whitespace-only hydration' do
        result = injector.inject(simple_html, "   \n  \t  ")
        expect(result).to eq(simple_html)
      end
    end
  end

  describe '#inject_link_based_strategy' do
    let(:merged_data) do
      {
        'userData' => { user: 'john', role: 'admin' },
        'config' => { api_url: 'https://api.example.com' }
      }
    end
    let(:nonce) { 'test-nonce-123' }

    context 'with :preload strategy' do
      before { hydration_config.injection_strategy = :preload }

      it 'generates link tags for all window attributes' do
        result = injector.inject_link_based_strategy(simple_html, merged_data, nonce)

        expect(result).to include('<link rel="preload" href="/api/hydration/test_template" as="fetch" crossorigin>')
        expect(result).to include('data-hydration-target="userData"')
        expect(result).to include('data-hydration-target="config"')
        expect(result).to include('nonce="test-nonce-123"')
      end

      it 'uses earliest injection by default' do
        result = injector.inject_link_based_strategy(simple_html, merged_data, nonce)

        # Should inject in head section
        head_end_pos = result.index('</head>')
        injection_pos = result.index('<link rel="preload"')

        expect(injection_pos).to be < head_end_pos
      end

      it 'falls back to late injection when template disabled' do
        hydration_config.disable_early_for_templates = ['test_template']

        result = injector.inject_link_based_strategy(simple_html, merged_data, nonce)

        # Should inject before </body>
        expect(result).to include("crossorigin>")
        expect(result).to include("</body>")
        expect(result.index("crossorigin>")).to be < result.index("</body>")
      end
    end

    context 'with :lazy strategy' do
      before { hydration_config.injection_strategy = :lazy }

      it 'generates intersection observer scripts' do
        result = injector.inject_link_based_strategy(simple_html, merged_data, nonce)

        expect(result).to include('IntersectionObserver')
        expect(result).to include('data-lazy-src="/api/hydration/test_template"')
        expect(result).to include('data-hydration-target="userData"')
        expect(result).to include('data-hydration-target="config"')
        # Check for lazy-generated links, not original template links
        expect(result).not_to include('<link rel="prefetch"')  # No prefetch for lazy strategy
      end
    end

    context 'with :modulepreload strategy' do
      before { hydration_config.injection_strategy = :modulepreload }

      it 'generates modulepreload links with .js extension' do
        result = injector.inject_link_based_strategy(simple_html, merged_data, nonce)

        expect(result).to include('<link rel="modulepreload" href="/api/hydration/test_template.js">')
        expect(result).to include('type="module"')
        expect(result).to include('import data from \'/api/hydration/test_template.js\'')
      end
    end

    context 'with empty merged data' do
      it 'returns original template for nil data' do
        result = injector.inject_link_based_strategy(simple_html, nil, nonce)
        expect(result).to eq(simple_html)
      end

      it 'returns original template for empty data' do
        result = injector.inject_link_based_strategy(simple_html, {}, nonce)
        expect(result).to eq(simple_html)
      end
    end

    context 'with multiple window attributes' do
      let(:complex_merged_data) do
        {
          'userData' => { user: 'john' },
          'appConfig' => { theme: 'dark' },
          'apiData' => { endpoints: ['users', 'posts'] }
        }
      end

      it 'generates separate scripts for each window attribute' do
        hydration_config.injection_strategy = :preload
        result = injector.inject_link_based_strategy(simple_html, complex_merged_data, nonce)

        expect(result).to include('data-hydration-target="userData"')
        expect(result).to include('data-hydration-target="appConfig"')
        expect(result).to include('data-hydration-target="apiData"')

        # Should have multiple fetch calls
        expect(result.scan(/fetch\('\/api\/hydration\/test_template'\)/).length).to eq(3)
      end
    end
  end

  describe 'strategy validation' do
    it 'falls back to late injection for unknown strategies' do
      # Bypass validation by setting the instance variable directly
      hydration_config.instance_variable_set(:@injection_strategy, :unknown_strategy)

      result = injector.inject(simple_html, hydration_script)

      # Should default to late injection
      expect(result).to include(hydration_script.strip)
      expect(result).to include("</body>")
      expect(result.index(hydration_script.strip)).to be < result.index("</body>")
    end
  end

  describe 'integration with detectors' do
    it 'initializes EarliestInjectionDetector' do
      expect(injector.instance_variable_get(:@earliest_detector)).to be_a(Rhales::EarliestInjectionDetector)
    end

    it 'initializes LinkBasedInjectionDetector with config' do
      link_detector = injector.instance_variable_get(:@link_detector)
      expect(link_detector).to be_a(Rhales::LinkBasedInjectionDetector)
    end
  end

  describe 'error handling' do
    it 'handles detector failures gracefully' do
      # Mock a detector that raises an error
      allow_any_instance_of(Rhales::EarliestInjectionDetector).to receive(:detect).and_raise(StandardError.new('Test error'))

      hydration_config.injection_strategy = :earliest

      result = injector.inject(simple_html, hydration_script)

      # Should fall back to late injection
      expect(result).to include(hydration_script.strip)
      expect(result).to include("</body>")
      expect(result.index(hydration_script.strip)).to be < result.index("</body>")
    end

    it 'handles missing mount point gracefully' do
      # HTML without any mount points
      html_no_mount = '<html><head><title>Test</title></head><body><p>No mount point</p></body></html>'

      hydration_config.injection_strategy = :early

      result = injector.inject(html_no_mount, hydration_script, nil)

      # Should fall back to late injection
      expect(result).to include(hydration_script.strip)
      expect(result).to include("</body>")
      expect(result.index(hydration_script.strip)).to be < result.index("</body>")
    end
  end
end
