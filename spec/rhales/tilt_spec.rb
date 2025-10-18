# spec/rhales/tilt_spec.rb

require 'spec_helper'
require 'rhales/tilt'

RSpec.describe Rhales::TiltTemplate do
  let(:template_content) { '<h1>{{title}}</h1><p>{{content}}</p>' }
  let(:template_file) { 'test_template.rue' }
  let(:template) { described_class.new(template_file) { template_content } }

  describe '#prepare' do
    it 'stores template content' do
      template.prepare
      expect(template.instance_variable_get(:@template_content)).to eq(template_content)
    end
  end

  describe '#evaluate' do
    let(:mock_scope) { double('scope') }
    let(:locals) { { title: 'Test Title', content: 'Test Content' } }

    context 'with minimal scope' do
      before do
        allow(mock_scope).to receive(:respond_to?).and_return(false)
        allow(mock_scope).to receive(:instance_variable_set)
      end

      it 'renders template with locals' do
        allow_any_instance_of(Rhales::View).to receive(:render).and_return('<h1>Test Title</h1><p>Test Content</p>')

        result = template.evaluate(mock_scope, locals)
        expect(result).to eq('<h1>Test Title</h1><p>Test Content</p>')
      end
    end

    context 'with framework scope (Roda/Sinatra)' do
      let(:mock_request) { double('request', path: '/test', request_method: 'GET', env: {}) }
      let(:mock_flash) { { 'notice' => 'Success!', 'error' => nil } }

      before do
        allow(mock_scope).to receive(:respond_to?).and_return(false)
        allow(mock_scope).to receive(:respond_to?).with(:request).and_return(true)
        allow(mock_scope).to receive(:respond_to?).with(:flash).and_return(true)
        allow(mock_scope).to receive(:respond_to?).with(:logged_in?).and_return(true)
        allow(mock_scope).to receive(:respond_to?).with(:current_user).and_return(false)
        allow(mock_scope).to receive(:respond_to?).with(:csp_nonce).and_return(false)
        allow(mock_scope).to receive(:respond_to?).with(:rodauth).and_return(false)
        allow(mock_scope).to receive(:respond_to?).with(:instance_variable_set).and_return(true)
        allow(mock_scope).to receive(:request).and_return(mock_request)
        allow(mock_scope).to receive(:flash).and_return(mock_flash)
        allow(mock_scope).to receive(:logged_in?).and_return(true)
        allow(mock_scope).to receive(:instance_variable_set)
      end

      it 'includes request data in props' do
        expect(template).to receive(:build_rhales_context) do |scope, props|
          expect(props['current_path']).to eq('/test')
          expect(props['request_method']).to eq('GET')
          expect(props['flash_notice']).to eq('Success!')
          expect(props['authenticated']).to be(true)
          double('rhales_context').tap do |ctx|
            allow(ctx).to receive(:render).and_return('rendered')
          end
        end

        template.evaluate(mock_scope, locals)
      end
    end
  end

  describe '#build_props' do
    let(:mock_scope) { double('scope') }
    let(:locals) { { title: 'Test' } }

    before do
      allow(mock_scope).to receive(:respond_to?).and_return(false)
    end

    it 'includes locals in props' do
      props = template.send(:build_props, mock_scope, locals)
      expect(props[:title]).to eq('Test')
    end

    it 'adds block content when provided' do
      props = template.send(:build_props, mock_scope, locals) { 'Block Content' }
      expect(props['content']).to eq('Block Content')
    end

    context 'with request' do
      let(:mock_request) { double('request', path: '/users', request_method: 'POST') }

      before do
        allow(mock_scope).to receive(:respond_to?).with(:request).and_return(true)
        allow(mock_scope).to receive(:request).and_return(mock_request)
      end

      it 'adds request data' do
        props = template.send(:build_props, mock_scope, locals)
        expect(props['current_path']).to eq('/users')
        expect(props['request_method']).to eq('POST')
      end
    end

    context 'with flash' do
      let(:mock_flash) { { 'notice' => 'Saved!', 'error' => 'Failed!' } }

      before do
        allow(mock_scope).to receive(:respond_to?).with(:flash).and_return(true)
        allow(mock_scope).to receive(:flash).and_return(mock_flash)
      end

      it 'adds flash messages' do
        props = template.send(:build_props, mock_scope, locals)
        expect(props['flash_notice']).to eq('Saved!')
        expect(props['flash_error']).to eq('Failed!')
      end
    end

    context 'with rodauth' do
      let(:mock_rodauth) { double('rodauth') }

      before do
        allow(mock_scope).to receive(:respond_to?).with(:rodauth).and_return(true)
        allow(mock_scope).to receive(:rodauth).and_return(mock_rodauth)
      end

      it 'adds rodauth object' do
        props = template.send(:build_props, mock_scope, locals)
        expect(props['rodauth']).to eq(mock_rodauth)
      end
    end

    context 'with authentication' do
      before do
        allow(mock_scope).to receive(:respond_to?).with(:logged_in?).and_return(true)
        allow(mock_scope).to receive(:logged_in?).and_return(true)
      end

      it 'adds authentication status' do
        props = template.send(:build_props, mock_scope, locals)
        expect(props['authenticated']).to be(true)
      end
    end
  end

  describe '#build_rhales_context' do
    let(:mock_scope) { double('scope') }
    let(:props) { { title: 'Test', content: 'Content' } }

    before do
      allow(mock_scope).to receive(:respond_to?).and_return(false)
      allow(mock_scope).to receive(:instance_variable_set)
    end

    context 'with minimal scope' do
      it 'creates context with SimpleRequest' do
        context = template.send(:build_rhales_context, mock_scope, props)

        expect(context).to be_a(Rhales::View)
        expect(context.instance_variable_get(:@req)).to be_a(Rhales::Adapters::SimpleRequest)
        expect(context.client).to eq({ 'title' => 'Test', 'content' => 'Content' })
      end

      it 'creates anonymous session and auth' do
        context = template.send(:build_rhales_context, mock_scope, props)

        expect(context.sess).to be_a(Rhales::Adapters::AnonymousSession)
        expect(context.user).to be_a(Rhales::Adapters::AnonymousAuth)
      end

      it 'generates nonce and request_id' do
        context = template.send(:build_rhales_context, mock_scope, props)

        expect(context.rsfc_context.get('nonce')).to be_a(String)
        expect(context.rsfc_context.get('nonce').length).to eq(32)
        expect(context.rsfc_context.get('request_id')).to be_a(String)
      end
    end

    context 'with authenticated scope' do
      let(:mock_user) { { id: 123, email: 'user@test.com' } }

      before do
        allow(mock_scope).to receive(:respond_to?).and_return(false)
        allow(mock_scope).to receive(:respond_to?).with(:logged_in?).and_return(true)
        allow(mock_scope).to receive(:respond_to?).with(:current_user).and_return(true)
        allow(mock_scope).to receive(:respond_to?).with(:instance_variable_set).and_return(true)
        allow(mock_scope).to receive(:logged_in?).and_return(true)
        allow(mock_scope).to receive(:current_user).and_return(mock_user)
        allow(mock_scope).to receive(:instance_variable_set)
      end

      it 'creates authenticated session and auth' do
        context = template.send(:build_rhales_context, mock_scope, props)

        expect(context.sess).to be_a(Rhales::Adapters::AuthenticatedSession)
        expect(context.user).to be_a(Rhales::Adapters::AuthenticatedAuth)
        expect(context.user.user_id).to eq(123)
        expect(context.user.attributes[:email]).to eq('user@test.com')
        expect(context.rsfc_context.get('authenticated')).to be(true)
      end
    end

    context 'with framework request' do
      let(:mock_request) { double('request', env: { 'REMOTE_ADDR' => '192.168.1.1' }) }

      before do
        allow(mock_scope).to receive(:respond_to?).and_return(false)
        allow(mock_scope).to receive(:respond_to?).with(:request).and_return(true)
        allow(mock_scope).to receive(:respond_to?).with(:instance_variable_set).and_return(true)
        allow(mock_scope).to receive(:request).and_return(mock_request)
        allow(mock_scope).to receive(:instance_variable_set)
      end

      it 'creates FrameworkRequest with wrapped env' do
        context = template.send(:build_rhales_context, mock_scope, props)

        request_adapter = context.rsfc_context.instance_variable_get(:@req)
        expect(request_adapter).to be_a(Rhales::Adapters::FrameworkRequest)

        # Verify the wrapped request preserves original env and adds our data
        expect(request_adapter.env['REMOTE_ADDR']).to eq('192.168.1.1')  # Original
        expect(request_adapter.env['nonce']).to be_a(String)              # Added
        expect(request_adapter.env['request_id']).to be_a(String)         # Added
      end

      it 'exposes session and user methods on request' do
        context = template.send(:build_rhales_context, mock_scope, props)

        request_adapter = context.rsfc_context.instance_variable_get(:@req)
        expect(request_adapter).to respond_to(:session)
        expect(request_adapter).to respond_to(:user)
      end
    end

    context 'with client_data and server_data separation' do
      let(:props_with_separation) do
        {
          title: 'Default',
          client_data: { user_id: 123, api_key: 'secret' },
          server_data: { csrf_token: 'token123', page_title: 'Admin' }
        }
      end

      it 'separates client and server data correctly' do
        context = template.send(:build_rhales_context, mock_scope, props_with_separation)

        expect(context.client).to eq({ 'user_id' => 123, 'api_key' => 'secret' })
        expect(context.server['csrf_token']).to eq('token123')
        expect(context.server['page_title']).to eq('Admin')
        expect(context.client['title']).to be_nil  # Not in client_data
      end
    end
  end

  describe '#get_shared_nonce' do
    let(:mock_scope) { double('scope') }

    context 'with csp_nonce method' do
      before do
        allow(mock_scope).to receive(:respond_to?).with(:csp_nonce).and_return(true)
        allow(mock_scope).to receive(:csp_nonce).and_return('method-nonce-123')
      end

      it 'uses scope csp_nonce method' do
        nonce = template.send(:get_shared_nonce, mock_scope)
        expect(nonce).to eq('method-nonce-123')
      end
    end

    context 'with request env nonce' do
      let(:mock_request) { double('request', env: { 'csp.nonce' => 'env-nonce-456' }) }

      before do
        allow(mock_scope).to receive(:respond_to?).with(:csp_nonce).and_return(false)
        allow(mock_scope).to receive(:respond_to?).with(:request).and_return(true)
        allow(mock_scope).to receive(:request).and_return(mock_request)
      end

      it 'uses request env nonce' do
        nonce = template.send(:get_shared_nonce, mock_scope)
        expect(nonce).to eq('env-nonce-456')
      end
    end

    context 'with instance variable nonce' do
      before do
        allow(mock_scope).to receive(:respond_to?).with(:csp_nonce).and_return(false)
        allow(mock_scope).to receive(:respond_to?).with(:request).and_return(false)
        allow(mock_scope).to receive(:instance_variable_defined?).with(:@csp_nonce).and_return(true)
        allow(mock_scope).to receive(:instance_variable_get).with(:@csp_nonce).and_return('ivar-nonce-789')
      end

      it 'uses instance variable nonce' do
        nonce = template.send(:get_shared_nonce, mock_scope)
        expect(nonce).to eq('ivar-nonce-789')
      end
    end

    context 'without existing nonce' do
      before do
        allow(mock_scope).to receive(:respond_to?).and_return(false)
        allow(mock_scope).to receive(:instance_variable_defined?).and_return(false)
        allow(mock_scope).to receive(:instance_variable_set)
        allow(SecureRandom).to receive(:hex).with(16).and_return('generated-nonce')
      end

      it 'generates and stores new nonce' do
        allow(mock_scope).to receive(:respond_to?).with(:instance_variable_set).and_return(true)
        expect(mock_scope).to receive(:instance_variable_set).with(:@csp_nonce, 'generated-nonce')

        nonce = template.send(:get_shared_nonce, mock_scope)
        expect(nonce).to eq('generated-nonce')
      end
    end
  end

  describe '#derive_template_name' do
    context 'without file path' do
      let(:template) { described_class.new { template_content } }

      it 'returns unknown when no file' do
        name = template.send(:derive_template_name)
        expect(name).to eq('unknown')
      end
    end

    context 'with simple file path' do
      let(:template) { described_class.new('/path/to/template.rue') { template_content } }

      it 'extracts basename without extension' do
        name = template.send(:derive_template_name)
        expect(name).to eq('template')
      end
    end

    context 'with configured template paths' do
      let(:template) { described_class.new('/app/views/users/show.rue') { template_content } }

      before do
        config = double('config', template_paths: ['/app/views', '/app/partials'])
        allow(Rhales).to receive(:configuration).and_return(config)
      end

      it 'creates relative path from configured template paths' do
        name = template.send(:derive_template_name)
        expect(name).to eq('users/show')
      end
    end

    context 'caching template name' do
      let(:template) { described_class.new('/path/template.rue') { template_content } }

      it 'caches derived name' do
        template.instance_variable_set(:@template_name, 'cached_name')
        name = template.send(:derive_template_name)
        expect(name).to eq('cached_name')
      end
    end
  end

  describe 'Tilt registration' do
    it 'registers Rhales::TiltTemplate for .rue files' do
      expect(Tilt['test.rue']).to eq(Rhales::TiltTemplate)
    end

    it 'has correct default MIME type' do
      expect(Rhales::TiltTemplate.default_mime_type).to eq('text/html')
    end
  end
end
