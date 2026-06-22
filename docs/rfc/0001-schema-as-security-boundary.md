# RFC 0001: The schema as a mechanical security boundary

- Status: Draft
- Author: Rhales maintainers
- Scope: hydration data flow, schema role, client-bound serialization

## Summary

Rhales' headline security promise is that "only data declared in the `<schema>`
section reaches the client." Today that promise is **advisory**: the schema is
used to validate and to log mismatches, but the entire `client:` hash is
serialized to the browser regardless of what the schema declares. This RFC
proposes turning the schema into a **mechanical** boundary — the schema becomes
the allowlist that the client payload is projected through — and sequences that
change across several small, reviewable, backward-compatible PRs.

## Background: what happens today

The aggregator assembles the client payload and serializes the whole hash. The
schema never filters it:

```ruby
# lib/rhales/hydration/hydration_data_aggregator.rb
# (process_schema_section)
expected_keys = extract_expected_keys(template_name, schema_content)
# ... compares expected vs actual keys and LOGS any mismatch ...

# Direct serialization of client data (no template interpolation)
processed_data = @context.client   # <-- the ENTIRE client hash, unfiltered
```

This is documented honestly in `docs/architecture/data-flow.md`
("⚠️ Schema is a Validator, NOT a Filter"), and the consequence is real:

```ruby
view = Rhales::View.new(request, client: { name: 'Alice', password: 'secret' })
# schema: z.object({ name: z.string() })
# Browser receives: window.data = { "name": "Alice", "password": "secret" }
```

Server-side key extraction is also weaker than it looks. Reliable keys come from
a generated JSON Schema file (`public/schemas/<template>.json`), but when that is
absent the aggregator falls back to a **regex** over the Zod source that, by its
own documentation, "will miss nested object literals, complex compositions and
unions, multiline definitions." Validation/logging on top of regex-extracted
keys is therefore unreliable, and must never be used to *drop* data.

Separately, `json_schemer (~> 2)` is already a dependency (used by
`lib/rhales/middleware/schema_validator.rb`), so real JSON Schema validation on
the server is within reach — it is not yet applied to the pre-serialization
payload.

## Goals

1. Make "only declared data reaches the client" a guarantee, not a convention.
2. Keep every step backward-compatible and opt-in until a major version flips
   the default.
3. Be honest about the strength of each guarantee — never silently drop a
   declared field because an unreliable extractor missed it.
4. Shrink the number of places that independently have to "get escaping right."

## Non-goals

- Changing the template-side data model (templates still have full server
  context access; the boundary is server→client).
- Removing the injection-strategy machinery. This RFC is about the data
  boundary, not injection performance.

## Proposed direction (sequenced)

Each step is intended to be its own PR. This RFC ships with **Step 1**.

### Step 1 — Mechanical allowlist projection (this PR)

Introduce a `schema_projection` configuration mode:

- `:off` (default) — current behavior; the schema is advisory.
- `:strip` — project the client payload to the schema's declared top-level keys
  before serialization; drop undeclared keys.
- `:strict` — like `:strip`, but raise `HydrationSchemaViolationError` when
  undeclared keys are present.

Projection only runs when a **reliable** key source is available — a generated
JSON Schema file. When projection is requested but only the regex fallback would
be available, projection is skipped and a warning is logged (the payload is
emitted unprojected). This avoids the footgun of dropping a declared field
because the regex missed it, and makes the gap visible.

Scope limit: Step 1 projects **top-level** keys only (`properties.keys` of the
JSON Schema). That already closes the most dangerous case — an undeclared
top-level field such as `password` or `api_key` leaking wholesale. Nested
projection is deferred to Step 2.

### Step 2 — Real server-side validation and deep projection

Use `json_schemer` against the generated JSON Schema to validate the payload's
*types*, not just key names, and to project nested structures. This replaces the
regex fallback for any enforcing decision and lets `:strict` mean "the payload
conforms to the contract," not merely "no undeclared top-level keys."

### Step 3 — One hardened serialization choke point, fuzzed

Funnel every client-bound value through a single encoder
(`JSONSerializer.dump_html_safe`) and forbid other paths. Back it with
property-based/fuzz tests across the `<script>`, HTML-attribute, and JSONP
contexts so the next breakout is caught by tests rather than in production.

### Step 4 — Prefer JSON data-islands over executable JS

Default to emitting hydration data as `<script type="application/json">` +
`JSON.parse`, which only ever needs `<` and `</script>` neutralized — a strictly
smaller, fully auditable threat model than interpolating into executable JS.

### Step 5 — Secure-by-default under a strict CSP

Package and document a strict-CSP hydration mode (nonce/hash based, no inline
eval) end to end. The CSP machinery already exists; this is mostly a coherent,
documented default.

### Step 6 — Auditability

A rake task / dev overlay that, for a given view, prints the declared schema and
the exact data that will cross to the client, so a reviewer can sign off on the
boundary per route.

## Backward compatibility and transition

- Step 1 defaults to `:off`; no existing behavior changes unless a project opts
  in.
- Projects are encouraged to generate JSON Schemas (`rake rhales:schema:generate`)
  and adopt `:strip`, then `:strict`, as they gain confidence.
- A future major version is expected to default `schema_projection` to a
  projecting mode. That flip will be announced with a deprecation window and a
  clear upgrade note.

## Alternatives considered

- **Filter at the `View` boundary instead of the aggregator.** The aggregator is
  the single point where per-template schema and per-template client data meet,
  so it is the natural place to project per window attribute. Filtering in `View`
  would not have per-schema granularity.
- **Project using regex-extracted keys.** Rejected: the regex is documented as
  incomplete and would drop legitimate declared fields. Projection must be backed
  by a reliable schema source.
