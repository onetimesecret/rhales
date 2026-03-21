# spec/rhales/utils/schema_extractor_search_paths_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'tmpdir'

RSpec.describe Rhales::SchemaExtractor do
  describe 'schema_search_paths configuration support' do
    let(:temp_dir) { Dir.mktmpdir('rhales_search_paths_test') }
    let(:templates_dir) { File.join(temp_dir, 'templates') }
    let(:shared_schemas_dir) { File.join(temp_dir, 'shared_schemas') }
    let(:lib_schemas_dir) { File.join(temp_dir, 'lib', 'schemas') }

    before do
      FileUtils.mkdir_p(templates_dir)
      FileUtils.mkdir_p(shared_schemas_dir)
      FileUtils.mkdir_p(lib_schemas_dir)
    end

    after do
      FileUtils.remove_entry(temp_dir) if File.exist?(temp_dir)
    end

    def create_file(path, content)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, content)
    end

    let(:common_schema_content) do
      <<~TS
        import { z } from 'zod';
        const schema = z.object({ common: z.string() });
        export default schema;
      TS
    end

    describe 'current behavior (relative to template)' do
      # Document the current behavior before search paths are implemented

      it 'resolves src paths relative to template directory' do
        create_file(File.join(templates_dir, 'schemas', 'local.ts'), common_schema_content)
        create_file(File.join(templates_dir, 'page.rue'), <<~RUE)
          <schema src="schemas/local.ts" lang="js-zod" window="__DATA__">
          </schema>
          <template><div>Test</div></template>
        RUE

        extractor = described_class.new(templates_dir)
        result = extractor.extract_from_file(File.join(templates_dir, 'page.rue'))

        expect(result[:resolved_path]).to eq(File.join(templates_dir, 'schemas', 'local.ts'))
        expect(result[:schema_code]).to include('common: z.string()')
      end

      it 'raises error when schema file not found in relative path' do
        create_file(File.join(templates_dir, 'missing_ref.rue'), <<~RUE)
          <schema src="schemas/nonexistent.ts" lang="js-zod" window="__DATA__">
          </schema>
          <template><div>Test</div></template>
        RUE

        extractor = described_class.new(templates_dir)

        expect {
          extractor.extract_from_file(File.join(templates_dir, 'missing_ref.rue'))
        }.to raise_error(Rhales::SchemaExtractor::ExtractionError, /not found/i)
      end
    end

    # Tests for search paths resolution feature
    describe 'search paths resolution' do
      before do
        # Configure search paths via Rhales configuration
        Rhales.reset_configuration!
        Rhales.configure do |config|
          config.schema_search_paths = [shared_schemas_dir, lib_schemas_dir]
          config.template_paths = [templates_dir]
        end
      end

      context 'when src is found in search paths' do
        before do
          create_file(File.join(shared_schemas_dir, 'common.ts'), common_schema_content)
          create_file(File.join(templates_dir, 'uses_shared.rue'), <<~RUE)
            <schema src="common.ts" lang="js-zod" window="__DATA__">
            </schema>
            <template><div>Test</div></template>
          RUE
        end

        it 'resolves schema from search paths when not found relative to template' do
          extractor = described_class.new(templates_dir)
          result = extractor.extract_from_file(File.join(templates_dir, 'uses_shared.rue'))

          expect(result[:resolved_path]).to eq(File.join(shared_schemas_dir, 'common.ts'))
        end

        it 'searches paths in order (first match wins)' do
          # Create same file in both search paths
          create_file(File.join(shared_schemas_dir, 'duplicate.ts'), "const schema = z.object({ from: z.literal('shared') });")
          create_file(File.join(lib_schemas_dir, 'duplicate.ts'), "const schema = z.object({ from: z.literal('lib') });")

          create_file(File.join(templates_dir, 'uses_duplicate.rue'), <<~RUE)
            <schema src="duplicate.ts" lang="js-zod" window="__DATA__">
            </schema>
            <template><div>Test</div></template>
          RUE

          extractor = described_class.new(templates_dir)
          result = extractor.extract_from_file(File.join(templates_dir, 'uses_duplicate.rue'))

          # First path in search_paths should win
          expect(result[:resolved_path]).to eq(File.join(shared_schemas_dir, 'duplicate.ts'))
          expect(result[:schema_code]).to include("'shared'")
        end
      end

      context 'when src is not found in any search path' do
        it 'raises error with all searched locations' do
          create_file(File.join(templates_dir, 'not_found.rue'), <<~RUE)
            <schema src="missing.ts" lang="js-zod" window="__DATA__">
            </schema>
            <template><div>Test</div></template>
          RUE

          extractor = described_class.new(templates_dir)

          expect {
            extractor.extract_from_file(File.join(templates_dir, 'not_found.rue'))
          }.to raise_error(Rhales::SchemaExtractor::ExtractionError, /not found/i)
        end
      end

      context 'priority: template-relative over search paths' do
        it 'prefers template-relative path when file exists in both locations' do
          # Create in both template dir and search path
          create_file(File.join(templates_dir, 'local_priority.ts'), "const schema = z.object({ from: z.literal('template') });")
          create_file(File.join(shared_schemas_dir, 'local_priority.ts'), "const schema = z.object({ from: z.literal('shared') });")

          create_file(File.join(templates_dir, 'priority_test.rue'), <<~RUE)
            <schema src="local_priority.ts" lang="js-zod" window="__DATA__">
            </schema>
            <template><div>Test</div></template>
          RUE

          extractor = described_class.new(templates_dir)
          result = extractor.extract_from_file(File.join(templates_dir, 'priority_test.rue'))

          # Template-relative should win
          expect(result[:resolved_path]).to eq(File.join(templates_dir, 'local_priority.ts'))
          expect(result[:schema_code]).to include("'template'")
        end
      end

      context 'security with search paths' do
        it 'prevents path traversal in search path resolution' do
          create_file(File.join(templates_dir, 'traversal_via_search.rue'), <<~RUE)
            <schema src="../../../etc/passwd" lang="js-zod" window="__DATA__">
            </schema>
            <template><div>Test</div></template>
          RUE

          extractor = described_class.new(templates_dir)

          expect {
            extractor.extract_from_file(File.join(templates_dir, 'traversal_via_search.rue'))
          }.to raise_error(Rhales::SchemaExtractor::ExtractionError, /path traversal|not allowed/i)
        end

        it 'only searches within configured search paths' do
          # Schema exists outside search paths
          outside_path = File.join(temp_dir, 'outside', 'secret.ts')
          create_file(outside_path, 'secret content')

          create_file(File.join(templates_dir, 'outside_search.rue'), <<~RUE)
            <schema src="../outside/secret.ts" lang="js-zod" window="__DATA__">
            </schema>
            <template><div>Test</div></template>
          RUE

          extractor = described_class.new(templates_dir)

          expect {
            extractor.extract_from_file(File.join(templates_dir, 'outside_search.rue'))
          }.to raise_error(Rhales::SchemaExtractor::ExtractionError)
        end
      end
    end

    describe 'empty search paths' do
      before do
        Rhales.reset_configuration!
        Rhales.configure do |config|
          config.schema_search_paths = []
          config.template_paths = [templates_dir]
        end
      end

      it 'falls back to template-relative resolution with empty search paths' do
        create_file(File.join(templates_dir, 'schemas', 'fallback.ts'), common_schema_content)
        create_file(File.join(templates_dir, 'fallback_test.rue'), <<~RUE)
          <schema src="schemas/fallback.ts" lang="js-zod" window="__DATA__">
          </schema>
          <template><div>Test</div></template>
        RUE

        extractor = described_class.new(templates_dir)
        result = extractor.extract_from_file(File.join(templates_dir, 'fallback_test.rue'))

        expect(result[:resolved_path]).to eq(File.join(templates_dir, 'schemas', 'fallback.ts'))
      end
    end
  end
end
