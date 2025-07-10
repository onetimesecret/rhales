require 'spec_helper'

RSpec.describe Rhales::MountPointDetector do
  let(:detector) { described_class.new }

  describe '#detect' do
    context 'with ID selectors' do
      it 'detects simple ID mount points' do
        html = '<div id="app">Content</div>'
        result = detector.detect(html)

        expect(result).not_to be_nil
        expect(result[:selector]).to eq('#app')
        expect(result[:position]).to eq(0)
        expect(result[:matched]).to eq('id="app"')
      end

      it 'detects ID mount points with surrounding content' do
        html = '<header>Header</header><div id="root">App content</div><footer>Footer</footer>'
        result = detector.detect(html)

        expect(result).not_to be_nil
        expect(result[:selector]).to eq('#root')
        expect(result[:position]).to eq(23)
      end

      it 'handles single quotes' do
        html = "<div id='app'>Content</div>"
        result = detector.detect(html)

        expect(result).not_to be_nil
        expect(result[:selector]).to eq('#app')
      end

      it 'is case insensitive' do
        html = '<DIV ID="app">Content</DIV>'
        result = detector.detect(html)

        expect(result).not_to be_nil
        expect(result[:selector]).to eq('#app')
      end
    end

    context 'with class selectors' do
      it 'detects class-based mount points' do
        html = '<div class="react-root other-class">Content</div>'
        result = detector.detect(html, ['.react-root'])

        expect(result).not_to be_nil
        expect(result[:selector]).to eq('.react-root')
      end

      it 'handles multiple classes' do
        html = '<main class="app-container vue-app layout">Content</main>'
        result = detector.detect(html, ['.vue-app'])

        expect(result).not_to be_nil
        expect(result[:selector]).to eq('.vue-app')
      end
    end

    context 'with attribute selectors' do
      it 'detects data attribute mount points' do
        html = '<main data-rsfc-mount>Content</main>'
        result = detector.detect(html)

        expect(result).not_to be_nil
        expect(result[:selector]).to eq('[data-rsfc-mount]')
      end

      it 'detects data attributes with values' do
        html = '<div data-mount="app">Content</div>'
        result = detector.detect(html)

        expect(result).not_to be_nil
        expect(result[:selector]).to eq('[data-mount]')
      end

      it 'handles custom attribute selectors' do
        html = '<section data-vue-root="main">Content</section>'
        result = detector.detect(html, ['[data-vue-root]'])

        expect(result).not_to be_nil
        expect(result[:selector]).to eq('[data-vue-root]')
      end
    end

    context 'with multiple mount points' do
      it 'returns the earliest mount point' do
        html = '<div id="header">Header</div><main data-rsfc-mount>Content</main><div id="app">App</div>'
        result = detector.detect(html)

        expect(result).not_to be_nil
        expect(result[:selector]).to eq('[data-rsfc-mount]')
        expect(result[:position]).to eq(29) # Position of the < character
      end

      it 'prioritizes by order of appearance, not selector priority' do
        html = '<div data-mount>First</div><div id="app">Second</div>'
        result = detector.detect(html)

        expect(result).not_to be_nil
        expect(result[:selector]).to eq('[data-mount]')
      end
    end

    context 'with custom selectors' do
      it 'uses custom selectors along with defaults' do
        html = '<div class="my-app">Content</div>'
        result = detector.detect(html, ['.my-app'])

        expect(result).not_to be_nil
        expect(result[:selector]).to eq('.my-app')
      end

      it 'handles empty custom selectors' do
        html = '<div id="app">Content</div>'
        result = detector.detect(html, [])

        expect(result).not_to be_nil
        expect(result[:selector]).to eq('#app')
      end

      it 'handles nil custom selectors' do
        html = '<div id="app">Content</div>'
        result = detector.detect(html, nil)

        expect(result).not_to be_nil
        expect(result[:selector]).to eq('#app')
      end
    end

    context 'when no mount points found' do
      it 'returns nil for HTML without mount points' do
        html = '<div class="content">No mount point here</div>'
        result = detector.detect(html)

        expect(result).to be_nil
      end

      it 'returns nil for empty HTML' do
        result = detector.detect('')

        expect(result).to be_nil
      end

      it 'returns nil for malformed selectors' do
        html = '<div id="app">Content</div>'
        result = detector.detect(html, ['invalid-selector'])

        # Should still find default selectors
        expect(result).not_to be_nil
        expect(result[:selector]).to eq('#app')
      end
    end

    context 'with complex HTML' do
      it 'handles nested elements' do
        html = <<~HTML
          <html>
            <head><title>Test</title></head>
            <body>
              <header>Header content</header>
              <main>
                <div id="app">
                  <div class="nested">Nested content</div>
                </div>
              </main>
            </body>
          </html>
        HTML

        result = detector.detect(html)

        expect(result).not_to be_nil
        expect(result[:selector]).to eq('#app')
      end

      it 'handles HTML with special characters' do
        html = '<div id="app" data-special="&quot;test&quot;">Content</div>'
        result = detector.detect(html)

        expect(result).not_to be_nil
        expect(result[:selector]).to eq('#app')
      end
    end
  end
end
