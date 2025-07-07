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
  spec.required_ruby_version = '>= 3.4.0'

  spec.metadata['homepage_uri']          = spec.homepage
  spec.metadata['source_code_uri']       = 'https://github.com/onetimesecret/rhales'
  spec.metadata['changelog_uri']         = 'https://github.com/onetimesecret/rhales/blob/main/CHANGELOG.md'
  spec.metadata['documentation_uri']     = 'https://github.com/onetimesecret/rhales/blob/main/README.md'
  spec.metadata['rubygems_mfa_required'] = 'true'

  # Specify which files should be added to the gem
  spec.files = Dir.chdir(__dir__) do
    Dir['{lib}/**/*', '*.md', '*.txt', '*.gemspec'].select { |f| File.file?(f) }
  end

  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  # Runtime dependencies
  # (none currently - all parsing is done with manual recursive descent parsers)

  # Development dependencies should be specified in Gemfile instead of gemspec
  # See: https://bundler.io/guides/creating_gem.html#testing-our-gem
end
