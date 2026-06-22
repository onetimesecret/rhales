## Requests for Comments (RFCs)

RFCs propose a direction and explore options *before* (or around) the decisions
that an ADR records. Where an ADR is the immutable record of a single settled
decision, an RFC is the **mutable, deliberative** document that frames a problem,
weighs alternatives, and may sequence a **multi-step** plan.

**Lifecycle:**
- Draft: Being written; not yet ready for feedback
- Proposed: Ready for discussion / review
- Accepted: Direction agreed (in whole or in part); see "Resulting decisions"
- Superseded: Replaced by a newer RFC (reference it)
- Withdrawn: Abandoned

### RFC vs ADR

| | RFC | ADR |
|---|---|---|
| Question | "Should we, and how?" | "We decided X." |
| Time | Forward-looking | Backward-looking record |
| Scope | May span multiple steps/decisions | Exactly one decision |
| Mutability | Mutable; evolves with discussion | Immutable once accepted |

The two form a pipeline: an **RFC proposes → discussion happens → each settled
piece becomes an ADR.** Keep the link in both directions — an RFC lists the ADRs
it produced under "Resulting decisions", and each ADR references its RFC.

### A note on the name

Calling these documents "mutable RFCs" is a deliberate departure from the IETF
sense of the term. In the IETF, the *published* RFC is **immutable** — changes
ship as a new RFC that Updates/Obsoletes the old one — and the mutable, evolving
working document is the **Internet-Draft**. So in spirit our RFC is closer to an
IETF Internet-Draft, and our ADR is the frozen record. We keep the word "RFC"
because the looser, mutable-proposal usage is the dominant one in software orgs
(Rust RFCs, Python PEPs, Oxide RFDs all treat the proposal doc as living to
varying degrees). IETF immutability is one well-known convention, not the only
one — but if the collision is confusing, "RFD" (Request for Discussion) is the
cleaner name for an explicitly living proposal.

### Avoiding game-of-telephone across sessions

An RFC is mutable, but a long roadmap touched by many contiguous sessions (human
or agent) will drift if every editor is free to rewrite the spine. The template's
**Modification rules** section is the guard, and it is mandatory:

- The **spine is frozen** once Proposed: Summary, Motivation, and each step's ID
  and Goal. Material changes are not edits — supersede the RFC or append a dated
  amendment. **Step IDs are permanent**; never renumber or repurpose them.
- **Progress is append-only and single-sourced**: state lives in the per-step
  Status markers and the Resulting decisions (ADR links), updated by appending to
  the Change log — never by rewriting narrative. An editor *reads* state from
  those two places and *records* state by flipping a marker and appending.

The effect: each session leaves an auditable trail instead of overwriting the
last one's account of where things stand.

### Keys to success

- **Readable in a few minutes**: focus on the "why" and the shape of the proposal.
- **Be honest about state**: when a proposal is staged, mark each step done / in
  progress / future so the roadmap doesn't overclaim.
- **Don't bundle decisions into ADRs prematurely**: the roadmap belongs here; only
  the settled pieces graduate to ADRs.
- **Numbered sequentially**: `RFC-001`, `RFC-002`, …

Start from `rfc-000-template.md`.
