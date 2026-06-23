# Feature Implementation Guidelines

## Common Commands
- Use bin/rackup to run the dev server
- bundle exec rspec spec/rhales/: Run test suite for current changes
- gem build rhales.gemspec: Build the gem
- bundle exec rspec spec/rhales/ --format documentation: Run tests with verbose output
- rake rhales:test: Run Rhales-specific tests
- rake rhales:validate: Validate template files
- git worktree add ../feature-name feature-branch: Create parallel workspace
- gh issue view [number]: Review GitHub issue details
- gh pr create: Create pull request with context-aware commit message

## Workflow: Feature Implementation

### 1. Research & Planning Phase
IMPORTANT: Always research and plan before coding. Spend extra planning effort on complex or security-sensitive features.

- Read relevant files and documentation WITHOUT writing code yet
- Understand the two-layer data system (app, props)
- Review adapter interfaces and dependency injection patterns
- Create implementation plan in markdown file or GitHub issue
- Document security implications and edge cases

### 2. Implementation Phase
Follow test-driven development when possible:

1. Write RSpec tests first (mark with "TDD - no implementation yet")
2. Confirm tests fail appropriately
3. Commit tests
4. Implement code to pass tests WITHOUT modifying tests
6. Verify HTML escaping and security measures
7. Commit implementation

### 3. Validation & Review
- Run full test suite: `bundle exec rspec spec/rhales/`
- Check for any global configuration usage
- Update README.md and CHANGELOG.md with changes
- Verify YARD documentation is complete
- Use `gh` to create descriptive pull request
- Address review comments in separate commits

## Code Style
- CRITICAL: Make MINIMAL changes to existing patterns
- Preserve existing naming conventions and file organization
- Use existing utility functions - avoid duplication
- Use dependency injection over global state
- Maintain adapter interface compliance
- Keep context objects immutable
- Ensure proper HTML escaping in templates

## Multi-Task Guidelines
For complex features requiring parallel work:
- Use git worktrees for independent components
- Keep adapter changes separate from core changes
- Start a fresh session/context between unrelated tasks to keep context focused
- Document progress in CHANGELOG.md

## Project-Specific Notes

### Core Components to Consider
- **Configuration**: Block-based configuration with validation
- **Context**: Three-layer system with dot-notation access
- **Parsers**: Two manual recursive descent parsers, for .rue files and handlebars templates
- **Parser**: .rue file parsing with manual recursive descent
- **Rhales**: Handlebars-style template engine
- **Hydrator**: Client-side data injection with CSP support
- **Adapters**: Pluggable auth and session interfaces


### Key File Locations
- **Core Logic**: `lib/rhales/`
- **Main Entry Point**: `lib/rhales.rb`
- **Unit & Integration Tests**: `spec/rhales/`
- **Gem Specification**: `rhales.gemspec`
- **Rake Tasks**: `Rakefile`

### Key Patterns
- **Template Syntax**: Uses Handlebars-style syntax (e.g., `{{variable}}`, `{{#if condition}}...{{/if}}`, `{{> partial_name}}`)
- **Data Hydration**: Uses a `<schema>` block in `.rue` files to define a zod v4 schema in plain Javascript for client-side hydration
- **Security**: Default HTML escaping, CSP nonce support for scripts, and CSRF token handling are built-in
- **Configuration**: All configuration is handled via an injected `Configuration` object, avoiding global state

### Testing Patterns
- Mock adapters for auth/session testing
- Use fixtures in `spec/fixtures/templates/`
- Test all three context layers independently
- Verify template caching behavior
- Check false/nil handling explicitly

## Resuming work

Re-orient with **Map → Mail → Mess**:

1. **Map — the plan.** First `todo` in the active RFD (`docs/rfd/`), any
   `docs/adr/` `Status:`, and `CHANGELOG.md` `[Unreleased]`.
2. **Mail — what's waiting.** Open PRs: red CI, unresolved review threads, each
   PR's `## Next`. Note what merged or closed since.
3. **Mess — local state.** `git fetch`, then `git branch --show-current`,
   `git status`, `git stash list`, `git log --oneline -10`.

Next step is the first that fires: a PR waiting on you → a roadmap `todo` →
local half-finished work.

Before stopping, leave a breadcrumb: flip a step's `Status:` in the RFD, update
the PR's `## Next`, or add a `TODO(next):` to the final commit.
