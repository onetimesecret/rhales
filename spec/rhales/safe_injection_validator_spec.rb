require 'spec_helper'

RSpec.describe Rhales::SafeInjectionValidator do
  describe '#safe_injection_point?' do
    context 'with script tags' do
      it 'detects unsafe injection inside script tags' do
        html = '<script>var app = "test";</script><div id="app">Content</div>'
        validator = described_class.new(html)

        # Position inside the script tag should be unsafe
        script_inside_pos = html.index('var app')
        expect(validator.safe_injection_point?(script_inside_pos)).to be false
      end

      it 'allows safe injection outside script tags' do
        html = '<script>var app = "test";</script><div id="app">Content</div>'
        validator = described_class.new(html)

        # Position after the script tag should be safe
        after_script_pos = html.index('<div id="app">')
        expect(validator.safe_injection_point?(after_script_pos)).to be true
      end

      it 'handles unclosed script tags' do
        html = '<script>var app = "test"; // missing closing tag<div id="app">Content</div>'
        validator = described_class.new(html)

        # Everything after unclosed script should be unsafe
        app_div_pos = html.index('<div id="app">')
        expect(validator.safe_injection_point?(app_div_pos)).to be false
      end

      it 'handles script tags with attributes' do
        html = '<script type="text/javascript" nonce="abc123">alert("test");</script><div id="app">App</div>'
        validator = described_class.new(html)

        inside_script = html.index('alert')
        after_script = html.index('<div id="app">')

        expect(validator.safe_injection_point?(inside_script)).to be false
        expect(validator.safe_injection_point?(after_script)).to be true
      end
    end

    context 'with style tags' do
      it 'detects unsafe injection inside style tags' do
        html = '<style>.app { color: red; }</style><div id="app">Content</div>'
        validator = described_class.new(html)

        inside_style = html.index('.app')
        expect(validator.safe_injection_point?(inside_style)).to be false
      end

      it 'allows safe injection outside style tags' do
        html = '<style>.app { color: red; }</style><div id="app">Content</div>'
        validator = described_class.new(html)

        after_style = html.index('<div id="app">')
        expect(validator.safe_injection_point?(after_style)).to be true
      end
    end

    context 'with HTML comments' do
      it 'detects unsafe injection inside comments' do
        html = '<!-- This is a comment --><div id="app">Content</div>'
        validator = described_class.new(html)

        inside_comment = html.index('This is')
        expect(validator.safe_injection_point?(inside_comment)).to be false
      end

      it 'allows safe injection outside comments' do
        html = '<!-- This is a comment --><div id="app">Content</div>'
        validator = described_class.new(html)

        after_comment = html.index('<div id="app">')
        expect(validator.safe_injection_point?(after_comment)).to be true
      end
    end

    context 'with CDATA sections' do
      it 'detects unsafe injection inside CDATA' do
        html = '<![CDATA[Some data content]]><div id="app">Content</div>'
        validator = described_class.new(html)

        inside_cdata = html.index('Some data')
        expect(validator.safe_injection_point?(inside_cdata)).to be false
      end

      it 'allows safe injection outside CDATA' do
        html = '<![CDATA[Some data content]]><div id="app">Content</div>'
        validator = described_class.new(html)

        after_cdata = html.index('<div id="app">')
        expect(validator.safe_injection_point?(after_cdata)).to be true
      end
    end

    context 'with complex HTML scenarios' do
      it 'handles the problematic colourmode scenario' do
        html = <<~HTML
          <script nonce="abc123" language="javascript">
            // This lightweight script ensures instant theme switching
            (() => {
              var { matches: isRestMode } = window.matchMedia('(prefers-color-scheme: dark)');
              // ... more script content
            })();
          </script>
          <div id="app">Content</div>
        HTML

        validator = described_class.new(html)

        # Position inside script should be unsafe
        inside_script = html.index('var { matches')
        expect(validator.safe_injection_point?(inside_script)).to be false

        # Position after script should be safe
        app_div = html.index('<div id="app">')
        expect(validator.safe_injection_point?(app_div)).to be true
      end

      it 'handles multiple unsafe contexts' do
        html = <<~HTML
          <style>.theme { color: blue; }</style>
          <!-- Comment -->
          <script>var x = 1;</script>
          <div id="app">Content</div>
        HTML

        validator = described_class.new(html)

        style_inside = html.index('.theme')
        comment_inside = html.index('Comment')
        script_inside = html.index('var x')
        app_div = html.index('<div id="app">')

        expect(validator.safe_injection_point?(style_inside)).to be false
        expect(validator.safe_injection_point?(comment_inside)).to be false
        expect(validator.safe_injection_point?(script_inside)).to be false
        expect(validator.safe_injection_point?(app_div)).to be true
      end
    end

    context 'with edge cases' do
      it 'handles position at beginning of document' do
        html = '<div id="app">Content</div>'
        validator = described_class.new(html)

        expect(validator.safe_injection_point?(0)).to be true
      end

      it 'handles position at end of document' do
        html = '<div id="app">Content</div>'
        validator = described_class.new(html)

        expect(validator.safe_injection_point?(html.length)).to be true
      end

      it 'handles invalid positions' do
        html = '<div id="app">Content</div>'
        validator = described_class.new(html)

        expect(validator.safe_injection_point?(-1)).to be false
        expect(validator.safe_injection_point?(html.length + 1)).to be false
      end
    end
  end

  describe '#nearest_safe_point_before' do
    it 'finds safe point before unsafe script content' do
      html = '<div>Before</div><script>unsafe content</script><div id="app">After</div>'
      validator = described_class.new(html)

      script_inside = html.index('unsafe')
      safe_before = validator.nearest_safe_point_before(script_inside)

      expect(safe_before).to be <= html.index('<script>')
      expect(validator.safe_injection_point?(safe_before)).to be true
    end

    it 'returns nil when no safe point found before' do
      html = '<script>unsafe from start</script><div id="app">Content</div>'
      validator = described_class.new(html)

      script_inside = html.index('unsafe')
      expect(validator.nearest_safe_point_before(script_inside)).to be_nil
    end
  end

  describe '#nearest_safe_point_after' do
    it 'finds safe point after unsafe script content' do
      html = '<script>unsafe content</script><div id="app">After</div>'
      validator = described_class.new(html)

      script_inside = html.index('unsafe')
      safe_after = validator.nearest_safe_point_after(script_inside)

      expect(safe_after).to be >= html.index('</script>') + 9 # length of '</script>'
      expect(validator.safe_injection_point?(safe_after)).to be true
    end

    it 'returns nil when no safe point found after' do
      html = '<div id="app">Content</div><script>unsafe to end'
      validator = described_class.new(html)

      script_inside = html.index('unsafe')
      expect(validator.nearest_safe_point_after(script_inside)).to be_nil
    end
  end

  describe 'tag boundary detection' do
    it 'recognizes safe injection at tag boundaries' do
      html = '<div><span>content</span></div><div id="app">App</div>'
      validator = described_class.new(html)

      # Before opening tags
      expect(validator.safe_injection_point?(0)).to be true
      expect(validator.safe_injection_point?(html.index('<span>'))).to be true
      expect(validator.safe_injection_point?(html.index('<div id="app">'))).to be true

      # After closing tags
      expect(validator.safe_injection_point?(html.index('</span>') + 7)).to be true
      expect(validator.safe_injection_point?(html.index('</div>') + 6)).to be true
    end

    it 'handles whitespace between tags' do
      html = '<div>content</div>   <div id="app">App</div>'
      validator = described_class.new(html)

      whitespace_pos = html.index('   ')
      expect(validator.safe_injection_point?(whitespace_pos)).to be true
    end
  end
end
