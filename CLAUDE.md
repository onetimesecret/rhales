# CLAUDE.md - Rhales Gem Development

## Project Overview

Rhales uses RSFCs (Ruby Single File Components) is a standalone Ruby gem for
building server-rendered components with client-side data hydration using `.rue`
files. This gem was extracted from the OneTime Secret project and transformed
into a modern, reusable Ruby library.

## Architecture

Rhales follows a clean, modular architecture with clear separation of concerns:

### Core Components

1. **Configuration** (`lib/rhales/configuration.rb`)
   - Dependency injection system replacing global configuration
   - Supports block-based configuration typical of Ruby gems
   - Validates settings and provides sensible defaults

2. **Context** (`lib/rhales/context.rb`)
   - Three-layer data system: runtime, business, computed
   - Dot-notation variable access with proper false/nil handling
   - Immutable after creation for security

3. **Parser** (`lib/rhales/parser.rb`)
   - Parses `.rue` files into sections: `<data>`, `<template>`, `<logic>`
   - Validates structure and extracts dependencies
   - Uses Prism for reliable parsing

4. **Rhales** (`lib/rhales/rhales.rb`)
   - Handlebars-style template engine
   - Supports conditionals (`{{#if}}{{else}}{{/if}}`), iteration, partials
   - HTML escaping by default with raw output option

5. **Hydrator** (`lib/rhales/hydrator.rb`)
   - Client-side data injection with JSON serialization
   - Secure script generation with CSP nonce support
   - Variable interpolation in data sections

6. **View** (`lib/rhales/view.rb`)
   - Main orchestration class
   - Template loading with configurable paths
   - Complete rendering pipeline

7. **Adapters** (`lib/rhales/adapters/`)
   - Pluggable authentication (`BaseAuth`, `AnonymousAuth`, `AuthenticatedAuth`)
   - Session management (`BaseSession`, `AnonymousSession`, `AuthenticatedSession`)

### Key Features Implemented

- ✅ **Dependency Injection**: No global state dependencies
- ✅ **Pluggable Architecture**: Authentication and session adapters
- ✅ **Template Caching**: Configurable with development mode invalidation
- ✅ **Security First**: XSS protection, CSP support, CSRF tokens
- ✅ **Comprehensive Testing**: 56 test examples with full coverage
- ✅ **Standard Gem Structure**: Gemspec, version management, documentation

## Development Workflow

### Running Tests
```bash
# All Rhaes tests
bundle exec rspec spec/rhales/

# Specific test files
bundle exec rspec spec/rhales/configuration_spec.rb
bundle exec rspec spec/rhales/integration_spec.rb

# Run with documentation format
bundle exec rspec spec/rhales/ --format documentation
```

### Rake Tasks
```bash
# Run Rhales-specific tests
rake rhales:test

# Generate documentation
rake rhales:docs

# Validate template files
rake rhales:validate
```

### Gem Development
```bash
# Build gem
gem build rhales.gemspec

# Install locally for testing
gem install rhales-0.1.0.gem

# Test in irb/pry
require 'rhales'
Rhales.configure { |c| c.default_locale = 'en' }
```

## Code Style Guidelines

- **Ruby Style**: Follow standard Ruby conventions
- **Testing**: Use RSpec with descriptive test names
- **Documentation**: YARD-compatible inline documentation
- **Security**: Never expose secrets, validate all inputs
- **Performance**: Template caching, efficient data structures

## File Structure

When extracting to standalone gem, include these files:

### Core Files
```
lib/
├── rhales.rb                     # Main entry point
├── rhales/
│   ├── version.rb              # Version management
│   ├── configuration.rb        # Configuration system
│   ├── context.rb              # Data context layer
│   ├── parser.rb               # .rue file parser
│   ├── rhales.rb               # Template engine
│   ├── hydrator.rb             # Client-side data injection
│   ├── view.rb                 # Main orchestration
│   ├── adapters/
│   │   ├── base_auth.rb        # Authentication interface
│   │   └── base_session.rb     # Session interface
│   └── refinements/
│       └── require_refinements.rb  # .rue file loading
```

### Test Files
```
spec/
├── spec_helper.rb              # Test configuration
├── fixtures/
│   └── templates/
│       └── test.rue            # Test template
└── rhales/
    ├── configuration_spec.rb   # Configuration tests
    ├── context_spec.rb         # Context tests
    ├── integration_spec.rb     # End-to-end tests
    └── adapters/
        └── base_auth_spec.rb   # Adapter tests
```

### Gem Infrastructure
```
rhales.gemspec                    # Gem specification
Rakefile                        # Build tasks
README.md                       # Documentation
CHANGELOG.md                    # Version history
Gemfile                         # Development dependencies
.rspec                          # RSpec configuration
```

## Key Implementation Details

### Template Syntax Support
- Variables: `{{variable}}` (escaped), `{{{variable}}}` (raw)
- Conditionals: `{{#if condition}}...{{else}}...{{/if}}`
- Negation: `{{#unless condition}}...{{/unless}}`
- Iteration: `{{#each items}}...{{/each}}`
- Partials: `{{> partial_name}}`

### Data Hydration
```erb
<data window="customName">
{
  "message": "{{greeting}}",
  "user": {"name": "{{user.name}}"},
  "authenticated": "{{authenticated}}"
}
</data>
```

Generates secure JSON + hydration scripts with CSP nonce support.

### Context Data Layers
1. **Runtime**: Request metadata (CSRF, nonces, environment)
2. **Business**: Application data passed from controllers
3. **Computed**: Derived values (authentication state, themes, features)

Business data takes precedence over computed data for testing flexibility.

### Key Bug Fixes Applied
- ✅ Fixed `false` values being converted to `nil` in context access
- ✅ Added `{{else}}` clause support in Rhales conditionals
- ✅ Normalized hash keys to strings for consistent access
- ✅ Proper template path resolution with configurable directories

## Migration Notes

When moving to standalone gem:
1. All global `OT.conf` references replaced with injected configuration
2. `V2::Customer` dependencies replaced with adapter interfaces
3. Refinements copied to `lib/rhales/refinements/` with fixed paths
4. Template paths configurable via `Rhales.configure`
5. Full backward compatibility maintained

## Testing Strategy

- **Unit Tests**: Each component tested in isolation
- **Integration Tests**: End-to-end template rendering
- **Adapter Tests**: Interface compliance verification
- **Mock Objects**: No external dependencies in tests

Current test coverage: 56 examples, 0 failures, comprehensive edge case coverage.

## Performance Considerations

- Template parsing cached with file modification time checking
- Immutable context objects prevent accidental mutations
- Configurable caching levels for different environments
- Efficient hash key normalization

## Security Features

- HTML escaping by default in template output
- CSP nonce injection for generated scripts
- CSRF token handling in data hydration
- No code execution in templates (data only)
- Input validation throughout the pipeline

This gem is intended for community use and follows modern Ruby gem standards
for maintainability, testability, and extensibility.
