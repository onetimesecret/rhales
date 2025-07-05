# Feature Implementation Guidelines

## Common Commands
- bundle exec rspec spec/rhales/: Run all Rhales tests
- bundle exec rspec spec/rhales/ --format documentation: Run tests with documentation format
- rake rhales:test: Run Rhales-specific tests
- rake rhales:docs: Generate documentation
- gem build rhales.gemspec: Build the gem
- gem install rhales-0.1.0.gem: Install the gem locally
- git worktree add ../feature-name feature-branch: Create parallel workspace
- gh issue view [number]: Review GitHub issue details
- gh pr create: Create pull request with context-aware commit message

## Workflow: Feature Implementation

### 1. Research & Planning Phase
IMPORTANT: Always research and plan before coding. Use "think" or "think hard" for complex features.

- Read relevant files and documentation WITHOUT writing code yet
- Use subagents to investigate specific technical questions
- Create implementation plan in markdown file
- Document edge cases and potential complications

### 2. Implementation Phase
Follow test-driven development when possible:

1. Write tests first in the `spec/rhales/` directory (mark with "TDD - no implementation yet")
2. Confirm tests fail appropriately (`bundle exec rspec spec/rhales/your_spec.rb`)
3. Commit tests
4. Implement code in `lib/rhales/` to pass the tests WITHOUT modifying tests
5. Use subagents to verify implementation isn't overfitting
6. Commit implementation

### 3. Validation & Review
- Run the full test suite before committing (`bundle exec rspec spec/rhales/`)
- Update `README.md` and `CHANGELOG.md` with changes
- Use `gh` to create a descriptive pull request
- Address review comments in separate commits

## Code Style
- CRITICAL: Make MINIMAL changes to existing patterns
- Preserve existing naming conventions and file organization
- Use existing utility functions - avoid duplication
- Follow established architecture patterns
- Keep commits focused and logical

## Multi-Task Guidelines
For complex features requiring parallel work:
- Use git worktrees for independent tasks
- Keep one task per worktree/terminal
- Use /clear between unrelated tasks to optimize context
- Document progress in shared markdown checklist

## Project-Specific Notes

### Architecture
The system is built around several core components:
- `Configuration`: Handles dependency injection
- `Context`: Manages a three-layer data system (runtime, business, computed)
- `Parser`: Parses `.rue` files into `<data>`, `<template>`, and `<logic>`
- `Rhales`: A Handlebars-style template engine
- `Hydrator`: Manages client-side data injection
- `View`: Orchestrates the rendering pipeline
- `Adapters`: Provides pluggable authentication and session management

### Key File Locations
- **Core Logic**: `lib/rhales/`
- **Main Entry Point**: `lib/rhales.rb`
- **Unit & Integration Tests**: `spec/rhales/`
- **Gem Specification**: `rhales.gemspec`
- **Rake Tasks**: `Rakefile`

### Key Patterns
- **Template Syntax**: Uses Handlebars-style syntax (e.g., `{{variable}}`, `{{#if condition}}...{{/if}}`, `{{> partial_name}}`)
- **Data Hydration**: Uses a `<data>` block in `.rue` files to define a JSON object for client-side hydration, which supports variable interpolation
- **Security**: Default HTML escaping, CSP nonce support for scripts, and CSRF token handling are built-in
- **Configuration**: All configuration is handled via an injected `Configuration` object, avoiding global state
