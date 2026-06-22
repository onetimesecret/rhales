# spec/rhales/configuration_schema_projection_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Rhales::Configuration#schema_projection' do
  let(:config) { Rhales::Configuration.new }

  it 'defaults to :off (backward-compatible advisory behavior)' do
    expect(config.schema_projection).to eq(:off)
  end

  [:off, :strip, :strict].each do |mode|
    it "accepts #{mode.inspect}" do
      config.schema_projection = mode
      expect(config.schema_projection).to eq(mode)
    end
  end

  it 'coerces string values to symbols' do
    config.schema_projection = 'strict'
    expect(config.schema_projection).to eq(:strict)
  end

  it 'rejects unknown modes with a helpful ArgumentError' do
    expect { config.schema_projection = :loose }
      .to raise_error(ArgumentError, /Invalid schema_projection/)
  end
end
