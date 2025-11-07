# spec/rhales/logging_spec.rb
#
# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe 'Rhales Logging' do
  let(:logger) { double('logger') }
  let(:mock_request) { double('request', env: {}) }
  let(:original_logger) { Rhales.logger }

  before do
    # Mock logger calls to avoid noise in test output
    allow(logger).to receive(:debug)
    allow(logger).to receive(:info)
    allow(logger).to receive(:warn)
    allow(logger).to receive(:error)
  end

  after do
    Rhales.logger = original_logger
  end

  describe 'View rendering logging' do
    before do
      Rhales.logger = logger
    end

    it 'logs successful view renders with timing' do
      allow_any_instance_of(Rhales::View).to receive(:build_view_composition).and_return(
        double('composition',
          layout: nil,
          template_names: [],
          dependencies: {},
          each_document_in_render_order: [],
        ),
      )
      allow_any_instance_of(Rhales::View).to receive(:render_template_with_composition).and_return('<html></html>')
      allow_any_instance_of(Rhales::View).to receive(:generate_hydration_from_merged_data).and_return('')
      allow_any_instance_of(Rhales::View).to receive(:set_csp_header_if_enabled)
      allow_any_instance_of(Rhales::View).to receive(:inject_hydration_with_mount_points).and_return('<html></html>')
      allow_any_instance_of(Rhales::HydrationDataAggregator).to receive(:aggregate).and_return({})

      view = Rhales::View.new(mock_request, client: { user: 'test' })
      view.render('test_template')

      expect(logger).to have_received(:debug).with(
        a_string_matching(/View rendered: template=test_template/),
      )
    end

    it 'logs render failures with error context' do
      allow_any_instance_of(Rhales::View).to receive(:build_view_composition).and_raise('Test error')

      view = Rhales::View.new(mock_request)

      expect do
        view.render('test_template')
      end.to raise_error(Rhales::View::RenderError)

      expect(logger).to have_received(:error).with(
        a_string_matching(/View render failed: template=test_template/),
      )
    end

    it 'logs duration as integer microseconds' do
      allow_any_instance_of(Rhales::View).to receive(:build_view_composition).and_return(
        double('composition',
          layout: nil,
          template_names: [],
          dependencies: {},
          each_document_in_render_order: [],
        ),
      )
      allow_any_instance_of(Rhales::View).to receive(:render_template_with_composition).and_return('<html></html>')
      allow_any_instance_of(Rhales::View).to receive(:generate_hydration_from_merged_data).and_return('')
      allow_any_instance_of(Rhales::View).to receive(:set_csp_header_if_enabled)
      allow_any_instance_of(Rhales::View).to receive(:inject_hydration_with_mount_points).and_return('<html></html>')
      allow_any_instance_of(Rhales::HydrationDataAggregator).to receive(:aggregate).and_return({})

      view = Rhales::View.new(mock_request, client: { user: 'test' })
      view.render('test_template')

      # Verify duration is logged as an integer (microseconds, not float milliseconds)
      expect(logger).to have_received(:debug).with(
        a_string_matching(/View rendered: .*duration=\d+/),
      )
    end
  end

  describe 'Template engine logging' do
    before do
      Rhales.logger = logger
    end

    it 'logs template compilation with timing' do
      template = 'Hello {{user}}'
      context = Rhales::Context.minimal(client: { user: 'World' })

      engine = Rhales::TemplateEngine.new(template, context)
      engine.render

      expect(logger).to have_received(:debug).with(
        a_string_matching(/Template compiled: template_type=handlebars/),
      )
    end

    it 'logs unescaped variable warnings' do
      template = 'Unsafe: {{{html}}}'
      context = Rhales::Context.minimal(client: { html: '<script>alert("xss")</script>' })

      engine = Rhales::TemplateEngine.new(template, context)
      engine.render

      expect(logger).to have_received(:warn).with(
        a_string_matching(/Unescaped variable usage: variable=html/),
      )
    end

    describe 'allowed_unescaped_variables configuration' do
      after do
        Rhales.reset_configuration!
      end

      it 'suppresses warnings for whitelisted variables' do
        Rhales.reset_configuration!
        Rhales.configure do |config|
          config.allowed_unescaped_variables = ['vite_assets_html']
        end

        template = 'Assets: {{{vite_assets_html}}}'
        context = Rhales::Context.minimal(client: { vite_assets_html: '<script src="app.js"></script>' })

        engine = Rhales::TemplateEngine.new(template, context)
        engine.render

        expect(logger).not_to have_received(:warn)
      end

      it 'still warns for non-whitelisted variables' do
        Rhales.reset_configuration!
        Rhales.configure do |config|
          config.allowed_unescaped_variables = ['vite_assets_html']
        end

        template = 'Unsafe: {{{html}}}'
        context = Rhales::Context.minimal(client: { html: '<script>alert("xss")</script>' })

        engine = Rhales::TemplateEngine.new(template, context)
        engine.render

        expect(logger).to have_received(:warn).with(
          a_string_matching(/Unescaped variable usage: variable=html/),
        )
      end

      it 'works with multiple whitelisted variables' do
        Rhales.reset_configuration!
        Rhales.configure do |config|
          config.allowed_unescaped_variables = ['vite_assets_html', 'safe_html', 'trusted_content']
        end

        template = '{{{vite_assets_html}}} {{{safe_html}}} {{{trusted_content}}}'
        context = Rhales::Context.minimal(
          client: {
            vite_assets_html: '<script src="app.js"></script>',
            safe_html: '<div>Content</div>',
            trusted_content: '<p>Safe</p>',
          },
        )

        engine = Rhales::TemplateEngine.new(template, context)
        engine.render

        expect(logger).not_to have_received(:warn)
      end

      it 'handles both handlebars {{{ }}} and variable expressions' do
        Rhales.reset_configuration!
        Rhales.configure do |config|
          config.allowed_unescaped_variables = ['safe_var']
        end

        # Test both syntax forms
        template = '{{{safe_var}}} and also {{{safe_var}}}'
        context = Rhales::Context.minimal(client: { safe_var: '<div>Safe</div>' })

        engine = Rhales::TemplateEngine.new(template, context)
        engine.render

        expect(logger).not_to have_received(:warn)
      end

      it 'warns by default when allowed list is empty' do
        Rhales.reset_configuration!
        Rhales.configure do |config|
          config.allowed_unescaped_variables = []
        end

        template = '{{{html}}}'
        context = Rhales::Context.minimal(client: { html: '<script>xss</script>' })

        engine = Rhales::TemplateEngine.new(template, context)
        engine.render

        expect(logger).to have_received(:warn).with(
          a_string_matching(/Unescaped variable usage: variable=html/),
        )
      end
    end

    it 'logs parse errors with location context' do
      template = '{{unclosed'
      context = Rhales::Context.minimal(client: {})

      engine = Rhales::TemplateEngine.new(template, context)

      expect do
        engine.render
      end.to raise_error(Rhales::TemplateEngine::RenderError)

      expect(logger).to have_received(:error).with(
        a_string_matching(/Template parse error: error="Expected/),
      )
    end
  end

  describe 'CSP logging' do
    let(:config) { Rhales::Configuration.new }

    before do
      Rhales.logger = logger
      config.csp_enabled = true
    end

    it 'logs nonce generation' do
      Rhales::CSP.generate_nonce

      expect(logger).to have_received(:debug).with(
        a_string_matching(/CSP nonce generated: nonce=\w+/),
      )
    end

    it 'logs CSP header generation' do
      csp = Rhales::CSP.new(config, nonce: 'test-nonce')
      csp.build_header

      expect(logger).to have_received(:debug).with(
        a_string_matching(/CSP header generated: nonce_used=true/),
      )
    end
  end

  describe 'Logger configuration' do
    it 'uses Rhales.logger throughout the framework' do
      custom_logger = double('custom_logger')
      allow(custom_logger).to receive(:debug)
      allow(custom_logger).to receive(:info)

      Rhales.logger = custom_logger

      # View logging uses Rhales.logger
      allow_any_instance_of(Rhales::View).to receive(:build_view_composition).and_return(
        double('composition',
          layout: nil,
          template_names: [],
          dependencies: {},
          each_document_in_render_order: [],
        ),
      )
      allow_any_instance_of(Rhales::View).to receive(:render_template_with_composition).and_return('<html></html>')
      allow_any_instance_of(Rhales::View).to receive(:generate_hydration_from_merged_data).and_return('')
      allow_any_instance_of(Rhales::View).to receive(:set_csp_header_if_enabled)
      allow_any_instance_of(Rhales::View).to receive(:inject_hydration_with_mount_points).and_return('<html></html>')
      allow_any_instance_of(Rhales::HydrationDataAggregator).to receive(:aggregate).and_return({})

      view = Rhales::View.new(mock_request, client: { user: 'test' })
      view.render('test_template')

      expect(custom_logger).to have_received(:debug).with(
        a_string_matching(/View rendered/),
      )
    end
  end
end
