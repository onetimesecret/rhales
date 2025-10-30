# spec/spec_helper.rb

require 'bundler/setup'
require 'rhales'

# Configure Rhales for testing
Rhales.configure do |config|
  config.default_locale      = 'en'
  config.app_environment     = 'test'
  config.development_enabled = false
  config.template_paths      = [File.join(__dir__, 'fixtures', 'templates')]
  config.cache_templates     = false
  config.features            = { test_feature: true }
end

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = '.rspec_status'

  # Disable RSpec exposing methods globally on Module and main
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Silence Rhales debug logs during test suite
  config.before(:suite) do
    Rhales.logger.level = Logger::WARN
  end

  # Reset Rhales configuration between tests
  config.before do
    # Clear any instance variables that might hold stale mocks
    Rhales.instance_variable_set(:@logger, nil) if Rhales.instance_variable_defined?(:@logger)

    # Reset configuration BEFORE configuring to avoid frozen configuration errors
    Rhales.reset_configuration!

    Rhales.configure do |rhales_config|
      rhales_config.default_locale      = 'en'
      rhales_config.app_environment     = 'test'
      rhales_config.development_enabled = false
      rhales_config.template_paths      = [File.join(__dir__, 'fixtures', 'templates')]
      rhales_config.cache_templates     = false
      rhales_config.features            = { test_feature: true }
    end
  end
end
