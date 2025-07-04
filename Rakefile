# Rakefile

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

task :default => :spec

# Rhales specific tasks
namespace :rhales do
  desc "Run Rhales tests only"
  task :test do
    system("bundle exec rspec spec/rhales/")
  end

  desc "Generate Rhales documentation"
  task :docs do
    system("bundle exec yard doc lib/rhales/")
  end

  desc "Validate Rhales templates in examples"
  task :validate do
    require 'rhales'

    examples_dir = File.join(__dir__, 'examples', 'templates')
    if Dir.exist?(examples_dir)
      Dir.glob(File.join(examples_dir, '**', '*.rue')).each do |file|
        puts "Validating #{file}..."
        begin
          Rhales::Parser.parse_file(file)
          puts "  ✓ Valid"
        rescue => e
          puts "  ✗ Error: #{e.message}"
        end
      end
    else
      puts "No examples directory found at #{examples_dir}"
    end
  end
end
