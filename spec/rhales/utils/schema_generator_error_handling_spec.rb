# spec/rhales/utils/schema_generator_error_handling_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'fileutils'
require 'tmpdir'

RSpec.describe Rhales::SchemaGenerator do
  describe 'error handling' do
    let(:temp_dir) { Dir.mktmpdir('rhales_schema_generator_errors') }
    let(:templates_dir) { File.join(temp_dir, 'templates') }
    let(:output_dir) { File.join(temp_dir, 'output') }

    before do
      FileUtils.mkdir_p(templates_dir)
      FileUtils.mkdir_p(output_dir)
    end

    after do
      FileUtils.remove_entry(temp_dir) if File.exist?(temp_dir)
    end

    let(:valid_schema_info) do
      {
        template_name: 'test_template',
        template_path: File.join(templates_dir, 'test_template.rue'),
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

    describe 'tsx execution errors' do
      context 'when pnpm is not installed' do
        before do
          allow(Open3).to receive(:capture3)
            .with('pnpm', '--version')
            .and_return(['', 'command not found: pnpm', double(success?: false)])
        end

        it 'raises GenerationError with helpful message' do
          expect {
            described_class.new(templates_dir: templates_dir, output_dir: output_dir)
          }.to raise_error(
            Rhales::SchemaGenerator::GenerationError,
            /pnpm not found/i
          )
        end

        it 'includes installation instructions in error message' do
          expect {
            described_class.new(templates_dir: templates_dir, output_dir: output_dir)
          }.to raise_error(
            Rhales::SchemaGenerator::GenerationError,
            /npm install -g pnpm/
          )
        end
      end

      context 'when tsx is not installed' do
        before do
          allow(Open3).to receive(:capture3)
            .with('pnpm', '--version')
            .and_return(['8.0.0', '', double(success?: true)])
          allow(Open3).to receive(:capture3)
            .with('pnpm', 'exec', 'tsx', '--version')
            .and_return(['', 'Command "tsx" not found', double(success?: false)])
        end

        it 'raises GenerationError with helpful message' do
          expect {
            described_class.new(templates_dir: templates_dir, output_dir: output_dir)
          }.to raise_error(
            Rhales::SchemaGenerator::GenerationError,
            /tsx not found/i
          )
        end

        it 'includes installation instructions in error message' do
          expect {
            described_class.new(templates_dir: templates_dir, output_dir: output_dir)
          }.to raise_error(
            Rhales::SchemaGenerator::GenerationError,
            /pnpm install tsx/
          )
        end
      end

      context 'when esbuild is not installed (with schema_use_tsx_import enabled)' do
        before do
          Rhales.reset_configuration!
          Rhales.configure do |config|
            config.schema_use_tsx_import = true
          end

          allow(Open3).to receive(:capture3)
            .with('pnpm', '--version')
            .and_return(['8.0.0', '', double(success?: true)])
          allow(Open3).to receive(:capture3)
            .with('pnpm', 'exec', 'tsx', '--version')
            .and_return(['4.0.0', '', double(success?: true)])
          allow(Open3).to receive(:capture3)
            .with('pnpm', 'exec', 'esbuild', '--version')
            .and_return(['', 'Command "esbuild" not found', double(success?: false)])
        end

        after do
          Rhales.reset_configuration!
        end

        it 'raises GenerationError with helpful message' do
          expect {
            described_class.new(templates_dir: templates_dir, output_dir: output_dir)
          }.to raise_error(
            Rhales::SchemaGenerator::GenerationError,
            /esbuild not found/i
          )
        end

        it 'includes installation instructions in error message' do
          expect {
            described_class.new(templates_dir: templates_dir, output_dir: output_dir)
          }.to raise_error(
            Rhales::SchemaGenerator::GenerationError,
            /pnpm install esbuild/
          )
        end
      end

      context 'when TypeScript code has syntax errors' do
        let(:generator) do
          allow(Open3).to receive(:capture3)
            .with('pnpm', '--version')
            .and_return(['8.0.0', '', double(success?: true)])
          allow(Open3).to receive(:capture3)
            .with('pnpm', 'exec', 'tsx', '--version')
            .and_return(['4.0.0', '', double(success?: true)])
          described_class.new(templates_dir: templates_dir, output_dir: output_dir)
        end

        it 'raises GenerationError with TypeScript error details' do
          allow(Open3).to receive(:capture3)
            .with('pnpm', 'exec', 'tsx', anything)
            .and_return([
              '',
              "SyntaxError: Unexpected token 'const'\n  at line 5",
              double(success?: false)
            ])

          expect {
            generator.generate_schema(valid_schema_info)
          }.to raise_error(
            Rhales::SchemaGenerator::GenerationError,
            /TypeScript execution failed/i
          )
        end

        it 'includes the stderr output in the error' do
          tsx_error = "TypeError: Cannot read properties of undefined (reading 'object')"
          allow(Open3).to receive(:capture3)
            .with('pnpm', 'exec', 'tsx', anything)
            .and_return(['', tsx_error, double(success?: false)])

          expect {
            generator.generate_schema(valid_schema_info)
          }.to raise_error(
            Rhales::SchemaGenerator::GenerationError,
            /Cannot read properties of undefined/
          )
        end
      end

      context 'when Zod schema conversion fails' do
        let(:generator) do
          allow(Open3).to receive(:capture3)
            .with('pnpm', '--version')
            .and_return(['8.0.0', '', double(success?: true)])
          allow(Open3).to receive(:capture3)
            .with('pnpm', 'exec', 'tsx', '--version')
            .and_return(['4.0.0', '', double(success?: true)])
          described_class.new(templates_dir: templates_dir, output_dir: output_dir)
        end

        it 'raises GenerationError when schema variable is undefined' do
          allow(Open3).to receive(:capture3)
            .with('pnpm', 'exec', 'tsx', anything)
            .and_return([
              '',
              "ReferenceError: schema is not defined",
              double(success?: false)
            ])

          expect {
            generator.generate_schema(valid_schema_info)
          }.to raise_error(
            Rhales::SchemaGenerator::GenerationError,
            /schema is not defined/
          )
        end

        it 'raises GenerationError for invalid Zod constructs' do
          allow(Open3).to receive(:capture3)
            .with('pnpm', 'exec', 'tsx', anything)
            .and_return([
              '',
              "Error: z.customType is not a function",
              double(success?: false)
            ])

          expect {
            generator.generate_schema(valid_schema_info)
          }.to raise_error(
            Rhales::SchemaGenerator::GenerationError,
            /z.customType is not a function/
          )
        end
      end

      context 'when output is invalid JSON' do
        let(:generator) do
          allow(Open3).to receive(:capture3)
            .with('pnpm', '--version')
            .and_return(['8.0.0', '', double(success?: true)])
          allow(Open3).to receive(:capture3)
            .with('pnpm', 'exec', 'tsx', '--version')
            .and_return(['4.0.0', '', double(success?: true)])
          described_class.new(templates_dir: templates_dir, output_dir: output_dir)
        end

        it 'raises error when tsx produces non-JSON output' do
          allow(Open3).to receive(:capture3)
            .with('pnpm', 'exec', 'tsx', anything)
            .and_return([
              'This is not valid JSON',
              '',
              double(success?: true)
            ])

          expect {
            generator.generate_schema(valid_schema_info)
          }.to raise_error(JSON::ParserError)
        end

        it 'raises error when tsx produces empty output' do
          allow(Open3).to receive(:capture3)
            .with('pnpm', 'exec', 'tsx', anything)
            .and_return(['', '', double(success?: true)])

          expect {
            generator.generate_schema(valid_schema_info)
          }.to raise_error(JSON::ParserError)
        end
      end
    end

    describe 'directory validation' do
      context 'when templates directory does not exist' do
        before do
          allow(Open3).to receive(:capture3).and_return(['1.0', '', double(success?: true)])
        end

        it 'raises GenerationError' do
          expect {
            described_class.new(
              templates_dir: '/nonexistent/templates',
              output_dir: output_dir
            )
          }.to raise_error(
            Rhales::SchemaGenerator::GenerationError,
            /does not exist/i
          )
        end
      end

      context 'when output directory creation fails' do
        before do
          allow(Open3).to receive(:capture3).and_return(['1.0', '', double(success?: true)])
          allow(FileUtils).to receive(:mkdir_p).and_raise(Errno::EACCES, 'Permission denied')
        end

        it 'raises error when cannot create output directory' do
          expect {
            described_class.new(templates_dir: templates_dir, output_dir: '/root/forbidden/schemas')
          }.to raise_error(Errno::EACCES)
        end
      end
    end

    describe '#generate_all error handling' do
      let(:generator) do
        allow(Open3).to receive(:capture3)
          .with('pnpm', '--version')
          .and_return(['8.0.0', '', double(success?: true)])
        allow(Open3).to receive(:capture3)
          .with('pnpm', 'exec', 'tsx', '--version')
          .and_return(['4.0.0', '', double(success?: true)])
        described_class.new(templates_dir: templates_dir, output_dir: output_dir)
      end

      before do
        # Create test .rue file
        File.write(File.join(templates_dir, 'test.rue'), <<~RUE)
          <schema lang="js-zod" window="__DATA__">
          const schema = z.object({ name: z.string() });
          </schema>
          <template><div>Test</div></template>
        RUE
      end

      context 'when generation fails for some schemas' do
        it 'continues processing remaining schemas' do
          # First call fails, second succeeds
          call_count = 0
          allow(Open3).to receive(:capture3)
            .with('pnpm', 'exec', 'tsx', anything) do
              call_count += 1
              if call_count == 1
                ['', 'Error in first schema', double(success?: false)]
              else
                [JSON.generate({ 'type' => 'object' }), '', double(success?: true)]
              end
            end

          # Create second template
          File.write(File.join(templates_dir, 'test2.rue'), <<~RUE)
            <schema lang="js-zod" window="__DATA__">
            const schema = z.object({ id: z.number() });
            </schema>
            <template><div>Test2</div></template>
          RUE

          result = generator.generate_all

          expect(result[:failed]).to be >= 1
          expect(result[:errors]).not_to be_empty
        end

        it 'returns failure summary with error messages' do
          allow(Open3).to receive(:capture3)
            .with('pnpm', 'exec', 'tsx', anything)
            .and_return(['', 'Schema generation error', double(success?: false)])

          result = generator.generate_all

          expect(result[:success]).to be false
          expect(result[:failed]).to eq(1)
          expect(result[:errors].first).to include('test')
        end
      end

      context 'when no schemas are found' do
        before do
          FileUtils.rm_rf(File.join(templates_dir, 'test.rue'))
          File.write(File.join(templates_dir, 'no_schema.rue'), <<~RUE)
            <template><div>No schema here</div></template>
          RUE
        end

        it 'returns success with zero generated' do
          result = generator.generate_all

          expect(result[:success]).to be true
          expect(result[:generated]).to eq(0)
          expect(result[:message]).to include('No schemas found')
        end
      end
    end

    describe 'external schema error handling' do
      let(:external_schema_info) do
        {
          template_name: 'external_test',
          template_path: File.join(templates_dir, 'external_test.rue'),
          schema_code: 'const schema = z.object({ ext: z.boolean() });',
          lang: 'js-zod',
          version: nil,
          envelope: nil,
          window: '__DATA__',
          merge: nil,
          layout: nil,
          extends: nil,
          src: 'schemas/external.ts',
          resolved_path: File.join(templates_dir, 'schemas/external.ts')
        }
      end

      let(:generator) do
        allow(Open3).to receive(:capture3)
          .with('pnpm', '--version')
          .and_return(['8.0.0', '', double(success?: true)])
        allow(Open3).to receive(:capture3)
          .with('pnpm', 'exec', 'tsx', '--version')
          .and_return(['4.0.0', '', double(success?: true)])
        described_class.new(templates_dir: templates_dir, output_dir: output_dir)
      end

      it 'includes external source path in error messages' do
        allow(Open3).to receive(:capture3)
          .with('pnpm', 'exec', 'tsx', anything)
          .and_return(['', 'Import error in external file', double(success?: false)])

        expect {
          generator.generate_schema(external_schema_info)
        }.to raise_error(
          Rhales::SchemaGenerator::GenerationError,
          /Import error/
        )
      end
    end
  end
end
