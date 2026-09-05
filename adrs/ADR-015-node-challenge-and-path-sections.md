# ADR-015: Challenge belongs to the path node; the student path is a self-contained sectioned sequence

**Status:** Accepted
**Date:** 2026-09-03
**Deciders:** Gilson (Product Owner)

---

## Context

The PB-8j Student Alpha UX Foundation review raised structural questions that the current
model does not answer, and that shape every student-facing slice (PB-8c–8f).

**The lesson screen (S6) is overloaded.** A student opens a path node into S6, where they
watch a video or read an article. Review established that (a) the video must dominate the
screen — a small or below-the-fold player is the single most likely cause of alpha dropout
for the target persona, an informal learner who has abandoned apps before — and (b) S6 must
present *timed complementary resources* that appear at defined points during playback (for
example a chord diagram at 1:10) without stopping the video. The current PB-8j draft also
places a challenge call-to-action on S6 whenever the node has a challenge, giving three
demands on one screen, the weakest of which competes for the space the video needs.

**The path (S5) has no first-class grouping, and the draft grouped it by time.** The current
`GET /students/me/path` returns a flat ordered list of items with per-item status and a
`current_position`. The PB-8j draft and the test fixtures ("week-1-path", "Beginner Guitar —
Week 1") group the path by calendar week. Review rejected time-box framing outright: a
student who falls behind a weekly schedule loses motivation, which is the exact failure the
alpha exists to prevent. Progress should read by competency, not by date.

**"Sectioned content" must not couple the path to the knowledge graph.** MotifPath already
has a taxonomy layer (`TaxonomyNode`, `TaxonomyEdge`) whose `part_of` edges express
hierarchical decomposition of subjects into child subjects. It is tempting to derive path
sections from that hierarchy. Doing so would make the student path depend on content
classification (PB-8i) being complete, and would bind a student-facing read path to an
evolving, human-in-the-loop classification graph. The product decision is that these two
concerns stay independent.

**The relationship between a node and its challenge was never decided.** Challenges are a
separate relationship (`GET /content-nodes/{id}/challenges`), and PB-8j routes practice as a
child screen. Whether the challenge is a *sibling* of the lesson or *part of* the node
produces different navigation, different completion semantics, and different screen budgets
for S6.

Alternatives considered:

- **Keep the challenge as a peer screen and solve S6 with layout alone.** Rejected: leaves
  three co-equal demands on S6 and does not resolve what "node complete" means when a node
  has both content and a challenge.
- **Derive path sections from the taxonomy `part_of` hierarchy.** Rejected: creates the
  path-to-graph dependency the product decision forbids, and blocks the alpha on PB-8i.
- **Ship the alpha with a flat, unsectioned path.** Rejected: a run of 12–15 lessons with no
  grouping reads as a wall to a learner who has dropped out before; the emotional payoff of
  finishing a named part is part of what the alpha is testing.
- **Make practice a modal on S6 rather than a route.** Rejected: loses deep-linking and
  browser-back semantics PB-8j deliberately preserves.

## Decision

**MotifPath will treat the challenge as part of its path node, and will model the student
path as a self-contained sequence of steps that the path itself groups into named sections.**

1. **A path node bundles content and challenge.** The unit the student opens (S6) owns its
   content — video or article, inline media, and timed complementary resources — and its
   challenge, if any. The challenge is the node's practice step, not a peer of the lesson.
   S7 remains a distinct route (`/path/nodes/:nodeId/practice`) for focus, deep-linking, and
   browser-back correctness, but it is entered from within S6 and returns there on finish. A
   node with no challenge completes from S6 alone.

2. **The student path groups its own steps into sections.** A path step carries an optional
   section label, set by the teacher while authoring the path. The path view groups
   consecutive steps that share a label under that heading. Sections are ordered,
   competency-named, and never named for a time period. A path with no labels renders as a
   single ungrouped list. `current_position` and per-item status semantics are unchanged;
   section status is derived from its steps' status, consistent with ADR-011.

3. **The student path is self-contained.** It depends on no other MotifPath subsystem to
   render. In particular it has no dependency on the taxonomy / knowledge graph or on
   content classification. Any future "derive sections from the knowledge graph" capability
   is a separate, additive decision and a separate backlog item.

4. **S6 is a dynamic video layout.** By default the video fills the frame. When playback
   reaches a timed cue, the video shrinks and the cue's content (a note, a resource) takes
   the space it gave up — beside the video in landscape (the reference case), below it in
   portrait. The content is visually continuous with the video frame — it reads as part of
   the lesson, not an overlay and not a separate panel with its own chrome (no header
   label). When the cue passes, the video reclaims the full frame. Playback never pauses. A
   cue carries a timestamp and its resource — no per-cue focus mode, no picture-in-picture.
   The node's practice step (or "mark complete") appears when the video ends. Timed content
   is authored against the video timeline (see PB-8i).

5. **Time-box language leaves the product.** Fixtures and examples that imply a schedule are
   renamed to competency names. No student-facing surface refers to weeks, days, or due
   dates.

This decision also revises PB-8j page anatomy. The "single column, mobile-first, no
multi-column" rule holds for S0–S5 and S8. **S6 is a dynamic video layout** — video fills
the frame, and shares it with timed content only while a cue is active (content beside the
video in landscape, below it in portrait). **S7 is responsive** — a single column in
portrait, prompt and answer input side by side in landscape. There is no forced rotation,
and S7 stays within the app shell (the header remains).

## Rationale

Bundling the challenge into the node resolves the S6 space contest by demoting the challenge
from "co-equal screen" to "the node's next step": S6's layout is content-first and the
challenge is a single forward affordance at the end of the flow. It also gives node
completion one meaning — content plus challenge, if any — which the event-derived model
(ADR-011) already expresses through `lesson.*` and `exercise.*` events without new
vocabulary.

Sectioning the path *from within the path* — rather than from the knowledge graph — gets the
motivational benefit ("you finished Fretting-hand fundamentals") at the cost of one optional
field, while keeping the student path a simple, independently deployable read model. The
teacher already curates the path node by node in a concierge conversation; labelling a
handful of section breaks is a marginal authoring cost. Binding the path to the taxonomy
instead would trade that one field for a hard dependency on an unfinished classification
pipeline and an evolving graph, for a benefit the alpha has no evidence it needs yet.

An optional label with client-side grouping of consecutive steps is deliberately the
smallest possible mechanism: it adds no endpoint, changes no status or positioning logic,
and degrades cleanly to a flat list. If sections later need richer structure — nesting,
teacher-authored descriptions, graph derivation — that is an additive change from here, not
a rework.

Keeping S7 a route rather than a modal preserves the two properties PB-8j committed to:
browser-back does the same thing as the in-page back affordance, and any screen can be
linked directly. Keeping S7 inside the app shell keeps one navigation model across the whole
student experience; "immersive" is a visual-density decision, not a structural one.

## Consequences

### Positive

- S6 has a clear content-first layout budget; the video gets the room the alpha needs it to
  have.
- Node completion has one definition, derivable from events that already exist.
- Students track progress by competency; the product carries no schedule pressure.
- The student path stays a self-contained read model with no cross-subsystem dependency — it
  can ship and evolve on its own.
- The path-sections mechanism is one optional field and degrades to a flat list.

### Negative / Trade-offs

- `GET /students/me/path` and the learning-path authoring contract both change: a path step
  gains an optional section label. This is additive but still a spec change that must be
  re-approved, with revised `learning-paths.feature` and `student-path-view.feature`
  scenarios, before implementation, plus a web-client regeneration.
- Section boundaries are teacher-authored, so an inconsistent or missing labelling produces
  an odd-looking path; authoring guidance must call this out.
- "Section" is a new student-facing term that must stay distinct from "path", "step", and
  "node" to avoid vocabulary drift.
- The timed-resource cue is a new content-authoring concept (timestamp + resource + render
  style) with no schema yet; it must be specified before PB-8e can build S6, and it belongs
  to the content-authoring flow (PB-8i).
- S6's dynamic video/content split and S7's responsive two-region landscape layout are more
  layout work than a fixed column, and need a real device/orientation test pass that the
  other screens do not.

### Neutral

- S7's route and event emissions are unchanged; only its framing ("the node's challenge")
  and its visual density move.
- `GET /content-nodes/{id}/challenges` still exists for authoring; only the student path
  view's treatment of the challenge changes.
- The taxonomy / knowledge graph is untouched by this decision.

## Related ADRs

- **ADR-011** — Minimal Aggregation Worker for MVP node-completion state. Section status
  derives from node status the same way node status derives from events.
- **ADR-006** — Kafka topology. Unchanged; the completion events this decision relies on
  already flow through the single topic.

## Follow-up work (not part of this ADR)

- Revise `openapi/core-domain-service.yaml` and `openapi/components/schemas/` for the
  optional path-step section label — separate spec PR, PO-approved, with revised
  `learning-paths.feature` and `student-path-view.feature`.
- Specify the timed-resource cue (timestamp, resource reference, render style) in
  the content spec before PB-8e; it is authored as part of the video (see PB-8i).
- Rename time-box fixtures ("week-1-path", "Beginner Guitar — Week 1") across
  `features/learning-paths/`.
- New backlog item: "derive path sections from the knowledge graph" — deferred, additive,
  to be picked up only if alpha evidence shows teacher-authored sections are insufficient,
  and never in a way that makes the student path depend on classification.
- PB-8j design-doc revision for the S5 / S6 / S7 consequences (companion to this ADR).

---

*This ADR was decided on 2026-09-03. To revise, create a new ADR with Status: Supersedes ADR-015.*
