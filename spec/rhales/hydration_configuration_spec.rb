# spec/rhales/hydration_configuration_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Rhales::Configuration do
  let(:config) { described_class.new }

  describe 'hydration configuration' do
    it 'has a hydration configuration object' do
      expect(config.hydration).to be_a(Rhales::HydrationConfiguration)
    end

    it 'allows setting hydration injection strategy' do
      config.hydration.injection_strategy = :early
      expect(config.hydration.injection_strategy).to eq(:early)
    end

    it 'allows setting custom mount point selectors' do
      custom_selectors = ['#my-app', '.vue-root', '[data-custom-mount]']
      config.hydration.mount_point_selectors = custom_selectors
      expect(config.hydration.mount_point_selectors).to eq(custom_selectors)
    end

    it 'allows setting fallback behavior' do
      config.hydration.fallback_to_late = false
      expect(config.hydration.fallback_to_late).to eq(false)
    end
  end
end

RSpec.describe Rhales::HydrationConfiguration do
  let(:hydration_config) { described_class.new }

  describe 'default values' do
    it 'defaults injection strategy to :late' do
      expect(hydration_config.injection_strategy).to eq(:late)
    end

    it 'has default mount point selectors' do
      expected_selectors = ['#app', '#root', '[data-rsfc-mount]', '[data-mount]']
      expect(hydration_config.mount_point_selectors).to eq(expected_selectors)
    end

    it 'defaults fallback_to_late to true' do
      expect(hydration_config.fallback_to_late).to eq(true)
    end
  end

  describe 'configuration methods' do
    it 'allows setting injection strategy' do
      hydration_config.injection_strategy = :early
      expect(hydration_config.injection_strategy).to eq(:early)
    end

    it 'allows setting mount point selectors' do
      selectors = ['#custom-app', '.my-root']
      hydration_config.mount_point_selectors = selectors
      expect(hydration_config.mount_point_selectors).to eq(selectors)
    end

    it 'allows setting fallback behavior' do
      hydration_config.fallback_to_late = false
      expect(hydration_config.fallback_to_late).to eq(false)
    end
  end
end

RSpec.describe 'Rhales configuration integration' do
  before do
    Rhales.reset_configuration!
  end

  after do
    Rhales.reset_configuration!
  end

  it 'allows configuring hydration options through Rhales.configure' do
    Rhales.configure do |config|
      config.hydration.injection_strategy = :early
      config.hydration.mount_point_selectors = ['#my-app', '.custom-root']
      config.hydration.fallback_to_late = false
    end

    config = Rhales.configuration
    expect(config.hydration.injection_strategy).to eq(:early)
    expect(config.hydration.mount_point_selectors).to eq(['#my-app', '.custom-root'])
    expect(config.hydration.fallback_to_late).to eq(false)
  end

  it 'maintains backwards compatibility with existing configuration' do
    Rhales.configure do |config|
      config.default_locale = 'fr'
      config.csp_enabled = false
      # Don't configure hydration - should use defaults
    end

    config = Rhales.configuration
    expect(config.default_locale).to eq('fr')
    expect(config.csp_enabled).to eq(false)
    expect(config.hydration.injection_strategy).to eq(:late) # default
  end
end
