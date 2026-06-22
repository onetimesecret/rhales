# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Schema projection (RFC 0001, Steps 1 & 2a)**: the `<schema>` can now act as a
  mechanical allowlist for client data instead of an advisory one. New
  `config.schema_projection` mode:
  - `:off` (default) — unchanged behavior; the entire `client:` hash is
    serialized and the schema is advisory.
  - `:strip` — the client payload is projected to the schema's declared keys
    before serialization; undeclared keys are dropped.
  - `:strict` — like `:strip`, but undeclared keys raise the new
    `Rhales::HydrationSchemaViolationError` (with the dotted path of each).

  Projection follows the generated JSON Schema's full nested structure — object
  `properties`, array `items`, typed `additionalProperties` records, and local
  `$ref`/`$defs` — dropping or reporting undeclared keys at any depth. It is
  deliberately conservative: anything it cannot interpret (`anyOf`/`oneOf`/
  `allOf`, unresolvable/cyclic `$ref`, primitives) is passed through unchanged.
  Projection runs only when a reliable generated JSON Schema exists for the
  template (`rake rhales:schema:generate`); it never projects from the regex
  fallback and never drops a field it cannot verify. Full type validation of the
  projected payload via `json_schemer` is sequenced next — see
  `docs/rfc/0001-schema-as-security-boundary.md`.

### Fixed
- `HydrationDataAggregator` now honors `config.schemas_dir` when locating
  generated JSON Schemas instead of always using `Dir.pwd/public/schemas`
  (resolved lazily). Behavior is unchanged for the default configuration.

## [0.7.1] - 2026-06-22

### Security
- Validate the schema `window` attribute against a JavaScript identifier pattern
  (`/\A[a-zA-Z_][a-zA-Z0-9_]*\z/`) at parse time; invalid names raise
  `RueDocument::ParseError` (#57).
- Escape the window name at every hydration render site as defense in depth:
  HTML-escape it in `data-window` / `data-hydration-target` attributes and
  JSON-encode it (`JSONSerializer.dump_html_safe`) in `window[...]` script
  contexts, in both `View` and `LinkBasedInjectionDetector`. Previously an
  unescaped window name could break out of the HTML attribute or JS string (#57).
- Stop logging the raw CSP nonce value. `CSP.generate_nonce` and
  `CSP#build_header` now log only length/entropy/usage metadata, never the
  per-response secret itself (#57).
- Escape the remaining interpolated config values in `LinkBasedInjectionDetector`
  for the same reason: `endpoint_url` / `template_name` (HTML-escaped in `href` /
  `data-lazy-src`, JSON-encoded in `fetch(...)` / `import` / loader calls) and the
  lazy `mount_selector` (JSON-encoded in `document.querySelector(...)`), so a
  single/double quote in those config values can no longer break out of its
  context (#59 review).

## [0.7.0] - 2026-06-21

### Security
- Validate JSONP callback names against a JS identifier / dotted-path pattern to
  block reflected XSS; invalid names raise `ArgumentError` (`HydrationEndpoint#render_jsonp`).
- Escape `<`, `>`, `&`, U+2028, and U+2029 in hydration JSON so payloads like
  `</script>` can't break out of the script context (`JSONSerializer.dump_html_safe`,
  used by `View` and `HydrationEndpoint`).

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
