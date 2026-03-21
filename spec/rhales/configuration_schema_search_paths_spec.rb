# spec/rhales/configuration_schema_search_paths_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Rhales::Configuration do
  describe '#schema_search_paths' do
    subject { described_class.new }

    describe 'default value' do
      it 'defaults to an empty array' do
        expect(subject.schema_search_paths).to eq([])
      end

      it 'is an array type' do
        expect(subject.schema_search_paths).to be_an(Array)
      end
    end

    describe 'assignment' do
      it 'accepts an array of paths' do
        paths = ['/app/schemas', '/lib/shared/schemas']
        subject.schema_search_paths = paths
        expect(subject.schema_search_paths).to eq(paths)
      end

      it 'accepts an empty array' do
        subject.schema_search_paths = []
        expect(subject.schema_search_paths).to eq([])
      end

      it 'accepts a single path in an array' do
        subject.schema_search_paths = ['/single/path']
        expect(subject.schema_search_paths).to eq(['/single/path'])
      end
    end

    describe 'configuration block' do
      before { Rhales.reset_configuration! }

      it 'can be configured via Rhales.configure' do
        Rhales.configure do |config|
          config.schema_search_paths = ['/custom/schemas', '/shared/schemas']
        end

        expect(Rhales.config.schema_search_paths).to eq(['/custom/schemas', '/shared/schemas'])
      end

      it 'preserves paths through freeze' do
        Rhales.configure do |config|
          config.schema_search_paths = ['/frozen/path']
        end

        expect(Rhales.config.schema_search_paths).to eq(['/frozen/path'])
        expect(Rhales.config).to be_frozen
      end
    end

    describe 'validation' do
      # schema_search_paths validation is minimal - paths are validated at resolution time
      # This matches the pattern used by template_paths

      it 'does not raise on non-existent paths (validation is deferred)' do
        subject.schema_search_paths = ['/nonexistent/path']
        expect { subject.validate! }.not_to raise_error
      end

      it 'accepts relative paths' do
        subject.schema_search_paths = ['./schemas', '../shared/schemas']
        expect(subject.schema_search_paths).to eq(['./schemas', '../shared/schemas'])
      end
    end
  end
end
