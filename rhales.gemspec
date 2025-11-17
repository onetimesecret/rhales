# rhales.gemspec

require_relative 'lib/rhales/version'

Gem::Specification.new do |spec|
  spec.name          = 'rhales'
  spec.version       = Rhales::VERSION
  spec.authors       = ['delano']
  spec.email         = ['gems@onetimesecret.com']

  spec.summary       = 'Rhales - Server-rendered components with client-side hydration (RSFCs)'
  spec.description   = <<~DESC
    Rhales is a framework for building server-rendered components with
    client-side data hydration using .rue files called RSFCs (Ruby
    Single File Components). Similar to Vue.js single file components
    but for server-side Ruby applications.

    Features include Handlebars-style templating, JSON data injection, partial support,
    pluggable authentication adapters, and security-first design.
  DESC

  spec.homepage              = 'https://github.com/onetimesecret/rhales'
  spec.license               = 'MIT'
  spec.required_ruby_version = '>= 3.3.4'

  spec.metadata['source_code_uri']       = 'https://github.com/onetimesecret/rhales'
  spec.metadata['changelog_uri']         = 'https://github.com/onetimesecret/rhales/blob/main/CHANGELOG.md'
  spec.metadata['documentation_uri']     = 'https://github.com/onetimesecret/rhales/blob/main/README.md'
  spec.metadata['rubygems_mfa_required'] = 'true'

  # Specify which files should be added to the gem
  # Use git if available, otherwise fall back to Dir.glob for non-git environments
  spec.files = if File.exist?('.git') && system('git --version > /dev/null 2>&1')
                 `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
               else
                 Dir.glob('{lib,exe}/**/*', File::FNM_DOTMATCH).reject { |f| File.directory?(f) }
               end

  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  # Runtime dependencies
  spec.add_dependency 'json_schemer', '~> 2.3'  # JSON Schema validation in middleware
  spec.add_dependency 'logger'                  # Standard library logger for logging support
  spec.add_dependency 'tilt', '~> 2'            # Templating engine for rendering RSFCs

  # Optional dependencies for performance optimization
  # Install oj for 10-20x faster JSON parsing and 5-10x faster generation
  # spec.add_dependency 'oj', '~> 3.13'

  # Development dependencies should be specified in Gemfile instead of gemspec
  # See: https://bundler.io/guides/creating_gem.html#testing-our-gem
end
