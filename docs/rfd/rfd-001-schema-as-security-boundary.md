---
id: "001"
state: discussion
title: "RFD-001: The schema as a mechanical security boundary"
authors: [Rhales maintainers]
discussion: https://github.com/onetimesecret/rhales/pull/63
labels: [security, hydration, schema]
---

<!-- Read "Modification rules" before editing. See docs/rfd/README.md. -->

## State
discussion

## Date
Created: 2026-06-22 · Last updated: 2026-06-22

## Modification rules

This RFD follows the repository's RFD modification rules (`docs/rfd/README.md`).
In short: from `discussion` onward, Summary, Motivation, and each step's **ID +
Goal** are **frozen**; Resulting decisions and Change log are **append-only**;
the document State, per-step **Status** markers, and Unresolved questions are
**living**. Track progress by the Status markers and Resulting decisions, not by
rewriting prose. Step IDs are permanent.

## Summary

*(Frozen.)* Rhales' headline security promise is that "only data declared in the
`<schema>` section reaches the client." Today that promise is **advisory**: the
entire `client:` hash is serialized to the browser, and the schema is used only
to validate and to log mismatches. This RFD proposes turning the schema into a
**mechanical** boundary — the schema becomes the allowlist the client payload is
projected through — and sequences that change across small, reviewable,
backward-compatible steps.

## Motivation

*(Frozen.)* The aggregator assembles the client payload and serializes the whole
hash; the schema never filters it:

```ruby
# lib/rhales/hydration/hydration_data_aggregator.rb (process_schema_section)
expected_keys = extract_expected_keys(template_name, schema_content)
# ... compares expected vs actual keys and LOGS any mismatch ...
processed_data = @context.client   # the ENTIRE client hash, unfiltered
```

The consequence is real: passing `client: { name: 'Alice', password: 'secret' }`
to a view whose schema only declares `name` still sends `password` to the
browser. Server-side key extraction is also weaker than it looks — reliable keys
come from a generated JSON Schema, but the regex fallback "will miss nested
object literals, complex compositions and unions, multiline definitions," so it
must never be used to *drop* data. (`json_schemer (~> 2)` is already a dependency,
so real JSON Schema validation on the server is within reach.)

Goals: make the promise a guarantee; keep every step opt-in until a major version
flips the default; be honest about the strength of each guarantee (never drop a
declared field an unreliable extractor missed); shrink the number of places that
must independently "get escaping right."

## Proposal

Each step is its own PR. A step's ID and Goal are frozen; its Status is living.

### Step 1 — Mechanical allowlist projection · Status: `done`
**Goal** *(frozen)*: add an opt-in `schema_projection` mode (`:off` default,
`:strip`, `:strict`) that projects the client payload through the schema's
declared keys before serialization, using only a reliable generated JSON Schema
(never the regex fallback). Crystallized by ADR-001.

### Step 2a — Deep (nested) projection · Status: `done`
**Goal** *(frozen)*: extend projection to follow the schema's full structure —
object `properties`, array `items`, typed `additionalProperties` records, local
`$ref`/`$defs` — dropping or reporting undeclared keys at any depth, while
passing through anything it cannot positively interpret. Crystallized by ADR-001.

### Step 2b — Server-side type validation · Status: `todo`
**Goal** *(frozen)*: validate the projected payload's types against the generated
JSON Schema with `json_schemer` before serialization, so `:strict` means "the
payload conforms to the contract," not merely "no undeclared keys." Moves the
middleware's post-render check earlier.

### Step 3 — One hardened serialization choke point, fuzzed · Status: `todo`
**Goal** *(frozen)*: funnel every client-bound value through a single encoder
(`JSONSerializer.dump_html_safe`), forbid other paths, and back it with
property-based/fuzz tests across `<script>`, attribute, and JSONP contexts.

### Step 4 — Prefer JSON data-islands over executable JS · Status: `todo`
**Goal** *(frozen)*: default to emitting hydration data as
`<script type="application/json">` + `JSON.parse`, a strictly smaller threat
model than interpolating into executable JS.

### Step 5 — Secure-by-default under a strict CSP · Status: `todo`
**Goal** *(frozen)*: package and document a strict-CSP hydration mode
(nonce/hash based, no inline eval) end to end.

### Step 6 — Auditability · Status: `todo`
**Goal** *(frozen)*: a rake task / dev overlay that prints, for a given view, the
declared schema and the exact data that will cross to the client.

## Non-goals

- Changing the template-side data model (templates keep full server context; the
  boundary is server→client).
- Removing the injection-strategy machinery. This RFD is about the data boundary.

## Alternatives considered

- **Filter at the `View` boundary instead of the aggregator.** The aggregator is
  the single point where per-template schema and per-template client data meet,
  so it is the natural place to project per window attribute.
- **Project using regex-extracted keys.** Rejected: the regex is documented as
  incomplete and would drop legitimate declared fields. Projection must be backed
  by a reliable schema source.

## Drawbacks and risks

- Projection is only as good as the generated JSON Schema; without one it is a
  no-op (by design) and the boundary stays advisory.
- A future default flip to a projecting mode is a breaking change and must ship
  with a deprecation window.

## Unresolved questions

*(Living.)*
- Final names for the projection modes and the eventual default.
- Whether Step 2b raises on type errors in `:strict` only, or also warns in `:strip`.

## Resulting decisions

*(Append-only.)*

- ADR-001: Schema projection as a mechanical client-data allowlist — crystallizes
  Steps 1 and 2a.

## Change log

*(Append-only.)*

- 2026-06-22: Created (discussion). Steps 1 and 2a implemented (PRs #62, #63);
  recorded as ADR-001 (Proposed).
