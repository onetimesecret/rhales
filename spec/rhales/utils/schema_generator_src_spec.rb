# spec/rhales/utils/schema_generator_src_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'fileutils'
require 'tmpdir'

RSpec.describe Rhales::SchemaGenerator do
  describe 'external schema source handling' do
    let(:temp_dir) { Dir.mktmpdir('rhales_schema_generator_test') }
    let(:templates_dir) { File.join(temp_dir, 'templates') }
    let(:output_dir) { File.join(temp_dir, 'output') }

    before do
      FileUtils.mkdir_p(templates_dir)
      FileUtils.mkdir_p(output_dir)
    end

    after do
      FileUtils.remove_entry(temp_dir) if File.exist?(temp_dir)
    end

    let(:inline_schema_info) do
      {
        template_name: 'inline_test',
        template_path: File.join(templates_dir, 'inline_test.rue'),
        schema_code: 'const schema = z.object({ name: z.string() });',
        lang: 'js-zod',
        version: nil,
        envelope: nil,
        window: '__DATA__',
        merge: nil,
        layout: nil,
        extends: nil,
        src: nil,
        resolved_path: nil
      }
    end

    let(:external_schema_info) do
      {
        template_name: 'external_test',
        template_path: File.join(templates_dir, 'external_test.rue'),
        schema_code: 'const schema = z.object({ id: z.number() });',
        lang: 'js-zod',
        version: nil,
        envelope: nil,
        window: '__DATA__',
        merge: nil,
        layout: nil,
        extends: nil,
        src: 'schemas/external.schema.ts',
        resolved_path: File.join(templates_dir, 'schemas/external.schema.ts')
      }
    end

    describe '#build_typescript_script (private method via send)' do
      let(:generator) do
        described_class.new(templates_dir: templates_dir, output_dir: output_dir)
      end

      it 'includes inline source comment for inline schemas' do
        script = generator.send(:build_typescript_script, inline_schema_info)

        expect(script).to include('// Source: inline schema')
        expect(script).not_to include('external')
      end

      it 'includes external source comment for external schemas' do
        script = generator.send(:build_typescript_script, external_schema_info)

        expect(script).to include('// Source: schemas/external.schema.ts (external)')
      end

      it 'includes the schema_code in the script' do
        script = generator.send(:build_typescript_script, external_schema_info)

        expect(script).to include(external_schema_info[:schema_code])
      end
    end

    describe '#generate_schema with mocked execution' do
      let(:generator) do
        described_class.new(templates_dir: templates_dir, output_dir: output_dir)
      end

      let(:mock_json_schema) do
        {
          '$schema' => 'https://json-schema.org/draft/2020-12/schema',
          'type' => 'object',
          'properties' => { 'name' => { 'type' => 'string' } }
        }
      end

      before do
        # Mock Open3.capture3 for validation checks
        allow(Open3).to receive(:capture3)
          .with('pnpm', '--version')
          .and_return(['8.0.0', '', double(success?: true)])
        allow(Open3).to receive(:capture3)
          .with('pnpm', 'exec', 'tsx', '--version')
          .and_return(['4.0.0', '', double(success?: true)])
        # Mock actual TypeScript execution
        allow(Open3).to receive(:capture3)
          .with('pnpm', 'exec', 'tsx', anything)
          .and_return([JSON.generate(mock_json_schema), '', double(success?: true)])
      end

      it 'processes inline schemas (src: nil)' do
        result = generator.generate_schema(inline_schema_info)

        expect(result).to be_a(Hash)
        expect(result['type']).to eq('object')
      end

      it 'processes external schemas (src present)' do
        result = generator.generate_schema(external_schema_info)

        expect(result).to be_a(Hash)
        expect(result['type']).to eq('object')
      end
    end

    describe 'tsx import mode' do
      # Define schema file path as a method so it can be used before lazy let evaluation
      def schema_file_path
        File.join(templates_dir, 'schemas', 'external.schema.ts')
      end

      let(:generator) do
        described_class.new(templates_dir: templates_dir, output_dir: output_dir)
      end

      let(:external_schema_with_path) do
        # Create actual file for resolved_path
        FileUtils.mkdir_p(File.dirname(schema_file_path))
        File.write(schema_file_path, "export default z.object({ id: z.number() });")

        {
          template_name: 'import_mode_test',
          template_path: File.join(templates_dir, 'import_mode_test.rue'),
          schema_code: 'const schema = z.object({ id: z.number() });',
          lang: 'js-zod',
          version: nil,
          envelope: nil,
          window: '__DATA__',
          merge: nil,
          layout: nil,
          extends: nil,
          src: 'schemas/external.schema.ts',
          resolved_path: schema_file_path
        }
      end

      before do
        Rhales.reset_configuration!

        # Mock Open3.capture3 for validation checks
        allow(Open3).to receive(:capture3)
          .with('pnpm', '--version')
          .and_return(['8.0.0', '', double(success?: true)])
        allow(Open3).to receive(:capture3)
          .with('pnpm', 'exec', 'tsx', '--version')
          .and_return(['4.0.0', '', double(success?: true)])
        allow(Open3).to receive(:capture3)
          .with('pnpm', 'exec', 'esbuild', '--version')
          .and_return(['0.20.0', '', double(success?: true)])
      end

      after do
        Rhales.reset_configuration!
      end

      describe '#use_tsx_import_mode? (private method via send)' do
        it 'returns false when schema_use_tsx_import is disabled' do
          Rhales.configure do |config|
            config.schema_use_tsx_import = false
          end

          result = generator.send(:use_tsx_import_mode?, external_schema_with_path)
          expect(result).to be(false)
        end

        it 'returns false for inline schemas even when tsx import is enabled' do
          Rhales.configure do |config|
            config.schema_use_tsx_import = true
          end

          result = generator.send(:use_tsx_import_mode?, inline_schema_info)
          expect(result).to be(false)
        end

        it 'returns true for external schemas when tsx import is enabled' do
          Rhales.configure do |config|
            config.schema_use_tsx_import = true
          end

          result = generator.send(:use_tsx_import_mode?, external_schema_with_path)
          expect(result).to be(true)
        end
      end

      describe '#build_typescript_import_script (private method via send)' do
        let(:bundled_file_pattern) { %r{tmp/bundled_external\.schema_\d+\.mjs$} }

        # Helper to mock esbuild bundling that writes to outfile
        def mock_esbuild_bundle_success
          allow(Open3).to receive(:capture3)
            .with('pnpm', 'exec', 'esbuild', schema_file_path,
                  '--bundle', '--format=esm', '--platform=node',
                  satisfy { |arg| arg.to_s.start_with?('--outfile=') }) do |*args|
              outfile_path = args.last.sub('--outfile=', '')
              FileUtils.mkdir_p(File.dirname(outfile_path))
              File.write(outfile_path, "export default { type: 'object' };")
              ['', '', double(success?: true)]
            end
        end

        before do
          Rhales.configure do |config|
            config.schema_use_tsx_import = true
          end

          # Force file creation before mocking
          external_schema_with_path
        end

        after do
          # Clean up any bundled files
          Dir.glob(File.join(Dir.pwd, 'tmp', 'bundled_*.mjs')).each { |f| File.unlink(f) rescue nil }
        end

        it 'returns script and bundled file path' do
          mock_esbuild_bundle_success

          result = generator.send(:build_typescript_import_script, external_schema_with_path)

          expect(result).to be_an(Array)
          expect(result.length).to eq(2)

          script, bundled_path = result
          expect(script).to be_a(String)
          expect(bundled_path).to match(bundled_file_pattern)
        end

        it 'generates script that imports from bundled file' do
          mock_esbuild_bundle_success

          script, bundled_path = generator.send(:build_typescript_import_script, external_schema_with_path)

          expect(script).to include("import schema from '#{bundled_path}'")
          expect(script).to include('// Source: schemas/external.schema.ts (bundled via esbuild)')
        end

        it 'creates the bundled file via esbuild' do
          mock_esbuild_bundle_success

          _script, bundled_path = generator.send(:build_typescript_import_script, external_schema_with_path)

          expect(File.exist?(bundled_path)).to be(true)
        end

        it 'raises GenerationError when esbuild fails' do
          allow(Open3).to receive(:capture3)
            .with('pnpm', 'exec', 'esbuild', schema_file_path,
                  '--bundle', '--format=esm', '--platform=node',
                  satisfy { |arg| arg.to_s.start_with?('--outfile=') })
            .and_return(['', 'Syntax error in schema', double(success?: false)])

          expect {
            generator.send(:build_typescript_import_script, external_schema_with_path)
          }.to raise_error(Rhales::SchemaGenerator::GenerationError, /esbuild bundling failed/)
        end
      end

      describe '#execute_tsx (private method via send)' do
        let(:script_path) { '/tmp/test_script.mts' }

        it 'executes without tsconfig when not configured' do
          Rhales.configure do |config|
            config.schema_tsconfig_path = nil
          end

          expect(Open3).to receive(:capture3)
            .with('pnpm', 'exec', 'tsx', script_path)
            .and_return(['{}', '', double(success?: true)])

          generator.send(:execute_tsx, script_path)
        end

        it 'executes with tsconfig when configured and file exists' do
          tsconfig_file = File.join(temp_dir, 'tsconfig.json')
          File.write(tsconfig_file, '{}')

          Rhales.configure do |config|
            config.schema_tsconfig_path = tsconfig_file
          end

          expect(Open3).to receive(:capture3)
            .with('pnpm', 'exec', 'tsx', '--tsconfig', tsconfig_file, script_path)
            .and_return(['{}', '', double(success?: true)])

          generator.send(:execute_tsx, script_path)
        end

        it 'falls back to no tsconfig when configured path does not exist' do
          Rhales.configure do |config|
            config.schema_tsconfig_path = '/nonexistent/tsconfig.json'
          end

          expect(Open3).to receive(:capture3)
            .with('pnpm', 'exec', 'tsx', script_path)
            .and_return(['{}', '', double(success?: true)])

          generator.send(:execute_tsx, script_path)
        end
      end
    end
  end
end
