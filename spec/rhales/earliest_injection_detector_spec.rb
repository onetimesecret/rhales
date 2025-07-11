require 'spec_helper'

RSpec.describe Rhales::EarliestInjectionDetector do
  let(:detector) { described_class.new }

  describe '#detect' do
    context 'with HTML head section' do
      it 'injects after last link tag' do
        html = <<~HTML
          <html>
          <head>
            <title>Test</title>
            <link rel="stylesheet" href="style1.css">
            <link rel="stylesheet" href="style2.css">
            <meta name="description" content="test">
            <script src="app.js"></script>
          </head>
          <body>
            <div id="app"></div>
          </body>
          </html>
        HTML

        position = detector.detect(html)

        # Should inject after the last link tag
        style2_end = html.index('<link rel="stylesheet" href="style2.css">') + html.match(/<link rel="stylesheet" href="style2\.css">/)[0].length
        meta_start = html.index('<meta name="description"')

        expect(position).to be >= style2_end
        expect(position).to be < meta_start
      end

      it 'injects after last meta tag when no link tags' do
        html = <<~HTML
          <html>
          <head>
            <title>Test</title>
            <meta name="description" content="test">
            <meta name="viewport" content="width=device-width">
            <script src="app.js"></script>
          </head>
          <body>
            <div id="app"></div>
          </body>
          </html>
        HTML

        position = detector.detect(html)
        expect(position).to be > html.index('<meta name="viewport"') + 45
        expect(position).to be < html.index('<script src="app.js">')
      end

      it 'injects after first script tag when no link or meta tags' do
        html = <<~HTML
          <html>
          <head>
            <title>Test</title>
            <script src="app.js"></script>
            <script src="utils.js"></script>
          </head>
          <body>
            <div id="app"></div>
          </body>
          </html>
        HTML

        position = detector.detect(html)
        expect(position).to be > html.index('</script>')
        expect(position).to be < html.index('<script src="utils.js">')
      end

      it 'injects before closing head tag as fallback' do
        html = <<~HTML
          <html>
          <head>
            <title>Test</title>
          </head>
          <body>
            <div id="app"></div>
          </body>
          </html>
        HTML

        position = detector.detect(html)
        expect(position).to be <= html.index('</head>')
        expect(position).to be > html.index('<title>Test</title>')
      end

      it 'handles self-closing link tags' do
        html = <<~HTML
          <html>
          <head>
            <link rel="stylesheet" href="style.css"/>
            <meta charset="utf-8"/>
          </head>
          <body>
            <div id="app"></div>
          </body>
          </html>
        HTML

        position = detector.detect(html)
        link_end = html.index('<link rel="stylesheet" href="style.css"/>') + html.match(/<link rel="stylesheet" href="style\.css"\/>/)[0].length
        expect(position).to be >= link_end
      end
    end

    context 'without head section but with body' do
      it 'injects before body tag' do
        html = <<~HTML
          <html>
          <body>
            <div id="app"></div>
          </body>
          </html>
        HTML

        position = detector.detect(html)
        expect(position).to eq html.index('<body>')
      end

      it 'handles body tag with attributes' do
        html = <<~HTML
          <html>
          <body class="app-body" data-theme="dark">
            <div id="app"></div>
          </body>
          </html>
        HTML

        position = detector.detect(html)
        expect(position).to eq html.index('<body class="app-body" data-theme="dark">')
      end
    end

    context 'with unsafe injection contexts' do
      it 'avoids injection inside script tags' do
        html = <<~HTML
          <html>
          <head>
            <script>
            var config = {
              link: "test"
            };
            </script>
            <link rel="stylesheet" href="style.css">
          </head>
          <body>
            <div id="app"></div>
          </body>
          </html>
        HTML

        position = detector.detect(html)
        # Should inject after the link, not inside the script
        link_end = html.index('<link rel="stylesheet" href="style.css">') + html.match(/<link rel="stylesheet" href="style\.css">/)[0].length
        expect(position).to be >= link_end
      end

      it 'avoids injection inside style tags' do
        html = <<~HTML
          <html>
          <head>
            <style>
            .link { color: blue; }
            </style>
            <meta name="description" content="test">
          </head>
          <body>
            <div id="app"></div>
          </body>
          </html>
        HTML

        position = detector.detect(html)
        # Should inject after the meta tag, not inside the style
        expect(position).to be > html.index('<meta name="description" content="test">') + 39
      end

      it 'avoids injection inside HTML comments' do
        html = <<~HTML
          <html>
          <head>
            <!-- This is a comment with link and meta references -->
            <link rel="stylesheet" href="style.css">
          </head>
          <body>
            <div id="app"></div>
          </body>
          </html>
        HTML

        position = detector.detect(html)
        # Should find a safe injection point after the link
        link_end = html.index('<link rel="stylesheet" href="style.css">') + html.match(/<link rel="stylesheet" href="style\.css">/)[0].length
        expect(position).to be >= link_end
      end
    end

    context 'with malformed or missing HTML' do
      it 'returns nil for empty HTML' do
        expect(detector.detect('')).to be_nil
      end

      it 'returns nil when no suitable injection point found' do
        html = '<html><script>everything is a script</script></html>'
        # This should return nil if no safe injection point exists
        position = detector.detect(html)
        expect(position).to be_nil
      end

      it 'handles unclosed head tag' do
        html = <<~HTML
          <html>
          <head>
            <title>Test</title>
            <link rel="stylesheet" href="style.css">
          <body>
            <div id="app"></div>
          </body>
          </html>
        HTML

        # Should still detect body injection as fallback
        position = detector.detect(html)
        expect(position).to eq html.index('<body>')
      end
    end

    context 'with complex nested HTML' do
      it 'handles multiple head sections correctly' do
        html = <<~HTML
          <html>
          <head>
            <title>Test</title>
            <link rel="stylesheet" href="style.css">
            <script>
            // This script contains head-like content
            var fakeHead = '<head><link rel="fake"></head>';
            </script>
            <meta name="description" content="test">
          </head>
          <body>
            <div id="app"></div>
          </body>
          </html>
        HTML

        position = detector.detect(html)
        # Should find the earliest safe injection point, which is after the link tag
        link_end = html.index('<link rel="stylesheet" href="style.css">') + html.match(/<link rel="stylesheet" href="style\.css">/)[0].length
        expect(position).to be >= link_end
        # Should not be inside the script (between script tags)
        script_start = html.index('<script>')
        script_end = html.index('</script>') + 9
        expect(position).not_to be_between(script_start, script_end)
      end

      it 'prioritizes real tags over script content' do
        html = <<~HTML
          <html>
          <head>
            <script>
            var template = '<meta name="fake" content="fake">';
            </script>
            <link rel="stylesheet" href="real.css">
          </head>
          <body>
            <div id="app"></div>
          </body>
          </html>
        HTML

        position = detector.detect(html)
        # Should inject after the real link tag
        expect(position).to be > html.index('<link rel="stylesheet" href="real.css">') + 37
      end
    end

    context 'performance with large templates' do
      it 'handles large HTML documents efficiently' do
        # Create a large HTML document
        large_html = "<html><head><title>Test</title>"
        1000.times { |i| large_html += "<meta name=\"test#{i}\" content=\"value#{i}\">" }
        large_html += "<link rel=\"stylesheet\" href=\"final.css\"></head><body><div id=\"app\"></div></body></html>"

        start_time = Time.now
        position = detector.detect(large_html)
        end_time = Time.now

        expect(position).not_to be_nil
        expect(end_time - start_time).to be < 0.1  # Should complete within 100ms
      end
    end
  end
end
