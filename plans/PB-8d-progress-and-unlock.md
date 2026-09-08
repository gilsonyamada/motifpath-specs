# Plan: Learning Path Progress & Unlock — Render Step State in `PathView`

**Task:** PB-8d
**Date:** 2026-09-07
**Author:** Gilson
**Status:** Ready — open questions resolved 2026-09-07; blocked only on motifpath-web#7 merging first

---

## Goal

Render each student path step's progress state — completed, current, or locked — in `PathView`
with a clear visual treatment and an affordance to open the current step, so a student can see
how far they've come and what to do next. Completes the "progress & unlock" half of backlog
item PB-8d; the section-label half ships separately (`plans/PB-8d-learning-path-sections.md`,
motifpath-web#7).

## Scope

**In scope (`motifpath-web` only):**
- A new `PathStep.vue` component (`features/student/components/`) — one path step: ordinal,
  status marker, title, status label, and an optional open/review affordance. Replaces the raw
  `{{ step.status }}` text and inline `<li>` that motifpath-web#7 puts in `PathView`.
- Status treatment per `design/PB-8j-student-alpha-ux-foundation.md` §"S5 — My Path": a
  completed marker, an emphasised current step, a dimmed non-interactive locked step
- Derive the current step from `StudentPathView.current_position` as the single source of truth,
  not by re-scanning per-item `status`
- An affordance on the current step **and** on completed steps (a completed lesson is
  revisitable): `Open` for the current step, `Review` for a completed one. Locked steps have no
  affordance. It links to the `node` named route (below).
- A minimal `NodeView.vue` + `node` route (`/path/nodes/:nodeId`) as a placeholder seam — a
  holding screen ("This lesson isn't available yet"). PB-8e replaces its body with the real S6.
- A pure per-step view helper + a progress helper (`{ completed, total }`) in
  `features/student/utils/`
- A single quiet **overall progress line** at the path head — "N of M steps complete" — kept
  alongside #7's per-section step counts. Plain, present tense, competency-framed; no time-box
  language, no progress bar (see Design Decisions).
- Add the `motif-success` **and** `motif-danger` tokens to `tailwind.config.ts` — the PB-8j
  §"Semantic token roles" action item; `motif-success` is used here, `motif-danger` added in the
  same commit for completeness
- Component tests for each status rendering, the open/review affordances, locked
  non-interactivity, and the progress line

**Out of scope:**
- The real S6 node / lesson screen (dynamic video layout, cues, mark-complete) — PB-8e. This
  plan ships only the `NodeView` placeholder and the route.
- Any change to how `status` or `current_position` are computed — that is backend, already
  implemented per ADR-011 and shipped in motifpath-core#9, and stays unchanged.
- Section grouping — delivered by motifpath-web#7, a prerequisite here.
- Marking a step complete or emitting `lesson.*` events — PB-8e.
- The PB-8j standard-state components (`StateLoading`, `StateEmpty`, `StateError`,
  `StateLocked`) — `PathView` keeps its current inline loading / no-path / `ErrorRetryNotice`
  handling. Extracting those is a separate PB-8j foundation-cleanup item. `StateLocked` in
  particular is a whole-screen state for S6 and belongs to PB-8e.
- A shared primary-action button component — the affordance is a styled `RouterLink` inside
  `PathStep`; a design-system button is a later decision.
- Teacher-facing path authoring.
- Any new endpoint or persisted state — this reads the existing `GET /students/me/path`.

## Prerequisites

- [ ] motifpath-web#7 merged to `dev` — this plan edits the step `<li>` and `groupPathSections`
      output that PR introduces
- [x] `StudentPathView.current_position` and `StudentPathItem.status` in the OpenAPI contract
      (`openapi/core-domain-service.yaml`) — already shipped
- [x] `features/learning-paths/student-path-view.feature` covers backend status computation —
      merged and godog-implemented (motifpath-core#9)
- [x] ADR-011 (aggregation worker derives node-completion state) and ADR-015 (self-contained
      sectioned path) — accepted
- [ ] ADR-017 (student path assignment lifecycle) — Proposed (specs PR #33). Does not block
      Phase 3 coding, but its "multi-path readiness" section governs the `PathView` /
      `PathContent` split below; land it first or in parallel.
- [x] `design/PB-8j-student-alpha-ux-foundation.md` §"S5 — My Path", §"Standard states",
      §"Semantic token roles" — the design source of truth for this screen

---

## Component Inventory

What this slice adds to `motifpath-web`, and what it deliberately does not.

| Item | Kind | Location | Notes |
|---|---|---|---|
| `PathView.vue` | route component | `features/student/views/` | Owns the fetch (`useStudentPath`) and the loading / error / no-path states. Renders `<PathContent>` on success. Deliberately thin — see Multi-path readiness. |
| `PathContent.vue` | component | `features/student/components/` | Props: one `StudentPathView`. Renders the progress line + the sections (`groupPathSections`) + a `PathStep` per item. Has **no** knowledge of fetching or of how many paths a student has. |
| `PathStep.vue` | component | `features/student/components/` | One step: ordinal · status marker (✓ / ▸ / 🔒) · title · status label · optional `Open`/`Review` affordance. All per-step branching lives here. Unit of the component tests. |
| `NodeView.vue` | view | `features/student/views/` | Placeholder holding screen for the `node` route. ~20 lines: reads `:nodeId`, renders "This lesson isn't available yet" + a "‹ Back to path" link. PB-8e replaces the body. |
| `node` route | router | `src/router/index.ts` | `/path/nodes/:nodeId`, name `node`, `meta.requiresAuth`, nested under `/path`. **Node-keyed, path-agnostic** — not nested under an assignment id (see Multi-path readiness). |
| `pathProgress` / `stepView` | pure helper | `features/student/utils/` | Alongside `groupPathSections`. `stepView` → per-step `{ position, title, status, isCurrent }`; `pathProgress` → `{ completed, total }`. Take a `StudentPathView`, so already per-path. |
| overall progress line | inline markup | `PathContent.vue` | One text node — not worth a component. Extract to `PathProgressSummary.vue` only if it later grows a bar or per-section breakdown. |
| `motif-success`, `motif-danger` | tokens | `tailwind.config.ts` | Placeholder hex + the existing `PLACEHOLDER` comment. |

**Explicitly deferred (not this slice):** `StateLoading` / `StateEmpty` / `StateError` /
`StateLocked` shared components and a shared primary-action button — a separate PB-8j
foundation-cleanup item. `PathView` keeps its inline state handling for now.

### Multi-path readiness (per ADR-017)

ADR-017 keeps the MVP single-active-path but requires the data model *and* the frontend
structure to not preclude concurrent multi-path later. This slice's contribution to that,
at zero extra cost:

- **`PathView` (fetch + states) is split from `PathContent` (render a given path).** A future
  multi-path view is a path picker feeding the same `PathContent` — not a rewrite.
- **Components key off `assignment_id`** (carried in `StudentPathView`), never "the student's
  path" as a singleton. `PathContent` and `PathStep` receive their data as props.
- **The `node` route stays node-keyed** (`/path/nodes/:nodeId`) and path-agnostic, so it needs
  no change when a student has more than one active path.
- **`useStudentPath` stays singular** ("the active assignment") — a future `useStudentPaths`
  (list) is an addition, not a replacement. No speculative plural code now.

Not in scope: the plural read endpoint, a picker, or any multi-active behaviour — those wait
for the dedicated multi-path item.

---

## Design Decisions

- **Overall progress line, not just per-section counts.** The S5 wireframe shows only
  per-section "N steps" counts. This slice adds one quiet line at the path head —
  "N of M steps complete" — because "how far am I overall" is the core signal of a
  progress-&-unlock screen and per-section counts only answer it locally. It stays
  competency-framed (steps, never time) and un-gamified (no bar, no XP, no streak) per the
  PB-8j copy voice. **This is a deliberate divergence from the wireframe** — fold back into the
  PB-8j canvas.
- **No progress bar on S5.** A fill-only bar (as on S7 practice) gives a vaguer signal and more
  visual weight; a concrete count reads as reassuring on a whole-journey screen. S7's bar is
  deliberately count-less for a short, pressured run — the opposite context.
- **Completed steps are revisitable.** The affordance shows for the current step (`Open`) and
  for completed steps (`Review`), not just the current one — a student can re-watch a finished
  lesson. Locked steps have no affordance.

---

## Implementation Steps

### Phase 1 — Spec (motifpath-specs)

**No spec change required.** The contract (`current_position`, the `status` enum) and the
behaviour spec (`student-path-view.feature`) already cover everything the backend must do, and
both are implemented. Frontend rendering is not expressed in Gherkin — there is no E2E layer at
MVP (PB-8j).

**Definition of Ready check:**
- [x] OpenAPI: `getStudentPath` returns `current_position` + per-item `status` — defined
- [x] Gherkin: happy path + edge cases (first node done, mid-node in progress, all done) +
      failure (no assignment) for status computation — merged, godog-implemented
- [x] ADR exists — ADR-011 (status derivation), ADR-015 (self-contained path)

**Non-blocking follow-up (not owned by this plan):** resolving the `motif-success` /
`motif-danger` hex in `motifpath-brand/colors.json` is already tracked in PB-8j §"Semantic
token roles" action items — brand's call, not a blocker for a placeholder token.

---

### Phase 2 — Backend (motifpath-core)

**No backend change required.** `status` and `current_position` are already derived and shipped
(motifpath-core#9, ADR-011).

- [ ] Step 1 (verification only): against the `process-compose` stack, seed a multi-step
      assignment with the first node completed and confirm `GET /students/me/path` returns
      `current_position` pointing at the first not-completed item, that item's `status` as
      `not_started` or `in_progress`, earlier items `completed`, and later items `locked`.
      Matches the scenarios in `student-path-view.feature`.

---

### Phase 3 — Frontend (motifpath-web)

**Branch:** `feat/PB-8d/path-progress-and-unlock` (from `dev`, after motifpath-web#7 merges)

- [ ] Step 1 — `chore(student)`, separate commit: add `motif-success` and `motif-danger` to
      `tailwind.config.ts`, each with a placeholder hex and the same `PLACEHOLDER` comment the
      other `motif-*` tokens carry, plus a note that the real values are a `motifpath-brand`
      decision (PB-8j §"Semantic token roles").
- [ ] Step 2 — write failing unit tests (TDD) for the pure helper in
      `src/features/student/utils/`: given a `StudentPathView`, produce per-step view data
      `{ position, title, status, isCurrent: position === current_position }` and a summary
      `{ completed, total }`. Cases: current is the first step; current is mid-path with earlier
      steps completed and later steps locked; path fully completed (`current_position === total`,
      nothing locked); single-step path.
- [ ] Step 3 — implement the helper to make Step 2 pass.
- [ ] Step 4 — write failing component tests (TDD) for `PathStep.vue`:
  - `completed` → completed marker, label, a **`Review`** affordance to the `node` route
  - current (`isCurrent`) → emphasised, an **`Open`** affordance to the `node` route
  - `locked` → dimmed (`motif-ink/40`), lock marker, `aria-disabled`, **no** affordance
  - the affordance targets the `node` named route with the step's `content_node_id`
- [ ] Step 5 — implement `PathStep.vue` to make Step 4 pass.
- [ ] Step 6 — add the `node` route (`/path/nodes/:nodeId`, name `node`, `meta.requiresAuth`,
      nested under `/path`) + a minimal `NodeView.vue` holding screen; a router test asserts the
      route resolves and requires auth.
- [ ] Step 7 — write failing component tests (TDD) for `PathContent.vue` (props: one
      `StudentPathView`):
  - each section maps its items to `PathStep` (delegation, not re-implementation)
  - the overall progress line reflects `pathProgress` `completed` / `total`
  - a fully completed path: every step `Review`, no `Open`, progress line reads "M of M"
  - regression: an unlabelled path and a labelled path (from #7) still render their sections
- [ ] Step 8 — implement `PathContent.vue` to make Step 7 pass: move the section/step render
      out of `PathView` into `PathContent`, add the progress line via `pathProgress` — "N of M
      steps complete", plain, present tense, no "week" / "on track" / due dates. `PathContent`
      does no fetching and takes the view as a prop (ADR-017 multi-path readiness).
- [ ] Step 9 — reduce `PathView` to the fetch + loading/error/no-path states + `<PathContent>`
      on success; its existing state tests stay green.
- [ ] Step 10 — `npm run test`, `npm run typecheck`, `npm run lint`, `npm run build` all clean;
      manual check against the `process-compose` stack with a seeded 3-step assignment (node 1
      completed): step 1 `Review`, step 2 current + `Open` → `NodeView` placeholder, step 3
      locked; progress line reads "1 of 3 steps complete".

**Commit discipline:** the token change (Step 1) is its own `chore` commit, separate from
component logic (git skill — config/generated changes split from business logic).

---

### Phase 4 — Infrastructure (motifpath-infra)

Not applicable — pure frontend rendering change, no new service, no infra.

---

## Rollback Plan

Pure frontend change behind the existing `GET /students/me/path` endpoint. Reverting is a
standard redeploy of the previous `motifpath-web` build per ADR-004. The new tokens and the
`node` placeholder route are additive and inert if unreferenced. No migration, no backend
change, no infra change — nothing that cannot be rolled back by redeploy.

## Validation

- [ ] `PathStep` tests assert: completed → completed marker + `Review`; current → emphasis +
      `Open`; locked → dimmed, `aria-disabled`, no affordance
- [ ] The affordance navigates to the `node` route with the step's `content_node_id`; the
      route requires auth
- [ ] The overall progress line reflects `current_position` / item count and contains no
      time-box language (asserted in a test, not just by eye)
- [ ] A fully completed path renders every step with `Review`, no `Open`, progress line "M of M"
- [ ] `npm run test` count grows by the new cases; `typecheck`, `lint`, `build` all clean
- [ ] Manual against `process-compose`: a seeded 3-step assignment with node 1 completed shows
      step 1 `Review`, step 2 current + `Open` → `NodeView` placeholder, step 3 locked; progress
      line "1 of 3 steps complete"
- [ ] Regression: unlabelled and labelled paths from motifpath-web#7 still render their sections
      unchanged

---

## Open Questions

### Resolved 2026-09-07

| Question | Resolution |
|---|---|
| Open affordance destination while S6 doesn't exist | **Option B** — PB-8d declares the `node` named route + a minimal `NodeView` placeholder; the affordance links to it. PB-8e replaces the view body. |
| Global progress line vs. per-section counts only | Add a single quiet overall line ("N of M steps complete") **in addition to** #7's per-section counts. Deliberate divergence from the S5 wireframe — fold back into the PB-8j canvas. No progress bar. |
| Do completed steps stay openable? | **Yes.** The affordance shows for completed steps as `Review` and for the current step as `Open`. Locked steps have none. |
| Add `motif-danger` now or defer? | **Add now**, in the same `tailwind.config.ts` commit as `motif-success`. |

### Still open

| Question | Owner | Resolution |
|---|---|---|
| `motif-success` / `motif-danger` hex values | `motifpath-brand` | Placeholder hex ships with this slice; real values tracked in PB-8j §"Semantic token roles" action items |

---

## Related

- **ADR:** [ADR-011 — Minimal Aggregation Worker for MVP node-completion state](../adrs/ADR-011-minimal-aggregation-worker.md); [ADR-015 — Challenge belongs to the path node; the student path is a self-contained sectioned sequence](../adrs/ADR-015-node-challenge-and-path-sections.md); [ADR-017 — Student path assignment lifecycle](../adrs/ADR-017-student-path-assignment-lifecycle.md) (governs the `PathView` / `PathContent` split)
- **Design:** `design/PB-8j-student-alpha-ux-foundation.md` §"S5 — My Path", §"Standard states", §"Semantic token roles"
- **Spec files:** `openapi/core-domain-service.yaml` (`getStudentPath`), `features/learning-paths/student-path-view.feature`
- **Backlog item:** PB-8d (Learning path view + progress & unlock)
- **Predecessor slice:** `plans/PB-8d-learning-path-sections.md` (Phases 1–3, section labels) + motifpath-web#7 (the `PathView` step `<li>` this plan extends)
- **Successor:** PB-8e — S6 node / lesson screen, consumes the `node` route seam
- **Related workstream:** ADR-017 downstream — `motifpath-core` assignment-lifecycle migration + the `path-assignments.feature` / `getMyPath` rewording (its own plan; not part of this slice)
