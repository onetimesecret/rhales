# spec/rhales/csp_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Rhales::CSP do
  let(:config) { Rhales::Configuration.new }
  let(:nonce) { 'abc123' }

  subject { described_class.new(config, nonce: nonce) }

  describe '#initialize' do
    it 'stores config and nonce' do
      expect(subject.config).to eq(config)
      expect(subject.nonce).to eq(nonce)
    end

    it 'accepts nil nonce' do
      csp = described_class.new(config, nonce: nil)
      expect(csp.nonce).to be_nil
    end
  end

  describe '#build_header' do
    context 'when CSP is disabled' do
      before { config.csp_enabled = false }

      it 'returns nil' do
        expect(subject.build_header).to be_nil
      end
    end

    context 'when CSP is enabled' do
      before { config.csp_enabled = true }

      context 'with default policy' do
        it 'builds proper CSP header' do
          header = subject.build_header
          expect(header).to include("default-src 'self'")
          expect(header).to include("script-src 'self' 'nonce-abc123'")
          expect(header).to include("style-src 'self' 'nonce-abc123' 'unsafe-hashes'")
          expect(header).to include("img-src 'self' data:")
          expect(header).to include("font-src 'self'")
          expect(header).to include("connect-src 'self'")
          expect(header).to include("base-uri 'self'")
          expect(header).to include("form-action 'self'")
          expect(header).to include("frame-ancestors 'none'")
          expect(header).to include("object-src 'none'")
          expect(header).to include("upgrade-insecure-requests")
        end

        it 'separates directives with semicolons' do
          header = subject.build_header
          expect(header).to match(/; /)
        end
      end

      context 'with custom policy' do
        before do
          config.csp_policy = {
            'default-src' => ["'self'"],
            'script-src' => ["'self'", "'nonce-{{nonce}}'"],
            'style-src' => ["'self'", "'unsafe-inline'"]
          }
        end

        it 'builds custom CSP header' do
          header = subject.build_header
          expect(header).to include("default-src 'self'")
          expect(header).to include("script-src 'self' 'nonce-abc123'")
          expect(header).to include("style-src 'self' 'unsafe-inline'")
          expect(header).not_to include("img-src")
        end
      end

      context 'with empty directive sources' do
        before do
          config.csp_policy = {
            'default-src' => ["'self'"],
            'upgrade-insecure-requests' => []
          }
        end

        it 'includes directives with empty sources' do
          header = subject.build_header
          expect(header).to include("default-src 'self'")
          expect(header).to include("upgrade-insecure-requests")
        end
      end

      context 'without nonce' do
        subject { described_class.new(config, nonce: nil) }

        it 'does not interpolate nonce' do
          header = subject.build_header
          expect(header).to include("script-src 'self' 'nonce-{{nonce}}'")
          expect(header).not_to include("'nonce-abc123'")
        end
      end
    end
  end

  describe '.generate_nonce' do
    it 'generates a 32-character hex string' do
      nonce = described_class.generate_nonce
      expect(nonce).to match(/\A[0-9a-f]{32}\z/)
    end

    it 'generates unique nonces' do
      nonce1 = described_class.generate_nonce
      nonce2 = described_class.generate_nonce
      expect(nonce1).not_to eq(nonce2)
    end
  end

  describe '#validate_policy!' do
    before { config.csp_enabled = true }

    context 'with valid policy' do
      it 'does not raise error' do
        expect { subject.validate_policy! }.not_to raise_error
      end
    end

    context 'with invalid policy type' do
      before { config.csp_policy = 'invalid' }

      it 'raises configuration error' do
        expect { subject.validate_policy! }.to raise_error(Rhales::Configuration::ConfigurationError, /must be a hash/)
      end
    end

    context 'with invalid directive sources' do
      before do
        config.csp_policy = {
          'script-src' => 'invalid'
        }
      end

      it 'raises configuration error' do
        expect { subject.validate_policy! }.to raise_error(Rhales::Configuration::ConfigurationError, /must be an array/)
      end
    end

    context 'with dangerous unsafe-eval' do
      before do
        config.csp_policy = {
          'script-src' => ["'self'", "'unsafe-eval'"]
        }
      end

      it 'raises configuration error' do
        expect { subject.validate_policy! }.to raise_error(Rhales::Configuration::ConfigurationError, /dangerous 'unsafe-eval'/)
      end
    end

    context 'with dangerous unsafe-inline in script-src' do
      before do
        config.csp_policy = {
          'script-src' => ["'self'", "'unsafe-inline'"]
        }
      end

      it 'raises configuration error' do
        expect { subject.validate_policy! }.to raise_error(Rhales::Configuration::ConfigurationError, /dangerous 'unsafe-inline'/)
      end
    end

    context 'with unsafe-inline in style-src' do
      before do
        config.csp_policy = {
          'style-src' => ["'self'", "'unsafe-inline'"]
        }
      end

      it 'does not raise error for style-src' do
        expect { subject.validate_policy! }.not_to raise_error
      end
    end

    context 'when CSP is disabled' do
      before { config.csp_enabled = false }

      it 'does not validate policy' do
        expect { subject.validate_policy! }.not_to raise_error
      end
    end
  end

  describe '#nonce_required?' do
    context 'when CSP is disabled' do
      before { config.csp_enabled = false }

      it 'returns false' do
        expect(subject.nonce_required?).to be false
      end
    end

    context 'when CSP is enabled' do
      before { config.csp_enabled = true }

      context 'with nonce placeholder in policy' do
        before do
          config.csp_policy = {
            'script-src' => ["'self'", "'nonce-{{nonce}}'"]
          }
        end

        it 'returns true' do
          expect(subject.nonce_required?).to be true
        end
      end

      context 'without nonce placeholder in policy' do
        before do
          config.csp_policy = {
            'script-src' => ["'self'"]
          }
        end

        it 'returns false' do
          expect(subject.nonce_required?).to be false
        end
      end
    end
  end

  describe 'nonce interpolation' do
    let(:custom_nonce) { 'xyz789' }
    subject { described_class.new(config, nonce: custom_nonce) }

    before do
      config.csp_enabled = true
      config.csp_policy = {
        'script-src' => ["'self'", "'nonce-{{nonce}}'"],
        'style-src' => ["'self'", "'nonce-{{nonce}}'"],
        'img-src' => ["'self'", 'data:']
      }
    end

    it 'interpolates nonce in all directives' do
      header = subject.build_header
      expect(header).to include("script-src 'self' 'nonce-xyz789'")
      expect(header).to include("style-src 'self' 'nonce-xyz789'")
      expect(header).to include("img-src 'self' data:")
      expect(header).not_to include('{{nonce}}')
    end
  end
end
