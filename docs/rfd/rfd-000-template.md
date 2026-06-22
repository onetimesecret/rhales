---
id: 000
state: prediscussion
title: "RFD-000: [Short Title]"
authors: [Name <handle>]
discussion: [link to the PR where this RFD is discussed]
labels: [comma, separated, topics]
---

<!-- Filename: rfd-NNN-kebab-slug.md (slug derived from title).

An RFD (Request for Discussion) is the MUTABLE, deliberative home for an idea —
modeled on Oxide's RFD process. Unlike an ADR it may span MULTIPLE decisions or
steps. When a part of an RFD is actually decided, record that decision as an ADR
and link it under "Resulting decisions".

The minimum length for a useful note is one sentence — publish rough thoughts
early rather than waiting for polish. READ "Modification rules" before editing an
RFD that has reached `discussion`. -->

## State
[prediscussion | ideation | discussion | published | committed | abandoned]

<!-- State meanings: see docs/rfd/README.md (### State). -->

## Date
Created: YYYY-MM-DD · Last updated: YYYY-MM-DD

## Modification rules

Canonical rules and rationale: `docs/rfd/README.md` (### Modification rules). In
short, once this RFD reaches `discussion`:

- **Frozen** (supersede or append an amendment instead of rewriting): Summary,
  Motivation, and each step's ID and Goal. Step IDs are permanent.
- **Append-only**: Resulting decisions, Change log.
- **Living**: State, per-step Status markers, Unresolved questions, Last updated.

Track progress with the Status markers and Resulting decisions, not by rewriting
prose.

## Summary
*(Frozen once `discussion`.)* One paragraph that stands on its own: what this
proposes and why.

## Motivation
*(Frozen once `discussion`.)* What problem or opportunity drives this? What is
broken, missing, or risky today? What constraints apply?

## Proposal
The substance, staged into steps. Each step has a permanent **ID** and a
**Status** marker (distinct from the document's State). A step's ID and one-line
Goal freeze when the RFD reaches `discussion`; details may be refined only while
the step's Status is `todo`.

### Step 1 — [Title] · Status: `todo`
**Goal** *(frozen once `discussion`)*: one sentence describing the intended
outcome. [Status values: `todo` | `in progress` | `done` | `withdrawn`.]

<!-- Optional sections below — include only when they add value -->

## Non-goals
What this explicitly does not address.

## Alternatives considered
Options weighed and why they were not chosen.

## Drawbacks and risks
Costs of doing this; what could go wrong.

## Unresolved questions
*(Living.)* Open points that still need a decision or discussion.

## Resulting decisions
*(Append-only.)* ADRs this RFD has produced, kept in sync as steps are decided:

- ADR-NNN: [title] — crystallizes Step N

## Change log
*(Append-only.)* One dated line per state change or amendment:

- YYYY-MM-DD: Created (prediscussion).
