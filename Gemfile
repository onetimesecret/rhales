source 'https://rubygems.org'

# Specify your gem's dependencies in rhales.gemspec
gemspec

group :development, :test do
  gem 'benchmark'
  gem 'rack-test'
  gem 'rspec', '~> 3.12'
  gem 'simplecov', '~> 0.22'
end

group :development do
  gem 'benchmark-ips', '~> 2.0'
  gem 'bundler', '~> 2.0'
  gem 'kramdown', '~> 2.0' # Required for YARD markdown processing
  gem 'pry-byebug', require: false
  gem 'rack', '~> 2.0'
  gem 'rack-proxy', require: false
  gem 'rake', '~> 13.0'
  gem 'rubocop', '1.78' # '~> 1.76.2'
  gem 'rubocop-performance', require: false
  gem 'rubocop-rspec', require: false
  gem 'rubocop-thread_safety', require: false
  gem 'stackprof', require: false
  gem 'syntax_tree', require: false
  gem 'yard', '~> 0.9'
end
