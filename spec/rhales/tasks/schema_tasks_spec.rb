# spec/rhales/tasks/schema_tasks_spec.rb
# frozen_string_literal: true

require 'spec_helper'
require 'rake'
require 'fileutils'
require 'tmpdir'
require 'json'
require 'open3'

RSpec.describe 'rhales:schema rake tasks' do
  # Load rake tasks
  before(:all) do
    @rake = Rake::Application.new
    Rake.application = @rake

    # Load the rake tasks
    load File.expand_path('../../../lib/tasks/rhales_schema.rake', __dir__)

    Rake::Task.define_task(:environment)
  end

  around(:each) do |example|
    # Save original ENV to prevent test pollution
    original_env = ENV.to_h
    @rake.tasks.each(&:reenable)
    example.run
  ensure
    # Restore ENV even if test fails
    ENV.replace(original_env)
  end

  let(:temp_dir) { Dir.mktmpdir('rhales_schema_test') }
  let(:templates_dir) { File.join(temp_dir, 'templates') }
  let(:output_dir) { File.join(temp_dir, 'schemas') }

  after(:each) do
    FileUtils.remove_entry(temp_dir) if File.exist?(temp_dir)
  end

  # Helper to create a .rue file with schema
  def create_rue_file(path, content)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
  end

  # Sample .rue content with schema
  let(:sample_rue_with_schema) do
    <<~RUE
      <schema lang="js-zod" window="testData">
      const schema = z.object({
        name: z.string(),
        email: z.string().email(),
        age: z.number().int().positive()
      });
      </schema>

      <template>
      <h1>{{name}}</h1>
      </template>
    RUE
  end

  # Sample .rue content without schema
  let(:sample_rue_without_schema) do
    <<~RUE
      <template>
      <h1>Hello World</h1>
      </template>
    RUE
  end

  describe 'rhales:schema:generate' do
    it 'loads without error' do
      expect { Rake::Task['rhales:schema:generate'] }.not_to raise_error
    end

    context 'with valid templates directory' do
      before do
        FileUtils.mkdir_p(templates_dir)
        create_rue_file(
          File.join(templates_dir, 'test_template.rue'),
          sample_rue_with_schema
        )

        # Mock pnpm/tsx execution to avoid external dependencies
        allow_any_instance_of(Rhales::SchemaGenerator).to receive(:system).and_return(true)
        allow(Open3).to receive(:capture3).and_return([
          JSON.generate({
            '$schema' => 'https://json-schema.org/draft/2020-12/schema',
            'type' => 'object',
            'properties' => {
              'name' => { 'type' => 'string' },
              'email' => { 'type' => 'string', 'format' => 'email' },
              'age' => { 'type' => 'number' }
            },
            'required' => ['name', 'email', 'age']
          }),
          '',
          double(success?: true)
        ])
      end

      it 'generates JSON schemas successfully' do
        ENV['TEMPLATES_DIR'] = templates_dir
        ENV['OUTPUT_DIR'] = output_dir

        # Capture output - expect SystemExit with code 0
        output = capture_stdout do
          expect do
            Rake::Task['rhales:schema:generate'].invoke
          end.to raise_error(SystemExit) { |e| expect(e.status).to eq(0) }
        end

        expect(output).to include('Schema Generation')
        expect(output).to include('Found 1 schema section(s)')
        expect(output).to include('test_template (js-zod)')
        expect(output).to include('Successfully generated 1 schema(s)')

        # Verify output file exists
        schema_file = File.join(output_dir, 'test_template.json')
        expect(File.exist?(schema_file)).to be true

        # Verify schema content
        schema = JSON.parse(File.read(schema_file))
        expect(schema).to have_key('$schema')
        expect(schema).to have_key('properties')
        expect(schema['properties']).to have_key('name')
        expect(schema['properties']).to have_key('email')
        expect(schema['properties']).to have_key('age')
      end

      it 'creates output directory if it does not exist' do
        ENV['TEMPLATES_DIR'] = templates_dir
        ENV['OUTPUT_DIR'] = output_dir

        expect(File.exist?(output_dir)).to be false

        capture_stdout do
          expect { Rake::Task['rhales:schema:generate'].invoke }.to raise_error(SystemExit)
        end

        expect(File.exist?(output_dir)).to be true
      end

      it 'handles multiple templates' do
        create_rue_file(
          File.join(templates_dir, 'template2.rue'),
          sample_rue_with_schema
        )

        ENV['TEMPLATES_DIR'] = templates_dir
        ENV['OUTPUT_DIR'] = output_dir

        output = capture_stdout do
          expect { Rake::Task['rhales:schema:generate'].invoke }.to raise_error(SystemExit)
        end

        expect(output).to include('Found 2 schema section(s)')
        expect(output).to include('Successfully generated 2 schema(s)')

        expect(File.exist?(File.join(output_dir, 'test_template.json'))).to be true
        expect(File.exist?(File.join(output_dir, 'template2.json'))).to be true
      end
    end

    context 'when templates directory does not exist' do
      it 'exits with error message' do
        ENV['TEMPLATES_DIR'] = File.join(temp_dir, 'nonexistent')
        ENV['OUTPUT_DIR'] = output_dir

        output = capture_stdout do
          expect do
            Rake::Task['rhales:schema:generate'].invoke
          end.to raise_error(SystemExit)
        end

        expect(output).to include('Templates directory not found')
      end
    end

    context 'when no schemas found' do
      before do
        FileUtils.mkdir_p(templates_dir)
        create_rue_file(
          File.join(templates_dir, 'no_schema.rue'),
          sample_rue_without_schema
        )
      end

      it 'exits gracefully with message' do
        ENV['TEMPLATES_DIR'] = templates_dir
        ENV['OUTPUT_DIR'] = output_dir

        output = capture_stdout do
          expect do
            Rake::Task['rhales:schema:generate'].invoke
          end.to raise_error(SystemExit)
        end

        expect(output).to include('No schema sections found')
      end
    end

    context 'with default directories' do
      it 'uses ./templates and ./public/schemas as defaults' do
        # Clear ENV to test defaults
        ENV.delete('TEMPLATES_DIR')
        ENV.delete('OUTPUT_DIR')

        # This test verifies the task can be invoked without ENV vars
        # (actual execution would fail without real directories)
        output = capture_stdout do
          expect do
            Rake::Task['rhales:schema:generate'].invoke
          end.to raise_error(SystemExit)
        end

        expect(output).to include('Templates: ./templates')
        expect(output).to include('Output: ./public/schemas')
      end
    end
  end

  describe 'rhales:schema:validate' do
    it 'loads without error' do
      expect { Rake::Task['rhales:schema:validate'] }.not_to raise_error
    end

    context 'with valid schemas' do
      before do
        FileUtils.mkdir_p(output_dir)

        valid_schema = {
          '$schema' => 'https://json-schema.org/draft/2020-12/schema',
          'type' => 'object',
          'properties' => {
            'name' => { 'type' => 'string' },
            'age' => { 'type' => 'number' }
          }
        }

        File.write(
          File.join(output_dir, 'valid.json'),
          JSON.pretty_generate(valid_schema)
        )
      end

      it 'validates schemas successfully' do
        ENV['OUTPUT_DIR'] = output_dir

        output = capture_stdout do
          # Task exits with 0 on success (no error raised in this implementation)
          Rake::Task['rhales:schema:validate'].invoke
        end

        expect(output).to include('Validating 1 schema file(s)')
        expect(output).to include('✓ valid.json')
        expect(output).to include('All schemas valid')
      end
    end

    context 'with invalid JSON' do
      before do
        FileUtils.mkdir_p(output_dir)
        File.write(File.join(output_dir, 'invalid.json'), 'not valid json {')
      end

      it 'reports JSON parse errors' do
        ENV['OUTPUT_DIR'] = output_dir

        output = capture_stdout do
          expect do
            Rake::Task['rhales:schema:validate'].invoke
          end.to raise_error(SystemExit)
        end

        expect(output).to include('Errors:')
        expect(output).to include('invalid.json')
        expect(output).to include('Invalid JSON')
      end
    end

    context 'when schemas directory does not exist' do
      it 'exits with error message' do
        ENV['OUTPUT_DIR'] = File.join(temp_dir, 'nonexistent')

        output = capture_stdout do
          expect do
            Rake::Task['rhales:schema:validate'].invoke
          end.to raise_error(SystemExit)
        end

        expect(output).to include('Schemas directory not found')
      end
    end

    context 'when no schema files found' do
      before do
        FileUtils.mkdir_p(output_dir)
      end

      it 'exits with message' do
        ENV['OUTPUT_DIR'] = output_dir

        output = capture_stdout do
          expect do
            Rake::Task['rhales:schema:validate'].invoke
          end.to raise_error(SystemExit)
        end

        expect(output).to include('No schema files found')
      end
    end
  end

  describe 'rhales:schema:stats' do
    it 'loads without error' do
      expect { Rake::Task['rhales:schema:stats'] }.not_to raise_error
    end

    context 'with mixed templates' do
      before do
        FileUtils.mkdir_p(templates_dir)

        create_rue_file(
          File.join(templates_dir, 'with_schema.rue'),
          sample_rue_with_schema
        )

        create_rue_file(
          File.join(templates_dir, 'without_schema.rue'),
          sample_rue_without_schema
        )
      end

      it 'displays statistics correctly' do
        ENV['TEMPLATES_DIR'] = templates_dir

        output = capture_stdout do
          # Stats task doesn't exit, just outputs
          Rake::Task['rhales:schema:stats'].invoke
        end

        expect(output).to include('Schema Statistics')
        expect(output).to include('Total .rue files: 2')
        expect(output).to include('Files with <schema>: 1')
        expect(output).to include('Files without <schema>: 1')
        expect(output).to include('By language:')
        expect(output).to include('js-zod: 1')
      end
    end

    context 'when templates directory does not exist' do
      it 'exits with error message' do
        ENV['TEMPLATES_DIR'] = File.join(temp_dir, 'nonexistent')

        output = capture_stdout do
          expect do
            Rake::Task['rhales:schema:stats'].invoke
          end.to raise_error(SystemExit)
        end

        expect(output).to include('Templates directory not found')
      end
    end

    context 'with no templates' do
      before do
        FileUtils.mkdir_p(templates_dir)
      end

      it 'shows zero counts' do
        ENV['TEMPLATES_DIR'] = templates_dir

        output = capture_stdout do
          # Stats task doesn't exit, just outputs
          Rake::Task['rhales:schema:stats'].invoke
        end

        expect(output).to include('Total .rue files: 0')
        expect(output).to include('Files with <schema>: 0')
        expect(output).to include('Files without <schema>: 0')
      end
    end
  end

  # Helper to capture stdout
  def capture_stdout
    old_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = old_stdout
  end
end
