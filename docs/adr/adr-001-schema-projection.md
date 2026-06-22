---
id: "001"
status: proposed
title: "ADR-001: Schema projection as a mechanical client-data allowlist"
---

## Status
Proposed

<!-- Flips to Accepted when PRs #62 and #63 merge. Originates from RFC-001
     (docs/rfc/rfc-001-schema-as-security-boundary.md), Steps 1 and 2a. -->

## Date
2026-06-22

## Context

Rhales tells users that "only data declared in the `<schema>` reaches the
client," but that boundary was advisory, not enforced. `HydrationDataAggregator`
serialized the entire `client:` hash and used the schema only to log key
mismatches, so passing `client: { name:, password: }` to a view whose schema
declares only `name` still shipped `password` to the browser. Server-side key
extraction also has an unreliable regex fallback that misses nested/union/
multiline shapes, so it cannot safely be used to *drop* data.

## Decision

Introduce `config.schema_projection`, which makes the schema a mechanical
allowlist the client payload is projected through before serialization:

- `:off` (default) — unchanged advisory behavior.
- `:strip` — drop undeclared keys.
- `:strict` — raise `Rhales::HydrationSchemaViolationError` (with the dotted path
  of each undeclared key).

Projection follows the generated JSON Schema's full structure (object
`properties`, array `items`, typed `additionalProperties` records, local
`$ref`/`$defs`) and is **reliable-source only**: it runs only when a generated
JSON Schema exists, never from the regex fallback, and it is **conservative** —
anything it cannot positively interpret (`anyOf`/`oneOf`/`allOf`, unresolvable or
cyclic `$ref`, primitives) is passed through unchanged. It never drops a field it
cannot account for.

Why opt-in with `:off` as the default: turning the boundary on by default would
be a breaking change for apps that currently rely on extra keys flowing through.
Shipping it opt-in lets teams generate JSON Schemas and adopt `:strip` then
`:strict` incrementally; a future major version is expected to default to a
projecting mode with a deprecation window.

Why the aggregator (not `View`): it is the single point where a template's schema
and its client data meet, so it can project per window attribute.

## Consequences

### Positive
- "Only declared data reaches the client" becomes enforceable, not aspirational;
  defense in depth against accidental exposure of sensitive server data.
- Projection is deep, so the guarantee holds at every level of the structure.

### Negative / Neutral
- The guarantee is only as strong as the generated JSON Schema; with no schema it
  is a deliberate no-op and the boundary stays advisory.
- Type conformance is not yet enforced pre-serialization (the middleware still
  validates post-render); that is RFC-001 Step 2b.

## Implementation Notes

### Initial implementation (2026-06-22)
Step 1 (top-level projection, config, error class, `schemas_dir` honored) landed
in PR #62; Step 2a (deep/nested projection) in PR #63. `schema_projection`
defaults to `:off`; full suite green. See RFC-001 for the surrounding roadmap.
