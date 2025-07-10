require 'spec_helper'

RSpec.describe Rhales::HydrationInjector do
  let(:config) { double('config') }
  let(:hydration_config) { double('hydration_config') }
  let(:injector) { described_class.new(config) }
  let(:template_html) { '<html><body><div id="app">Content</div></body></html>' }
  let(:hydration_html) { '<script>window.data = {"test": "value"};</script>' }

  before do
    allow(config).to receive(:hydration).and_return(hydration_config)
    allow(hydration_config).to receive(:injection_strategy).and_return(:late)
    allow(hydration_config).to receive(:fallback_to_late).and_return(true)
  end

  describe '#inject' do
    context 'with late injection strategy' do
      before do
        allow(hydration_config).to receive(:injection_strategy).and_return(:late)
      end

      it 'injects before </body> tag when present' do
        result = injector.inject(template_html, hydration_html)

        expect(result).to include(hydration_html)
        expect(result).to match(/#{Regexp.escape(hydration_html)}\s*<\/body>/)
      end

      it 'appends to end when no </body> tag' do
        html_without_body = '<div>Content</div>'
        result = injector.inject(html_without_body, hydration_html)

        expect(result).to end_with("\n#{hydration_html}")
      end

      it 'ignores mount point data in late mode' do
        mount_point = { selector: '#app', position: 20, matched: 'id="app"' }
        result = injector.inject(template_html, hydration_html, mount_point)

        expect(result).to match(/#{Regexp.escape(hydration_html)}\s*<\/body>/)
      end
    end

    context 'with early injection strategy' do
      before do
        allow(hydration_config).to receive(:injection_strategy).and_return(:early)
      end

      it 'injects before mount point when mount point data provided' do
        # Calculate actual position of the mount point in template_html
        actual_position = template_html.index('<div id="app">')
        mount_point = { selector: '#app', position: actual_position, matched: 'id="app"' }
        result = injector.inject(template_html, hydration_html, mount_point)

        # Should inject before the <div id="app"> element
        expect(result).to include("#{hydration_html}\n<div id=\"app\">")
      end

      it 'falls back to late injection when no mount point provided' do
        result = injector.inject(template_html, hydration_html, nil)

        expect(result).to match(/#{Regexp.escape(hydration_html)}\s*<\/body>/)
      end

      it 'respects fallback_to_late configuration' do
        allow(hydration_config).to receive(:fallback_to_late).and_return(false)
        result = injector.inject(template_html, hydration_html, nil)

        expect(result).to eq(template_html)
      end

      it 'handles mount point at beginning of document' do
        html = '<div id="app">Content</div>'
        mount_point = { selector: '#app', position: 0, matched: 'id="app"' }
        result = injector.inject(html, hydration_html, mount_point)

        expect(result).to start_with(hydration_html)
      end
    end

    context 'with empty or nil hydration HTML' do
      it 'returns original template when hydration is nil' do
        result = injector.inject(template_html, nil)

        expect(result).to eq(template_html)
      end

      it 'returns original template when hydration is empty' do
        result = injector.inject(template_html, '')

        expect(result).to eq(template_html)
      end

      it 'returns original template when hydration is whitespace only' do
        result = injector.inject(template_html, '   ')

        expect(result).to eq(template_html)
      end
    end

    context 'with invalid strategy' do
      before do
        allow(hydration_config).to receive(:injection_strategy).and_return(:invalid)
      end

      it 'defaults to late injection' do
        result = injector.inject(template_html, hydration_html)

        expect(result).to match(/#{Regexp.escape(hydration_html)}\s*<\/body>/)
      end
    end

    context 'with config that does not respond to hydration' do
      let(:simple_config) { double('simple_config') }
      let(:injector) { described_class.new(simple_config) }

      before do
        allow(simple_config).to receive(:respond_to?).with(:hydration).and_return(false)
      end

      it 'defaults to late injection strategy' do
        result = injector.inject(template_html, hydration_html)

        expect(result).to match(/#{Regexp.escape(hydration_html)}\s*<\/body>/)
      end
    end
  end

  describe 'edge cases' do
    context 'with complex mount point positioning' do
      it 'handles mount points with attributes' do
        html = '<div class="wrapper"><main id="app" data-test="value">Content</main></div>'
        mount_point = { selector: '#app', position: 21, matched: 'id="app"' }

        allow(hydration_config).to receive(:injection_strategy).and_return(:early)
        result = injector.inject(html, hydration_html, mount_point)

        expect(result).to include("#{hydration_html}\n<main id=\"app\"")
      end

      it 'handles mount points in nested HTML' do
        html = <<~HTML
          <html>
            <body>
              <header>Header</header>
              <div class="container">
                <div id="app">Content</div>
              </div>
            </body>
          </html>
        HTML

        mount_point = { selector: '#app', position: html.index('<div id="app">'), matched: 'id="app"' }

        allow(hydration_config).to receive(:injection_strategy).and_return(:early)
        result = injector.inject(html, hydration_html, mount_point)

        # Should inject before the <div id="app"> element, maintaining indentation
        expect(result).to include("#{hydration_html}\n<div id=\"app\">")
      end
    end

    context 'with multiple </body> tags' do
      it 'replaces only the first </body> tag' do
        html = '<body>Content</body><template><body>Template body</body></template>'
        result = injector.inject(html, hydration_html)

        body_positions = html.enum_for(:scan, /<\/body>/).map { Regexp.last_match.begin(0) }
        expect(body_positions.length).to eq(2)

        # Should only replace the first one
        expect(result.scan(hydration_html).length).to eq(1)
      end
    end
  end
end
