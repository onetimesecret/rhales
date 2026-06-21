# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.7.0] - 2026-06-21

### Security
- **JSONP callback name validation** (`Rhales::HydrationEndpoint#render_jsonp`):
  the caller-supplied callback name was reflected verbatim into the executable
  response body, allowing arbitrary JavaScript injection (XSS) via a payload
  such as `alert(1)//`. Callback names are now validated against a JavaScript
  identifier / dotted member-path pattern and an invalid name raises
  `ArgumentError` before any template data is processed.
- **JSON-in-HTML/JS escaping** (`Rhales::JSONSerializer.dump_html_safe`): standard
  JSON generation does not escape `<`, `>`, `&`, U+2028 or U+2029, so hydration
  data containing `</script>` could break out of the surrounding script context
  and inject markup/JavaScript (XSS). The new `dump_html_safe` escapes those
  characters as `\uXXXX` (equivalent JSON that round-trips identically) and is now
  used for the HTML hydration `<script type="application/json">` data block
  (`View`) and the ES module / JSONP endpoint bodies (`HydrationEndpoint`).

## [0.6.2] - 2026-05-25

### Added
- **Automated gem release workflow** (`.github/workflows/release-gem.yml`):
  builds and publishes the gem to RubyGems.org via Trusted Publishing
  (OIDC) whenever a GitHub Release is published with a `vMAJOR.MINOR.PATCH`
  tag. Verifies the tag matches `Rhales::VERSION` before pushing.

### Changed
- **Dependencies**: bumped `unicode-emoji` from 4.0.4 to 4.2.0 and
  `unicode-display_width` from 3.1.4 to 3.2.0. The previous
  `unicode-emoji` cap of `< Ruby 4.0` broke `bundle install` on Ruby 4.x;
  4.2.0 lifts that cap.
- **Gemfile.lock**: platform list normalized via
  `bundle lock --normalize-platforms` so platform-specific gems no longer
  trigger setup-ruby warnings on CI.

## [0.6.1] - 2026-05-25

### Added
- **Server-rendered random tokens example** (`examples/token-loader.rue`):
  pattern-teaching example showing how to generate per-request data with
  `SecureRandom.hex` in a Ruby view model, validate a nested
  `z.array(z.object(...))` shape, and walk it with nested `{{#each}}` blocks
  that fall through to the current outer item without explicit bindings. The
  original loader-animation use case is documented as a CSS-only follow-on in
  the `<logic>` block. (#49)

### Changed
- **Minimum Ruby version lowered from 3.4 to 3.2** - broader compatibility with stable Ruby releases; CI now exercises 3.2, 3.3, 3.4, and 3.5

### Fixed
- `{{#each}}` block variable `@last` now correctly returns `true` for the final
  iteration instead of always `false`. Enables comma-separated output via
  `{{#unless @last}},{{/unless}}` and similar patterns. `EachContext` now
  accepts and stores the collection's total length.

## [0.6.0] - 2026-03-21

### Added
- **External Schema References**: Schema definitions can now reference external TypeScript/JavaScript files via the `src` attribute
  - Enables single-source-of-truth patterns where TypeScript schemas drive both frontend types and Rhales validation
  - Path resolution relative to template file with security checks to prevent path traversal
  - Rake task output now shows inline vs external schema sources
  - Example: `<schema src="schemas/user.schema.ts" lang="js-zod" window="__USER__">`
- **Multi-directory Schema Search**: New `schema_search_paths` configuration option
  - Allows searching multiple directories for external schema files
  - Resolution order: template-relative first, then search paths in order
  - Security checks apply to all configured paths
- **tsx Import Mode**: New bundling mode for external schemas with imports
  - `schema_use_tsx_import = true` enables esbuild bundling
  - `schema_tsconfig_path` allows custom TypeScript configuration
  - Externalizes zod to prevent dual-instance issues
  - Cross-platform file:// URL support for Windows ESM compatibility
- **Production Logging**: Structured logging via `Rhales.logger=` for security auditing and debugging
  - View rendering events with template details, timing, and hydration size
  - Schema validation warnings for production debugging (missing/extra keys)
  - Error logging with line numbers and section context
  - Security events: unescaped variable warnings, CSP nonce generation
  - Performance logging: template compilation, cache behavior, partial resolution
- Window collision detection prevents silent data overwrites when multiple templates use the same window attribute
- Explicit merge strategies (shallow, deep, strict) for controlled data sharing between templates
- `HydrationCollisionError` with detailed error messages showing file paths and line numbers
- `HydrationRegistry` for thread-safe tracking of window attributes per request
- `merge_strategy` method on RueDocument to extract merge attribute from data elements
- JavaScript merge functions for client-side data composition
- Comprehensive test coverage for collision detection and merge strategies

### Changed
- **Ruby 3.4+ required** (was 3.3.4) - aligns with current LTS ecosystem; no Ruby 3.3 features relied upon, but 3.4 is recommended for YJIT improvements and json_schemer performance
- Updated zod to 4.3.6
- Relaxed json_schemer dependency from ~> 2.3 to ~> 2
- Replaced `json-schema` gem with `json_schemer` for better JSON Schema Draft 2020-12 support
- Improved validation error messages with more structured output from json_schemer
- Validation performance improved to <0.05ms average (was ~2ms with json-schema)

### Removed
- Unused `HydrationRegistry.clear!` method

### Security
- Window collision detection prevents accidental data exposure by making overwrites explicit
- All merge operations happen client-side after server-side interpolation and JSON serialization
- Request-scoped registry prevents cross-request data leakage

## [0.1.0] - 2025-07-21

### Added
- Initial release of Rhales
- Ruby Single File Components (.rue files) with server-side rendering
- Client-side data hydration with secure JSON injection
- Handlebars-style template syntax
- Pluggable authentication adapters
- Framework-agnostic design with Rails and Roda examples
- Comprehensive test suite
