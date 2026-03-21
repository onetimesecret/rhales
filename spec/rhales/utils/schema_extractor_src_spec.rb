# spec/rhales/utils/schema_extractor_src_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'tmpdir'

RSpec.describe Rhales::SchemaExtractor do
  describe 'external schema src attribute support' do
    let(:temp_dir) { Dir.mktmpdir('rhales_schema_src_test') }
    let(:templates_dir) { File.join(temp_dir, 'templates') }
    let(:schemas_dir) { File.join(templates_dir, 'schemas') }

    before do
      FileUtils.mkdir_p(schemas_dir)
    end

    after do
      FileUtils.remove_entry(temp_dir) if File.exist?(temp_dir)
    end

    def create_file(path, content)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, content)
    end

    describe '#extract_from_file with src attribute' do
      let(:external_schema_content) do
        <<~TS
          import { z } from 'zod';

          const schema = z.object({
            appName: z.string(),
            version: z.string()
          });

          export default schema;
        TS
      end

      context 'path resolution' do
        it 'resolves src path relative to template directory' do
          create_file(File.join(schemas_dir, 'bootstrap.schema.ts'), external_schema_content)
          create_file(File.join(templates_dir, 'dashboard.rue'), <<~RUE)
            <schema src="schemas/bootstrap.schema.ts" lang="js-zod" window="__DATA__">
            </schema>

            <template>
            <div>Test</div>
            </template>
          RUE

          extractor = described_class.new(templates_dir)
          result = extractor.extract_from_file(File.join(templates_dir, 'dashboard.rue'))

          expect(result[:src]).to eq('schemas/bootstrap.schema.ts')
          expect(result[:resolved_path]).to eq(File.join(schemas_dir, 'bootstrap.schema.ts'))
          expect(result[:schema_code]).to include("z.object")
        end

        it 'resolves relative paths with ./ prefix' do
          create_file(File.join(schemas_dir, 'user.schema.ts'), external_schema_content)
          create_file(File.join(templates_dir, 'user.rue'), <<~RUE)
            <schema src="./schemas/user.schema.ts" lang="js-zod" window="__USER__">
            </schema>

            <template>
            <div>Test</div>
            </template>
          RUE

          extractor = described_class.new(templates_dir)
          result = extractor.extract_from_file(File.join(templates_dir, 'user.rue'))

          expect(result[:resolved_path]).to eq(File.join(schemas_dir, 'user.schema.ts'))
        end

        it 'resolves paths for nested templates' do
          nested_dir = File.join(templates_dir, 'pages', 'admin')
          nested_schemas = File.join(nested_dir, 'schemas')
          FileUtils.mkdir_p(nested_schemas)

          create_file(File.join(nested_schemas, 'admin.schema.ts'), external_schema_content)
          create_file(File.join(nested_dir, 'dashboard.rue'), <<~RUE)
            <schema src="schemas/admin.schema.ts" lang="js-zod" window="__ADMIN__">
            </schema>

            <template>
            <div>Test</div>
            </template>
          RUE

          extractor = described_class.new(templates_dir)
          result = extractor.extract_from_file(File.join(nested_dir, 'dashboard.rue'))

          expect(result[:resolved_path]).to eq(File.join(nested_schemas, 'admin.schema.ts'))
        end
      end

      context 'inline schemas (no src)' do
        it 'continues to work with inline schemas' do
          create_file(File.join(templates_dir, 'inline.rue'), <<~RUE)
            <schema lang="js-zod" window="__DATA__">
            const schema = z.object({ name: z.string() });
            </schema>

            <template>
            <div>Test</div>
            </template>
          RUE

          extractor = described_class.new(templates_dir)
          result = extractor.extract_from_file(File.join(templates_dir, 'inline.rue'))

          expect(result[:src]).to be_nil
          expect(result[:resolved_path]).to be_nil
          expect(result[:schema_code]).to include("z.object")
        end
      end

      context 'error handling' do
        it 'raises error when src file does not exist' do
          create_file(File.join(templates_dir, 'missing_src.rue'), <<~RUE)
            <schema src="nonexistent/schema.ts" lang="js-zod" window="__DATA__">
            </schema>

            <template>
            <div>Test</div>
            </template>
          RUE

          extractor = described_class.new(templates_dir)

          expect {
            extractor.extract_from_file(File.join(templates_dir, 'missing_src.rue'))
          }.to raise_error(Rhales::SchemaExtractor::ExtractionError, /not found|does not exist/i)
        end

        it 'includes template name and src path in error message' do
          create_file(File.join(templates_dir, 'bad_ref.rue'), <<~RUE)
            <schema src="missing/file.ts" lang="js-zod" window="__DATA__">
            </schema>

            <template>
            <div>Test</div>
            </template>
          RUE

          extractor = described_class.new(templates_dir)

          expect {
            extractor.extract_from_file(File.join(templates_dir, 'bad_ref.rue'))
          }.to raise_error(Rhales::SchemaExtractor::ExtractionError) { |e|
            expect(e.message).to include('missing/file.ts')
          }
        end
      end

      context 'security - path traversal prevention' do
        it 'blocks path traversal attempts outside templates directory' do
          # Create a file outside templates that attacker might try to access
          outside_file = File.join(temp_dir, 'secret.txt')
          create_file(outside_file, 'SECRET DATA')

          create_file(File.join(templates_dir, 'malicious.rue'), <<~RUE)
            <schema src="../secret.txt" lang="js-zod" window="__DATA__">
            </schema>

            <template>
            <div>Test</div>
            </template>
          RUE

          extractor = described_class.new(templates_dir)

          expect {
            extractor.extract_from_file(File.join(templates_dir, 'malicious.rue'))
          }.to raise_error(Rhales::SchemaExtractor::ExtractionError, /path traversal|outside.*directory|not allowed/i)
        end

        it 'blocks deep path traversal attempts' do
          create_file(File.join(templates_dir, 'deep_traversal.rue'), <<~RUE)
            <schema src="../../../etc/passwd" lang="js-zod" window="__DATA__">
            </schema>

            <template>
            <div>Test</div>
            </template>
          RUE

          extractor = described_class.new(templates_dir)

          expect {
            extractor.extract_from_file(File.join(templates_dir, 'deep_traversal.rue'))
          }.to raise_error(Rhales::SchemaExtractor::ExtractionError, /path traversal|outside.*directory|not allowed/i)
        end

        it 'allows legitimate parent directory references within templates' do
          # Template in nested dir referencing schema in parent
          nested_dir = File.join(templates_dir, 'pages')
          FileUtils.mkdir_p(nested_dir)

          create_file(File.join(templates_dir, 'shared', 'common.schema.ts'), external_schema_content)
          create_file(File.join(nested_dir, 'page.rue'), <<~RUE)
            <schema src="../shared/common.schema.ts" lang="js-zod" window="__DATA__">
            </schema>

            <template>
            <div>Test</div>
            </template>
          RUE

          extractor = described_class.new(templates_dir)
          result = extractor.extract_from_file(File.join(nested_dir, 'page.rue'))

          # Should work because final path is still within templates_dir
          expect(result[:resolved_path]).to eq(File.join(templates_dir, 'shared', 'common.schema.ts'))
        end
      end
    end

    describe '#extract_all with mixed schemas' do
      let(:external_schema_content) do
        "const schema = z.object({ name: z.string() });"
      end

      before do
        create_file(File.join(schemas_dir, 'external.schema.ts'), external_schema_content)

        create_file(File.join(templates_dir, 'with_src.rue'), <<~RUE)
          <schema src="schemas/external.schema.ts" lang="js-zod" window="__DATA__">
          </schema>

          <template>
          <div>Test</div>
          </template>
        RUE

        create_file(File.join(templates_dir, 'inline_schema.rue'), <<~RUE)
          <schema lang="js-zod" window="__INLINE__">
          const schema = z.object({ id: z.number() });
          </schema>

          <template>
          <div>Test</div>
          </template>
        RUE

        create_file(File.join(templates_dir, 'no_schema.rue'), <<~RUE)
          <template>
          <div>No schema here</div>
          </template>
        RUE
      end

      it 'extracts both external and inline schemas' do
        extractor = described_class.new(templates_dir)
        results = extractor.extract_all

        expect(results.length).to eq(2)

        external = results.find { |r| r[:template_name] == 'with_src' }
        inline = results.find { |r| r[:template_name] == 'inline_schema' }

        expect(external[:src]).to eq('schemas/external.schema.ts')
        expect(external[:resolved_path]).not_to be_nil

        expect(inline[:src]).to be_nil
        expect(inline[:resolved_path]).to be_nil
      end
    end

    describe '#schema_stats with src tracking' do
      let(:external_schema_content) do
        "const schema = z.object({ name: z.string() });"
      end

      before do
        create_file(File.join(schemas_dir, 'ext.schema.ts'), external_schema_content)

        create_file(File.join(templates_dir, 'ext1.rue'), <<~RUE)
          <schema src="schemas/ext.schema.ts" lang="js-zod" window="__DATA__">
          </schema>
          <template><div>Test</div></template>
        RUE

        create_file(File.join(templates_dir, 'ext2.rue'), <<~RUE)
          <schema src="schemas/ext.schema.ts" lang="js-zod" window="__DATA__">
          </schema>
          <template><div>Test</div></template>
        RUE

        create_file(File.join(templates_dir, 'inline1.rue'), <<~RUE)
          <schema lang="js-zod" window="__DATA__">
          const schema = z.object({});
          </schema>
          <template><div>Test</div></template>
        RUE
      end

      it 'reports external vs inline schema counts' do
        extractor = described_class.new(templates_dir)
        stats = extractor.schema_stats

        expect(stats[:files_with_schemas]).to eq(3)
        expect(stats[:external_schemas]).to eq(2)
        expect(stats[:inline_schemas]).to eq(1)
      end
    end

    describe 'schema_search_paths configuration' do
      let(:external_schema_content) do
        "const schema = z.object({ name: z.string() });"
      end

      # Separate directory outside of templates for shared schemas
      let(:shared_schemas_dir) { File.join(temp_dir, 'shared_schemas') }

      before do
        FileUtils.mkdir_p(shared_schemas_dir)
        Rhales.reset_configuration!
      end

      after do
        Rhales.reset_configuration!
      end

      it 'finds schema in configured search paths when not in template directory' do
        # Create schema file in shared_schemas_dir (not in templates)
        create_file(File.join(shared_schemas_dir, 'common.schema.ts'), external_schema_content)

        # Template references schema that only exists in shared_schemas_dir
        create_file(File.join(templates_dir, 'using_shared.rue'), <<~RUE)
          <schema src="common.schema.ts" lang="js-zod" window="__DATA__">
          </schema>

          <template>
          <div>Test</div>
          </template>
        RUE

        # Configure search paths
        Rhales.configure do |config|
          config.schema_search_paths = [shared_schemas_dir]
        end

        extractor = described_class.new(templates_dir)
        result = extractor.extract_from_file(File.join(templates_dir, 'using_shared.rue'))

        expect(result[:src]).to eq('common.schema.ts')
        expect(result[:resolved_path]).to eq(File.join(shared_schemas_dir, 'common.schema.ts'))
        expect(result[:schema_code]).to include("z.object")
      end

      it 'prefers template-relative path over search paths' do
        # Create schema in both locations with different content
        create_file(File.join(templates_dir, 'schemas', 'priority.schema.ts'), "const schema = z.object({ local: z.boolean() });")
        create_file(File.join(shared_schemas_dir, 'schemas', 'priority.schema.ts'), "const schema = z.object({ shared: z.boolean() });")

        create_file(File.join(templates_dir, 'priority_test.rue'), <<~RUE)
          <schema src="schemas/priority.schema.ts" lang="js-zod" window="__DATA__">
          </schema>

          <template>
          <div>Test</div>
          </template>
        RUE

        Rhales.configure do |config|
          config.schema_search_paths = [shared_schemas_dir]
        end

        extractor = described_class.new(templates_dir)
        result = extractor.extract_from_file(File.join(templates_dir, 'priority_test.rue'))

        # Should use the local template-relative path, not the search path
        expect(result[:resolved_path]).to eq(File.join(templates_dir, 'schemas', 'priority.schema.ts'))
        expect(result[:schema_code]).to include("local")
      end

      it 'searches multiple paths in order' do
        second_search_dir = File.join(temp_dir, 'second_search')
        FileUtils.mkdir_p(second_search_dir)

        # Only create in second search dir
        create_file(File.join(second_search_dir, 'only_in_second.schema.ts'), external_schema_content)

        create_file(File.join(templates_dir, 'multi_search.rue'), <<~RUE)
          <schema src="only_in_second.schema.ts" lang="js-zod" window="__DATA__">
          </schema>

          <template>
          <div>Test</div>
          </template>
        RUE

        Rhales.configure do |config|
          config.schema_search_paths = [shared_schemas_dir, second_search_dir]
        end

        extractor = described_class.new(templates_dir)
        result = extractor.extract_from_file(File.join(templates_dir, 'multi_search.rue'))

        expect(result[:resolved_path]).to eq(File.join(second_search_dir, 'only_in_second.schema.ts'))
      end

      it 'blocks path traversal outside of search paths' do
        # Configure a search path
        Rhales.configure do |config|
          config.schema_search_paths = [shared_schemas_dir]
        end

        # Try to access file outside both templates_dir and search paths
        outside_file = File.join(temp_dir, 'secret.txt')
        create_file(outside_file, 'SECRET DATA')

        create_file(File.join(templates_dir, 'traversal_attack.rue'), <<~RUE)
          <schema src="../secret.txt" lang="js-zod" window="__DATA__">
          </schema>

          <template>
          <div>Test</div>
          </template>
        RUE

        extractor = described_class.new(templates_dir)

        expect {
          extractor.extract_from_file(File.join(templates_dir, 'traversal_attack.rue'))
        }.to raise_error(Rhales::SchemaExtractor::ExtractionError, /path traversal|outside.*directory|not allowed/i)
      end
    end
  end
end
