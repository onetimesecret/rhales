# spec/rhales/integration/external_schema_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'tmpdir'
require 'json'

RSpec.describe 'External schema integration' do
  let(:temp_dir) { Dir.mktmpdir('rhales_external_schema_integration') }
  let(:templates_dir) { File.join(temp_dir, 'templates') }
  let(:schemas_dir) { File.join(templates_dir, 'schemas') }
  let(:output_dir) { File.join(temp_dir, 'output') }

  before do
    FileUtils.mkdir_p(schemas_dir)
    FileUtils.mkdir_p(output_dir)
  end

  after do
    FileUtils.remove_entry(temp_dir) if File.exist?(temp_dir)
  end

  def create_file(path, content)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
  end

  describe 'end-to-end workflow' do
    let(:external_schema_ts) do
      <<~TS
        import { z } from 'zod';

        const schema = z.object({
          userId: z.number(),
          username: z.string(),
          email: z.string().email(),
          roles: z.array(z.string()).optional()
        });

        export default schema;
      TS
    end

    let(:template_with_external_src) do
      <<~RUE
        <schema src="schemas/user.schema.ts" lang="js-zod" window="__USER_DATA__">
        </schema>

        <template>
        <div class="user-profile">
          <h1>{{username}}</h1>
          <p>{{email}}</p>
        </div>
        </template>
      RUE
    end

    before do
      create_file(File.join(schemas_dir, 'user.schema.ts'), external_schema_ts)
      create_file(File.join(templates_dir, 'user_profile.rue'), template_with_external_src)
    end

    it 'parses template with external schema reference' do
      doc = Rhales::RueDocument.parse_file(File.join(templates_dir, 'user_profile.rue'))

      expect(doc.schema_src).to eq('schemas/user.schema.ts')
      expect(doc.schema_lang).to eq('js-zod')
      expect(doc.schema_window).to eq('__USER_DATA__')
    end

    it 'extracts schema from external file' do
      extractor = Rhales::SchemaExtractor.new(templates_dir)
      schemas = extractor.extract_all

      expect(schemas.length).to eq(1)
      schema_info = schemas.first

      expect(schema_info[:template_name]).to eq('user_profile')
      expect(schema_info[:src]).to eq('schemas/user.schema.ts')
      expect(schema_info[:resolved_path]).to eq(File.join(schemas_dir, 'user.schema.ts'))
      expect(schema_info[:schema_code]).to include('z.object')
      expect(schema_info[:schema_code]).to include('userId')
      expect(schema_info[:schema_code]).to include('z.string().email()')
    end

    context 'with mocked TypeScript execution' do
      let(:mock_json_schema) do
        {
          '$schema' => 'https://json-schema.org/draft/2020-12/schema',
          'type' => 'object',
          'properties' => {
            'userId' => { 'type' => 'number' },
            'username' => { 'type' => 'string' },
            'email' => { 'type' => 'string', 'format' => 'email' },
            'roles' => {
              'type' => 'array',
              'items' => { 'type' => 'string' }
            }
          },
          'required' => %w[userId username email]
        }
      end

      before do
        # Mock validation checks
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

      it 'generates JSON Schema from external Zod schema' do
        extractor = Rhales::SchemaExtractor.new(templates_dir)
        schemas = extractor.extract_all

        generator = Rhales::SchemaGenerator.new(templates_dir: templates_dir, output_dir: output_dir)
        result = generator.generate_schema(schemas.first)

        expect(result['type']).to eq('object')
        expect(result['properties']['userId']['type']).to eq('number')
        expect(result['properties']['email']['format']).to eq('email')
      end
    end
  end

  describe 'mixed inline and external schemas' do
    let(:external_schema) { "const schema = z.object({ ext: z.boolean() });" }
    let(:inline_schema) { "const schema = z.object({ inline: z.string() });" }

    before do
      create_file(File.join(schemas_dir, 'external.ts'), external_schema)

      create_file(File.join(templates_dir, 'external_ref.rue'), <<~RUE)
        <schema src="schemas/external.ts" lang="js-zod" window="__EXT__">
        </schema>
        <template><div>External</div></template>
      RUE

      create_file(File.join(templates_dir, 'inline_def.rue'), <<~RUE)
        <schema lang="js-zod" window="__INLINE__">
        #{inline_schema}
        </schema>
        <template><div>Inline</div></template>
      RUE
    end

    it 'handles both types in the same templates directory' do
      extractor = Rhales::SchemaExtractor.new(templates_dir)
      schemas = extractor.extract_all

      external = schemas.find { |s| s[:template_name] == 'external_ref' }
      inline = schemas.find { |s| s[:template_name] == 'inline_def' }

      expect(external[:src]).to eq('schemas/external.ts')
      expect(external[:schema_code]).to include('ext: z.boolean()')

      expect(inline[:src]).to be_nil
      expect(inline[:schema_code]).to include('inline: z.string()')
    end
  end

  describe 'schema stats reporting' do
    before do
      create_file(File.join(schemas_dir, 'shared.ts'), "const schema = z.object({});")

      3.times do |i|
        create_file(File.join(templates_dir, "external_#{i}.rue"), <<~RUE)
          <schema src="schemas/shared.ts" lang="js-zod" window="__DATA__">
          </schema>
          <template><div>External #{i}</div></template>
        RUE
      end

      2.times do |i|
        create_file(File.join(templates_dir, "inline_#{i}.rue"), <<~RUE)
          <schema lang="js-zod" window="__DATA__">
          const schema = z.object({ i: z.literal(#{i}) });
          </schema>
          <template><div>Inline #{i}</div></template>
        RUE
      end

      create_file(File.join(templates_dir, 'no_schema.rue'), <<~RUE)
        <template><div>No schema</div></template>
      RUE
    end

    it 'reports accurate counts for external vs inline' do
      extractor = Rhales::SchemaExtractor.new(templates_dir)
      stats = extractor.schema_stats

      expect(stats[:total_files]).to eq(6)
      expect(stats[:files_with_schemas]).to eq(5)
      expect(stats[:external_schemas]).to eq(3)
      expect(stats[:inline_schemas]).to eq(2)
    end
  end
end
