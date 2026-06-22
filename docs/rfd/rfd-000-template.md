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

<!--
  prediscussion - just created, not yet ready for feedback
  ideation      - topic raised but not fully formed; early input welcome
  discussion    - ready for full review (PR open)
  published     - merged; the direction is finalized
  committed     - actively being implemented / in production
  abandoned     - no longer pursued (a replacement RFD should reference this one)
-->

## Date
Created: YYYY-MM-DD · Last updated: YYYY-MM-DD

## Modification rules

While an RFD is in `prediscussion` or `ideation` it may be freely reshaped. Once
it reaches `discussion` it is being acted on by others, so the record must stop
drifting. From `discussion` onward:

- **Frozen — do not rewrite**: Summary, Motivation, and each step's **ID** and
  **Goal**. A material change is not an edit: open a new RFD that supersedes this
  one, or append a dated amendment to Change log. Step IDs are permanent — never
  renumber or repurpose one; to drop a step, set its Status to `withdrawn` in place.
- **Append-only — add, never rewrite or delete**: Resulting decisions, Change log.
- **Living — may change in place**: the document **State**, per-step **Status**
  markers, Unresolved questions, and the "Last updated" date.

Progress is tracked by the per-step Status markers and Resulting decisions (ADR
links), recorded by appending to Change log — never by rewriting prose. Read those
to learn the current state; append to record a change.

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
