# spec/rhales/context_spec.rb

require 'spec_helper'

# rubocop:disable RSpec/MultipleExpectations
# rubocop:disable RSpec/MultipleDescribes
RSpec.describe Rhales::Context do
  let(:mock_session) { Rhales::Adapters::AuthenticatedSession.new(id: 'session123', created_at: Time.now) }
  let(:mock_user) { Rhales::Adapters::AuthenticatedAuth.new(id: 456, name: 'Test User', theme: 'dark') }
  let(:mock_request) {
    session_instance = mock_session
    user_instance = mock_user
    req = double('request', env: { 'csrf_token' => 'test-csrf', 'nonce' => 'test-nonce' })
    req.define_singleton_method(:session) { session_instance }
    req.define_singleton_method(:user) { user_instance }
    req
  }
  let(:props) { { page_title: 'Test Page', content: 'Hello World' } }

  describe '#initialize' do
    subject { described_class.new(mock_request, client: props) }

    it 'initializes with provided parameters' do
      expect(subject.req).to eq(mock_request)
      expect(subject.sess).to eq(mock_session)
      expect(subject.user).to eq(mock_user)
      expect(subject.locale).to eq('en')
      # Props are normalized to string keys
      expect(subject.client).to eq({ 'page_title' => 'Test Page', 'content' => 'Hello World' })
    end

    it 'uses default values when not provided' do
      context = described_class.new(nil)
      expect(context.sess).to be_a(Rhales::Adapters::AnonymousSession)
      expect(context.user).to be_a(Rhales::Adapters::AnonymousAuth)
      expect(context.locale).to eq('en')
    end

    it 'freezes the context after creation' do
      expect(subject).to be_frozen
    end
  end

  describe '#get' do
    subject { described_class.new(mock_request, client: props) }

    it 'retrieves runtime data' do
      expect(subject.get('csrf_token')).to eq('test-csrf')
      expect(subject.get('nonce')).to eq('test-nonce')
    end

    it 'retrieves props data' do
      expect(subject.get('page_title')).to eq('Test Page')
      expect(subject.get('content')).to eq('Hello World')
    end

    it 'retrieves computed data' do
      expect(subject.get('authenticated')).to be(true)
      expect(subject.get('theme_class')).to eq('theme-dark')
    end

    it 'retrieves app data through app namespace' do
      expect(subject.get('app.csrf_token')).to eq('test-csrf')
      expect(subject.get('app.nonce')).to eq('test-nonce')
      expect(subject.get('app.authenticated')).to be(true)
      expect(subject.get('app.theme_class')).to eq('theme-dark')
    end

    it 'has app_data attribute' do
      expect(subject.server).to be_a(Hash)
      expect(subject.server['csrf_token']).to eq('test-csrf')
      expect(subject.server['authenticated']).to be(true)
    end

    it 'accesses environment through app namespace' do
      expect(subject.get('app.environment')).to eq('test')
      expect(subject.get('environment')).to eq('test')
    end

    it 'supports dot notation' do
      nested_data = { user: { profile: { name: 'John' } } }
      context     = described_class.new(nil, client: nested_data)
      expect(context.get('user.profile.name')).to eq('John')
    end

    it 'returns nil for non-existent variables' do
      expect(subject.get('non_existent')).to be_nil
    end
  end

  describe '#variable?' do
    subject { described_class.new(mock_request, client: props) }

    it 'returns true for existing variables' do
      expect(subject.variable?('page_title')).to be(true)
      expect(subject.variable?('csrf_token')).to be(true)
    end

    it 'returns false for non-existent variables' do
      expect(subject.variable?('non_existent')).to be(false)
    end
  end

  describe '#available_variables' do
    subject { described_class.new(nil, client: { user: { name: 'Test' } }) }

    it 'returns list of available variable paths' do
      variables = subject.available_variables
      expect(variables).to include('user')
      expect(variables).to include('user.name')
      expect(variables).to include('environment')
      expect(variables).to include('authenticated')
    end
  end

  describe '.for_view' do
    it 'creates context with props data' do
      context = described_class.for_view(mock_request, test_data: 'value')
      expect(context.locale).to eq('en')  # Uses default when no Accept-Language header
      expect(context.get('test_data')).to eq('value')
    end
  end

  describe 'locale parsing' do
    it 'parses simple locale from HTTP_ACCEPT_LANGUAGE' do
      req = double('request', env: { 'HTTP_ACCEPT_LANGUAGE' => 'es' })
      context = described_class.new(req)
      expect(context.locale).to eq('es')
    end

    it 'parses locale with region from HTTP_ACCEPT_LANGUAGE' do
      req = double('request', env: { 'HTTP_ACCEPT_LANGUAGE' => 'es-ES' })
      context = described_class.new(req)
      expect(context.locale).to eq('es-ES')
    end

    it 'parses first locale from complex Accept-Language header' do
      req = double('request', env: { 'HTTP_ACCEPT_LANGUAGE' => 'es-ES,es;q=0.9,en;q=0.8' })
      context = described_class.new(req)
      expect(context.locale).to eq('es-ES')
    end

    it 'ignores quality values and extracts first locale' do
      req = double('request', env: { 'HTTP_ACCEPT_LANGUAGE' => 'fr;q=0.7,es;q=0.9' })
      context = described_class.new(req)
      expect(context.locale).to eq('fr')
    end

    it 'handles whitespace in Accept-Language header' do
      req = double('request', env: { 'HTTP_ACCEPT_LANGUAGE' => ' es-MX , en ; q=0.8 ' })
      context = described_class.new(req)
      expect(context.locale).to eq('es-MX')
    end

    it 'falls back to default when Accept-Language is empty' do
      req = double('request', env: { 'HTTP_ACCEPT_LANGUAGE' => '' })
      context = described_class.new(req)
      expect(context.locale).to eq('en')
    end

    it 'prefers custom rhales.locale over HTTP_ACCEPT_LANGUAGE' do
      req = double('request', env: {
        'rhales.locale' => 'fr',
        'HTTP_ACCEPT_LANGUAGE' => 'es'
      })
      context = described_class.new(req)
      expect(context.locale).to eq('fr')
    end

    it 'uses default when no locale headers present' do
      req = double('request', env: {})
      context = described_class.new(req)
      expect(context.locale).to eq('en')
    end
  end

  describe '.minimal' do
    it 'creates minimal context for testing' do
      context = described_class.minimal(client: { test: 'data' })
      expect(context.req).to be_nil
      expect(context.sess).to be_a(Rhales::Adapters::AnonymousSession)
      expect(context.user).to be_a(Rhales::Adapters::AnonymousAuth)
      expect(context.locale).to eq('en')
      expect(context.get('test')).to eq('data')
    end
  end

  describe 'with custom configuration' do
    subject { described_class.new(nil, config: custom_config) }

    let(:custom_config) do
      config                 = Rhales::Configuration.new
      config.default_locale  = 'fr'
      config.app_environment = 'staging'
      config.features        = { custom_feature: true }
      config
    end

    it 'uses custom configuration' do
      expect(subject.locale).to eq('fr')  # Uses custom default_locale from config
      expect(subject.get('environment')).to eq('staging')
      expect(subject.get('features.custom_feature')).to be(true)
    end

    it 'HTTP_ACCEPT_LANGUAGE overrides custom default_locale' do
      req = double('request', env: { 'HTTP_ACCEPT_LANGUAGE' => 'es' })
      context = described_class.new(req, config: custom_config)
      expect(context.locale).to eq('es')  # Request header takes precedence
    end
  end

  describe 'builder pattern methods' do
    subject { described_class.new(mock_request, client: { name: 'John', age: 30 }, server: { page_title: 'Test' }) }

    describe '#with_client' do
      it 'creates new context with replaced client data' do
        new_context = subject.with_client({ name: 'Jane', email: 'jane@example.com' })

        # New context has updated client data
        expect(new_context.get('name')).to eq('Jane')
        expect(new_context.get('email')).to eq('jane@example.com')
        expect(new_context.get('age')).to be_nil

        # Original context is unchanged (immutable)
        expect(subject.get('name')).to eq('John')
        expect(subject.get('age')).to eq(30)

        # Server data is preserved
        expect(new_context.get('page_title')).to eq('Test')
      end
    end

    describe '#with_server' do
      it 'creates new context with replaced server data' do
        new_context = subject.with_server({ page_title: 'New Title', subtitle: 'Subtitle' })

        # New context has updated server data
        expect(new_context.get('page_title')).to eq('New Title')
        expect(new_context.get('subtitle')).to eq('Subtitle')

        # Original context is unchanged
        expect(subject.get('page_title')).to eq('Test')
        expect(subject.get('subtitle')).to be_nil

        # Client data is preserved
        expect(new_context.get('name')).to eq('John')
        expect(new_context.get('age')).to eq(30)
      end
    end

    describe '#merge_client' do
      it 'creates new context with merged client data' do
        new_context = subject.merge_client({ age: 31, city: 'NYC' })

        # New context has merged client data
        expect(new_context.get('name')).to eq('John')
        expect(new_context.get('age')).to eq(31) # Updated
        expect(new_context.get('city')).to eq('NYC') # Added

        # Original context is unchanged
        expect(subject.get('name')).to eq('John')
        expect(subject.get('age')).to eq(30)
        expect(subject.get('city')).to be_nil

        # Server data is preserved
        expect(new_context.get('page_title')).to eq('Test')
      end
    end

    it 'preserves request, session, and user in new contexts' do
      new_context = subject.merge_client({ new_field: 'value' })

      expect(new_context.req).to eq(mock_request)
      expect(new_context.sess).to eq(mock_session)
      expect(new_context.user).to eq(mock_user)
      expect(new_context.locale).to eq('en')
    end

    it 'maintains immutability of new contexts' do
      new_context = subject.with_client({ name: 'Jane' })
      expect(new_context).to be_frozen
    end
  end

  describe 'CSP nonce generation' do
    context 'with existing nonce in request env' do
      let(:mock_request_with_nonce) {
        double('request', env: { 'nonce' => 'existing-nonce' })
      }
      subject { described_class.new(mock_request_with_nonce) }

      it 'uses existing nonce' do
        expect(subject.get('nonce')).to eq('existing-nonce')
      end
    end

    context 'with auto_nonce enabled' do
      let(:config) do
        config = Rhales::Configuration.new
        config.auto_nonce = true
        config.csp_enabled = false
        config
      end
      let(:mock_request_no_nonce) { double('request', env: {}) }
      subject { described_class.new(mock_request_no_nonce, config: config) }

      it 'generates nonce automatically' do
        nonce = subject.get('nonce')
        expect(nonce).to be_a(String)
        expect(nonce.length).to eq(32)
        expect(nonce).to match(/\A[0-9a-f]{32}\z/)
      end
    end

    context 'with CSP enabled and nonce required' do
      let(:config) do
        config = Rhales::Configuration.new
        config.csp_enabled = true
        config.auto_nonce = false
        config.csp_policy = {
          'script-src' => ["'self'", "'nonce-{{nonce}}'"]
        }
        config
      end
      let(:mock_request_no_nonce) { double('request', env: {}) }
      subject { described_class.new(mock_request_no_nonce, config: config) }

      it 'generates nonce when CSP requires it' do
        nonce = subject.get('nonce')
        expect(nonce).to be_a(String)
        expect(nonce.length).to eq(32)
        expect(nonce).to match(/\A[0-9a-f]{32}\z/)
      end
    end

    context 'with CSP enabled but no nonce required' do
      let(:config) do
        config = Rhales::Configuration.new
        config.csp_enabled = true
        config.auto_nonce = false
        config.csp_policy = {
          'script-src' => ["'self'"]
        }
        config
      end
      let(:mock_request_no_nonce) { double('request', env: {}) }
      subject { described_class.new(mock_request_no_nonce, config: config) }

      it 'does not generate nonce' do
        expect(subject.get('nonce')).to be_nil
      end
    end

    context 'without request object' do
      let(:config) do
        config = Rhales::Configuration.new
        config.auto_nonce = true
        config
      end
      subject { described_class.new(nil, config: config) }

      it 'generates nonce even without request' do
        nonce = subject.get('nonce')
        expect(nonce).to be_a(String)
        expect(nonce.length).to eq(32)
        expect(nonce).to match(/\A[0-9a-f]{32}\z/)
      end
    end
  end
end
