# spec/rhales/configuration_spec.rb
# frozen_string_literal: true

require 'spec_helper'

# rubocop:disable RSpec/MultipleExpectations
# rubocop:disable RSpec/MultipleDescribes
RSpec.describe Rhales::Configuration do
  describe '#initialize' do
    subject { described_class.new }

    it 'sets default values' do
      expect(subject.default_locale).to eq('en')
      expect(subject.app_environment).to eq('development')
      expect(subject.development_enabled).to be(false)
      expect(subject.template_paths).to eq([])
      expect(subject.features).to eq({})
      expect(subject.csp_enabled).to be(true)
      expect(subject.auto_nonce).to be(true)
      expect(subject.csp_policy).to be_a(Hash)
      expect(subject.hydration_mismatch_format).to eq(:compact)
      expect(subject.hydration_authority).to eq(:schema)
    end
  end

  describe '#api_base_url' do
    subject { described_class.new }

    context 'when api_base_url is explicitly set' do
      before { subject.api_base_url = 'https://custom.api.com' }

      it 'returns the explicit value' do
        expect(subject.api_base_url).to eq('https://custom.api.com')
      end
    end

    context 'when site configuration is provided' do
      before do
        subject.site_host        = 'example.com'
        subject.site_ssl_enabled = true
      end

      it 'builds URL from site configuration' do
        expect(subject.api_base_url).to eq('https://example.com/api')
      end
    end

    context 'when no site host is configured' do
      it 'returns nil' do
        expect(subject.api_base_url).to be_nil
      end
    end
  end

  describe '#development?' do
    subject { described_class.new }

    context 'when development_enabled is true' do
      before { subject.development_enabled = true }

      it 'returns true' do
        expect(subject.development?).to be(true)
      end
    end

    context 'when app_environment is development' do
      before { subject.app_environment = 'development' }

      it 'returns true' do
        expect(subject.development?).to be(true)
      end
    end

    context 'when neither condition is met' do
      before do
        subject.development_enabled = false
        subject.app_environment     = 'production'
      end

      it 'returns false' do
        expect(subject.development?).to be(false)
      end
    end
  end

  describe '#feature_enabled?' do
    subject { described_class.new }

    before { subject.features = { 'dark_mode' => true, 'beta_features' => false } }

    it 'returns true for enabled features' do
      expect(subject.feature_enabled?(:dark_mode)).to be(true)
      expect(subject.feature_enabled?('dark_mode')).to be(true)
    end

    it 'returns false for disabled features' do
      expect(subject.feature_enabled?(:beta_features)).to be(false)
      expect(subject.feature_enabled?('beta_features')).to be(false)
    end

    it 'returns false for undefined features' do
      expect(subject.feature_enabled?(:undefined)).to be(false)
    end
  end

  describe '#validate!' do
    subject { described_class.new }

    context 'with valid configuration' do
      it 'does not raise an error' do
        expect { subject.validate! }.not_to raise_error
      end
    end

    context 'with empty locale' do
      before { subject.default_locale = '' }

      it 'raises ConfigurationError' do
        expect { subject.validate! }.to raise_error(Rhales::Configuration::ConfigurationError)
      end
    end

    context 'with negative cache TTL' do
      before { subject.cache_ttl = -1 }

      it 'raises ConfigurationError' do
        expect { subject.validate! }.to raise_error(Rhales::Configuration::ConfigurationError)
      end
    end
  end

  describe '#default_csp_policy' do
    subject { described_class.new }

    it 'returns secure default CSP policy' do
      policy = subject.default_csp_policy
      expect(policy).to be_a(Hash)
      expect(policy).to be_frozen
      expect(policy['default-src']).to eq(["'self'"])
      expect(policy['script-src']).to include("'self'")
      expect(policy['script-src']).to include("'nonce-{{nonce}}'")
      expect(policy['style-src']).to include("'self'")
      expect(policy['style-src']).to include("'nonce-{{nonce}}'")
      expect(policy['frame-ancestors']).to eq(["'none'"])
      expect(policy['object-src']).to eq(["'none'"])
      expect(policy['upgrade-insecure-requests']).to eq([])
    end
  end

  describe '#hydration_mismatch_format' do
    subject { described_class.new }

    it 'sets hydration_mismatch_format to :compact by default' do
      expect(subject.hydration_mismatch_format).to eq(:compact)
    end

    it 'allows setting hydration_mismatch_format to :compact' do
      subject.hydration_mismatch_format = :compact
      expect(subject.hydration_mismatch_format).to eq(:compact)
    end

    it 'allows setting hydration_mismatch_format to :multiline' do
      subject.hydration_mismatch_format = :multiline
      expect(subject.hydration_mismatch_format).to eq(:multiline)
    end

    it 'allows setting hydration_mismatch_format to :sidebyside' do
      subject.hydration_mismatch_format = :sidebyside
      expect(subject.hydration_mismatch_format).to eq(:sidebyside)
    end

    it 'allows setting hydration_mismatch_format to :json' do
      subject.hydration_mismatch_format = :json
      expect(subject.hydration_mismatch_format).to eq(:json)
    end
  end

  describe '#hydration_authority' do
    subject { described_class.new }

    it 'sets hydration_authority to :schema by default' do
      expect(subject.hydration_authority).to eq(:schema)
    end

    it 'allows setting hydration_authority to :schema' do
      subject.hydration_authority = :schema
      expect(subject.hydration_authority).to eq(:schema)
    end

    it 'allows setting hydration_authority to :data' do
      subject.hydration_authority = :data
      expect(subject.hydration_authority).to eq(:data)
    end
  end
end

RSpec.describe Rhales do
  describe '.configure' do
    before { described_class.reset_configuration! }

    it 'yields configuration object' do
      expect { |b| described_class.configure(&b) }.to yield_with_args(Rhales::Configuration)
    end

    it 'validates and freezes configuration' do
      config = described_class.configure do |c|
        c.default_locale = 'es'
      end

      expect(config).to be_frozen
      expect(config.default_locale).to eq('es')
    end
  end

  describe '.configuration' do
    it 'returns configuration instance' do
      expect(described_class.configuration).to be_a(Rhales::Configuration)
    end

    it 'returns same instance on multiple calls' do
      config1 = described_class.configuration
      config2 = described_class.configuration
      expect(config1).to be(config2)
    end
  end

  describe '.reset_configuration!' do
    it 'resets configuration' do
      original_config = described_class.configuration
      described_class.reset_configuration!
      new_config      = described_class.configuration
      expect(new_config).not_to be(original_config)
    end
  end

  describe '.logger' do
    before do
      # Reset logger before each test
      described_class.logger = nil
    end

    after do
      # Ensure logger is reset after each test
      described_class.logger = nil
    end

    it 'returns a logger instance' do
      expect(described_class.logger).to be_a(Logger)
    end

    it 'allows setting a custom logger' do
      custom_logger = Logger.new(STDOUT)
      described_class.logger = custom_logger
      expect(described_class.logger).to eq(custom_logger)
    end

    it 'defaults to a Logger instance when not set' do
      described_class.logger = nil
      expect(described_class.logger).to be_a(Logger)
    end
  end
end
