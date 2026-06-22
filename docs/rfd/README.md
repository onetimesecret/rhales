## Requests for Discussion (RFDs)

An RFD proposes a direction and explores options *before* (or around) the
decisions an ADR records. Where an ADR is the immutable record of a single
settled decision, an RFD is the **mutable, deliberative** document that frames a
problem, weighs alternatives, and may sequence a **multi-step** plan.

The model is Oxide Computer's [RFD process](https://rfd.shared.oxide.computer/rfd/0001).
In that spirit: *the minimum length for a useful note is one sentence.* Publish
rough thoughts early — a written statement is not authoritative just because it
is written down, so don't wait for polish to open an RFD.

### State

Every RFD records its lifecycle state in front-matter (`state:`):

| State | Meaning |
|---|---|
| `prediscussion` | Just created, not yet ready for feedback |
| `ideation` | Topic raised but not fully formed; early input welcome |
| `discussion` | Ready for full review (PR open) |
| `published` | Merged; direction finalized |
| `committed` | Actively being implemented / in production |
| `abandoned` | No longer pursued (a replacement RFD should reference it) |

Front-matter also carries `authors`, `discussion` (the PR link), and `labels`.

### Workflow

RFDs are git/PR-based, like Oxide's: reserve the next number, branch, write
`rfd-NNN-kebab-slug.md` from `rfd-000-template.md`, open a PR with state
`discussion` (or `ideation` for rough ideas), and merge to `published`. No direct
pushes to the trunk.

### RFD vs ADR

| | RFD | ADR |
|---|---|---|
| Question | "Should we, and how?" | "We decided X." |
| Time | Forward-looking | Backward-looking record |
| Scope | May span multiple steps/decisions | Exactly one decision |
| Mutability | Mutable; evolves with discussion | Immutable once accepted |

The two form a pipeline: an **RFD proposes → discussion happens → each settled
piece becomes an ADR.** Keep the link in both directions — an RFD lists the ADRs
it produced under "Resulting decisions", and each ADR references its RFD.

### Why "RFD" and not "RFC"

We avoid "RFC" on purpose. In the IETF tradition a *published* RFC is
**immutable** — changes ship as a new RFC that Updates/Obsoletes the old one —
and the mutable, evolving working document is the **Internet-Draft**. A mutable
"RFC" therefore inverts the IETF mapping (our living proposal is closer to an
Internet-Draft). "RFD" (Request for **Discussion**, Oxide's term) is purpose-built
for an explicitly living proposal and sidesteps that collision.

### Modification rules

An RFD is mutable, but a long roadmap touched by many contiguous sessions (human
or agent) will drift if every editor is free to rewrite the spine. These rules
are the guard and are mandatory once an RFD reaches `discussion`. They are
canonical here; an RFD carries only a short copy plus a pointer back to this
section.

- **Frozen — do not rewrite**: Summary, Motivation, and each step's ID and Goal.
  A material change is not an edit — supersede with a new RFD or append a dated
  amendment to Change log. **Step IDs are permanent**; never renumber or repurpose
  them, and to drop a step set its Status to `withdrawn` in place.
- **Append-only — add, never rewrite or delete**: Resulting decisions, Change log.
- **Living — may change in place**: the document State, per-step Status markers,
  Unresolved questions, and the "Last updated" date.

Progress is single-sourced in the per-step Status markers and Resulting decisions
(ADR links), recorded by appending to the Change log — never by rewriting
narrative. An editor *reads* state from those two places and *records* it by
flipping a marker and appending. The effect: each session leaves an auditable
trail instead of overwriting the last one's account of where things stand.

### Local conventions

This repo keeps RFDs as flat Markdown files (`rfd-NNN-kebab-slug.md`) to mirror
its ADR naming (`adr-NNN-kebab-slug.md`), uses 3-digit numbers for parity with
ADRs, and pairs each settled step with an ADR — diverging from Oxide's
AsciiDoc, per-RFD directories, and 4-digit numbering. Start from
`rfd-000-template.md`.
