# spec/rhales/security/window_attribute_injection_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'erb'

# Regression coverage for issue #57:
#   - H-1: `window` attribute interpolated unescaped into HTML attribute and
#          JavaScript string contexts in view.rb and link_based_injection_detector.rb
#   - L-1: CSP nonce value written to the debug log (csp.rb generate_nonce + build_header)
RSpec.describe 'window attribute injection (issue #57)' do
  describe 'parse-time validation (primary defense)' do
    def parse(window_value)
      rue = <<~RUE
        <schema lang="js-zod" window=#{window_value.inspect}>
        const schema = z.object({ a: z.string() });
        </schema>

        <template>
        <div>page</div>
        </template>
      RUE
      doc = Rhales::RueDocument.new(rue)
      doc.parse!
      doc
    end

    it 'accepts valid JavaScript identifiers' do
      %w[data appState __ONETIME_STATE__ user_data myData _x x9].each do |name|
        expect { parse(name) }.not_to raise_error
        expect(parse(name).schema_window).to eq(name)
      end
    end

    it 'rejects a window name that breaks out of a single-quoted JS string' do
      expect { parse("x'];alert(1);//") }
        .to raise_error(Rhales::RueDocument::ParseError, /window/i)
    end

    it 'rejects a window name that breaks out of an HTML attribute' do
      expect { parse('x"><script>alert(1)</script>') }
        .to raise_error(Rhales::RueDocument::ParseError, /window/i)
    end

    it 'rejects a window name containing whitespace' do
      expect { parse('a b') }.to raise_error(Rhales::RueDocument::ParseError, /window/i)
    end

    it 'rejects a window name that does not start with a letter or underscore' do
      expect { parse('9bad') }.to raise_error(Rhales::RueDocument::ParseError, /window/i)
    end
  end

  describe 'view.rb render-site escaping (defense in depth)' do
    let(:config) { Rhales::Configuration.new }
    let(:view) { Rhales::View.new(nil, config: config) }
    let(:js_breakout) { "x'];alert(1);//" }
    let(:attr_breakout) { 'x"><script>alert(1)</script>' }

    context 'with reflection enabled (default)' do
      it 'HTML-escapes the window name in data-window / data-hydration-target attributes' do
        html = view.send(:generate_hydration_from_merged_data, { attr_breakout => { 'a' => 1 } })

        escaped = ERB::Util.html_escape(attr_breakout)
        expect(html).to include(%(data-window="#{escaped}"))
        expect(html).to include(%(data-hydration-target="#{escaped}"))
        expect(html).not_to include(%(data-window="#{attr_breakout}"))
        expect(html).not_to include('<script>alert(1)</script>')
      end

      it 'JSON-encodes the window name in the targetName fallback string' do
        html = view.send(:generate_hydration_from_merged_data, { js_breakout => { 'a' => 1 } })

        encoded = Rhales::JSONSerializer.dump_html_safe(js_breakout)
        expect(html).to include("|| #{encoded};")
        expect(html).not_to include("|| '#{js_breakout}'")
      end
    end

    context 'with reflection disabled' do
      before { config.hydration.reflection_enabled = false }

      it 'JSON-encodes the window name in the window[...] assignment' do
        html = view.send(:generate_hydration_from_merged_data, { js_breakout => { 'a' => 1 } })

        encoded = Rhales::JSONSerializer.dump_html_safe(js_breakout)
        expect(html).to include("window[#{encoded}]")
        expect(html).not_to include("window['#{js_breakout}']")
      end
    end
  end

  describe 'link_based_injection_detector.rb render-site escaping (defense in depth)' do
    let(:hydration_config) do
      cfg = Rhales::HydrationConfiguration.new
      cfg.api_endpoint_path = '/api/hydration'
      cfg
    end
    let(:detector) { Rhales::LinkBasedInjectionDetector.new(hydration_config) }
    let(:js_breakout) { "x'];alert(1);//" }
    let(:attr_breakout) { 'x"><script>alert(1)</script>' }

    [:preload, :modulepreload, :lazy].each do |strategy|
      it "JSON-encodes the window name in window[...] assignment for #{strategy}" do
        result = detector.generate_for_strategy(strategy, 'tpl', js_breakout, nil)

        encoded = Rhales::JSONSerializer.dump_html_safe(js_breakout)
        expect(result).to include("window[#{encoded}]")
        expect(result).not_to include("window['#{js_breakout}']")
      end
    end

    [:link, :prefetch, :preload, :modulepreload, :lazy].each do |strategy|
      it "HTML-escapes the window name in data-hydration-target for #{strategy}" do
        result = detector.generate_for_strategy(strategy, 'tpl', attr_breakout, nil)

        escaped = ERB::Util.html_escape(attr_breakout)
        expect(result).to include(%(data-hydration-target="#{escaped}"))
        expect(result).not_to include(%(data-hydration-target="#{attr_breakout}"))
      end
    end

    it 'uses static JS comments that never embed the window name (no comment breakout)' do
      { link: '// Load hydration data', prefetch: '// Prefetch hydration data' }.each do |strategy, comment|
        result = detector.generate_for_strategy(strategy, 'tpl', 'sentinelWindow', nil)
        comment_line = result.lines.find { |line| line.strip.start_with?(comment) }

        expect(comment_line).not_to be_nil
        expect(comment_line.strip).to eq(comment)
      end
    end
  end

  describe 'CSP nonce is not written to the debug log (L-1)' do
    let(:logger) { instance_double(Logger, debug: nil, info: nil, warn: nil, error: nil) }

    before { Rhales.logger = logger }
    after { Rhales.logger = nil }

    it 'does not log the raw nonce value when generating a nonce' do
      nonce = Rhales::CSP.generate_nonce

      expect(logger).to have_received(:debug).with(a_string_matching(/CSP nonce generated/))
      expect(logger).not_to have_received(:debug).with(a_string_including(nonce))
    end

    it 'does not log the raw nonce value when building a header' do
      config = Rhales::Configuration.new
      config.csp_enabled = true
      secret = 'supersecretnoncevalue'

      Rhales::CSP.new(config, nonce: secret).build_header

      expect(logger).not_to have_received(:debug).with(a_string_including(secret))
    end
  end
end
