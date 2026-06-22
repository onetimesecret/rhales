---
id: 000
status: draft
title: "RFC-000: [Short Title]"
---

<!-- Filename: rfc-NNN-kebab-slug.md (slug derived from title) -->

<!--
An RFC proposes a direction and explores options. Unlike an ADR it is MUTABLE
and may span MULTIPLE decisions or steps. When a part of an RFC is actually
decided, record that decision as an ADR and link it under "Resulting decisions".
READ "Modification rules" BEFORE EDITING — it is what keeps long, multi-session
work from distorting the record.
-->

## Status
[Draft | Proposed | Accepted | Superseded | Withdrawn]

## Date
Created: YYYY-MM-DD · Last updated: YYYY-MM-DD

## Modification rules

After Status reaches `Proposed`, sections may change only as classified below.
This is the contract that prevents a multi-session "telephone" drift: the spine
is frozen, progress is recorded by appending, and only a few fields are live.

- **Frozen — do not rewrite**: Summary, Motivation, and each step's **ID** and
  **Goal**. A material change to a frozen element is not an edit. Either
  supersede this RFC with a new one, or append a dated entry to Change log
  describing the amendment. Step IDs are permanent identifiers — never renumber
  or repurpose one; to drop a step, set its Status to `withdrawn` in place.
- **Append-only — add, never rewrite or delete**: Resulting decisions, Change log.
- **Living — may be updated in place**: per-step Status markers, Unresolved
  questions, and the "Last updated" date.

Progress is tracked by (a) the per-step **Status** markers and (b) **Resulting
decisions** — never by editing prose in Proposal. To learn the current state,
read those two. To record a state change, flip the marker, add the ADR link, and
append a Change log line. Do not restate progress by rewriting the narrative.

## Summary
*(Frozen.)* One paragraph that stands on its own: what this proposes and why.

## Motivation
*(Frozen.)* What problem or opportunity drives this? What is broken, missing, or
risky today? What constraints apply (technical, security, time, compatibility)?

## Proposal
The substance, staged into steps. Each step has a permanent **ID** and a
**Status** marker. A step's ID and one-line Goal are frozen once the RFC is
Proposed; the step's details may be refined only while its Status is `todo`.

### Step 1 — [Title] · Status: `todo`
**Goal** *(frozen)*: one sentence describing the intended outcome.

[Details, which may be refined until this step starts. Status values:
`todo` | `in progress` | `done` | `withdrawn`.]

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
*(Append-only.)* ADRs this RFC has produced, kept in sync as steps are decided:

- ADR-NNN: [title] — crystallizes Step N

## Change log
*(Append-only.)* One dated line per state change or amendment:

- YYYY-MM-DD: Created (Draft).
