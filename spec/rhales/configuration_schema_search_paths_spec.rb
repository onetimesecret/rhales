# spec/rhales/configuration_schema_search_paths_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

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
      let(:temp_dirs) { [] }

      before do
        Rhales.reset_configuration!
      end

      after do
        temp_dirs.each { |d| FileUtils.rm_rf(d) if Dir.exist?(d) }
      end

      it 'can be configured via Rhales.configure' do
        dir1 = Dir.mktmpdir('custom_schemas')
        dir2 = Dir.mktmpdir('shared_schemas')
        temp_dirs.push(dir1, dir2)

        Rhales.configure do |config|
          config.schema_search_paths = [dir1, dir2]
        end

        expect(Rhales.config.schema_search_paths).to eq([dir1, dir2])
      end

      it 'preserves paths through freeze' do
        dir = Dir.mktmpdir('frozen_path')
        temp_dirs.push(dir)

        Rhales.configure do |config|
          config.schema_search_paths = [dir]
        end

        expect(Rhales.config.schema_search_paths).to eq([dir])
        expect(Rhales.config).to be_frozen
      end
    end

    describe 'validation' do
      it 'raises on non-existent paths during validate!' do
        subject.schema_search_paths = ['/nonexistent/path']
        expect { subject.validate! }.to raise_error(
          Rhales::Configuration::ConfigurationError,
          /Schema search path does not exist/
        )
      end

      it 'accepts relative paths that exist' do
        # Use current directory which always exists
        subject.schema_search_paths = ['.']
        expect { subject.validate! }.not_to raise_error
      end

      it 'validates all paths and reports all errors' do
        subject.schema_search_paths = ['/nonexistent/path1', '/nonexistent/path2']
        expect { subject.validate! }.to raise_error(
          Rhales::Configuration::ConfigurationError,
          /path1.*path2|path2.*path1/
        )
      end
    end
  end
end
