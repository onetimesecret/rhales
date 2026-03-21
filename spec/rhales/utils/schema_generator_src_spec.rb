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
  end
end
