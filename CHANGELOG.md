# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Native Logging System**: Comprehensive production-ready logging with structured data support
  - Configurable logger with `Rhales.logger=` for unified logging infrastructure integration
  - Component-specific loggers: `Rhales::View.logger`, `Rhales::TemplateEngine.logger`, etc.
  - Compatible with both standard Ruby Logger and SemanticLogger
  - View rendering events: template name, layout, partials, duration, hydration size
  - Template compilation logging with timing and cache status
  - Schema validation logging with key mismatch detection
  - Security audit trail: unescaped variable warnings, CSP nonce generation, data sanitization
  - Performance insights: partial resolution depth/timing, cache hit rates, template recompilation triggers
  - Error logging with full context: parse errors with line/column, validation errors, render failures
- Window collision detection prevents silent data overwrites when multiple templates use the same window attribute
- Explicit merge strategies (shallow, deep, strict) for controlled data sharing between templates
- `HydrationCollisionError` with detailed error messages showing file paths and line numbers
- `HydrationRegistry` for thread-safe tracking of window attributes per request
- `merge_strategy` method on RueDocument to extract merge attribute from data elements
- JavaScript merge functions for client-side data composition
- Comprehensive test coverage for collision detection and merge strategies

### Changed
- Replaced `json-schema` gem with `json_schemer` for better JSON Schema Draft 2020-12 support
- Improved validation error messages with more structured output from json_schemer
- Validation performance improved to <0.05ms average (was ~2ms with json-schema)

### Security
- Window collision detection prevents accidental data exposure by making overwrites explicit
- All merge operations happen client-side after server-side interpolation and JSON serialization
- Request-scoped registry prevents cross-request data leakage

## [0.1.0] - 2024-01-XX

### Added
- Initial release of Rhales
- Ruby Single File Components (.rue files) with server-side rendering
- Client-side data hydration with secure JSON injection
- Handlebars-style template syntax
- Pluggable authentication adapters
- Framework-agnostic design with Rails and Roda examples
- Comprehensive test suite
