# Plan: Learning Path Progress & Unlock — Render Step State in `PathView`

**Task:** PB-8d
**Date:** 2026-09-07
**Author:** Gilson
**Status:** Draft

---

## Goal

Render each student path step's progress state — completed, current, or locked — in `PathView`
with a clear visual treatment and an affordance to open the current step, so a student can see
how far they've come and what to do next. Completes the "progress & unlock" half of backlog
item PB-8d; the section-label half ships separately (`plans/PB-8d-learning-path-sections.md`,
motifpath-web#7).

## Scope

**In scope (`motifpath-web` only):**
- Replace the raw `{{ step.status }}` text that motifpath-web#7 puts in each step `<li>` with a
  status treatment: a completed marker, an emphasised current step, and a dimmed
  non-interactive locked step — per `design/PB-8j-student-alpha-ux-foundation.md` §"S5 — My Path"
- Derive the current step from `StudentPathView.current_position` as the single source of truth,
  not by re-scanning per-item `status`
- An **Open** affordance on the current step (destination — see Open Questions)
- A pure per-step view helper + a progress summary helper (`{ completed, total }`)
- A progress summary line, in the PB-8j copy voice — no time-box language
- Add the `motif-success` token to `tailwind.config.ts` (the PB-8j §"Semantic token roles"
  action item; this is its first consumer)
- Component tests for each status rendering, the current-step affordance, locked
  non-interactivity, and the progress summary

**Out of scope:**
- The node / lesson screen S6 (`/path/nodes/:nodeId`) — PB-8e. This plan may add only a
  placeholder route + view as a seam (see Open Questions).
- Any change to how `status` or `current_position` are computed — that is backend, already
  implemented per ADR-011 and shipped in motifpath-core#9, and stays unchanged.
- Section grouping — delivered by motifpath-web#7, a prerequisite here.
- Marking a step complete or emitting `lesson.*` events — PB-8e.
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
- [x] `design/PB-8j-student-alpha-ux-foundation.md` §"S5 — My Path", §"Standard states",
      §"Semantic token roles" — the design source of truth for this screen

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

- [ ] Step 1 — `chore(student)`, separate commit: add `motif-success` to `tailwind.config.ts`
      with a placeholder hex and the same `PLACEHOLDER` comment the other `motif-*` tokens
      carry, plus a note that the real value is a `motifpath-brand` decision. Add `motif-danger`
      only if design wants both now (see Open Questions).
- [ ] Step 2 — write failing unit tests (TDD) for a pure helper in
      `src/features/student/utils/`: given a `StudentPathView`, produce per-step view data
      `{ position, title, status, isCurrent: position === current_position }` and a summary
      `{ completed, total }`. Cases: current is the first step; current is mid-path with earlier
      steps completed and later steps locked; path fully completed (`current_position === total`,
      nothing locked); single-step path.
- [ ] Step 3 — implement the helper to make Step 2 pass.
- [ ] Step 4 — write failing component tests (TDD) for `PathView`:
  - a `completed` step renders the completed marker and label, no Open affordance
  - the current step renders emphasised and shows the Open affordance
  - a `locked` step renders dimmed (`motif-ink/40`), has a lock marker, and has **no** Open
    affordance and `aria-disabled`
  - the progress summary line reflects `completed` / `total`
  - a fully completed path renders every step completed with no Open affordance anywhere
  - an unlabelled path and a labelled path (from #7) both still render their sections correctly
    — no regression
- [ ] Step 5 — update `PathView` to make Step 4 pass: replace
      `<span data-test="step-status">{{ step.status }}</span>` with the status treatment above,
      keeping the ordinal + title from #7 unchanged. `data-test` hooks: keep `step-status`
      (now carrying a stable status value), add `step-open`.
- [ ] Step 6 — add the progress summary line at the path head, in the PB-8j copy voice
      ("2 of 5 steps done" — plain, present tense, no "week" / "on track" / due dates). No
      progress bar on S5 — the S5 wireframe shows per-section step counts and per-step markers,
      not a global bar (confirm placement against the wireframe: one quiet line under the path
      title, or the per-section "N steps" counts already in #7).
- [ ] Step 7 — `npm run test`, `npm run typecheck`, `npm run lint`, `npm run build` all clean;
      manual check against the `process-compose` stack with a seeded 3-step assignment (node 1
      completed): step 1 completed, step 2 current + Open, step 3 locked.

**Commit discipline:** the token change (Step 1) is its own `chore` commit, separate from the
component logic (git skill — generated/config changes split from business logic).

---

### Phase 4 — Infrastructure (motifpath-infra)

Not applicable — pure frontend rendering change, no new service, no infra.

---

## Rollback Plan

Pure frontend change behind the existing `GET /students/me/path` endpoint. Reverting is a
standard redeploy of the previous `motifpath-web` build per ADR-004. The `motif-success` token
addition is additive and inert if unreferenced. No migration, no backend change, no infra
change — nothing that cannot be rolled back by redeploy.

## Validation

- [ ] Component tests assert: completed step → completed marker, no Open; current step →
      emphasis + Open affordance; locked step → dimmed, `aria-disabled`, no Open
- [ ] The progress summary reflects `current_position` / item count and contains no time-box
      language (asserted in a test, not just by eye)
- [ ] A fully completed path renders every step completed and shows no Open affordance
- [ ] `npm run test` count grows by the new cases; `typecheck`, `lint`, `build` all clean
- [ ] Manual against `process-compose`: a seeded 3-step assignment with node 1 completed shows
      step 1 completed, step 2 current + Open, step 3 locked
- [ ] Regression: unlabelled and labelled paths from motifpath-web#7 still render their sections
      unchanged

---

## Open Questions

| Question | Owner | Resolution |
|---|---|---|
| **Open affordance destination.** S6 (`/path/nodes/:nodeId`, route `node`) is PB-8e and does not exist yet. Options: **A** — current step gets emphasis + marker but no Open button until PB-8e; **B** — PB-8d declares the `node` named route + a minimal placeholder `NodeView` and Open links to it; **C** — Open is a disabled button with explanatory text. Recommendation: **B** — delivers a real "click your next step" end to end and gives PB-8e a defined integration seam, at ~20 lines of placeholder. | Gilson | — |
| Global progress line vs. the per-section "N steps" counts already rendered by #7 — the S5 wireframe shows only the per-section counts and per-step markers, no global bar | Gilson / design | — |
| Does a completed step stay openable (revisit the lesson)? The S5 wireframe shows no affordance on completed steps | Gilson | — |
| Add `motif-danger` alongside `motif-success` now, or defer to its first real consumer | motifpath-web implementer | — |

---

## Related

- **ADR:** [ADR-011 — Minimal Aggregation Worker for MVP node-completion state](../adrs/ADR-011-minimal-aggregation-worker.md); [ADR-015 — Challenge belongs to the path node; the student path is a self-contained sectioned sequence](../adrs/ADR-015-node-challenge-and-path-sections.md)
- **Design:** `design/PB-8j-student-alpha-ux-foundation.md` §"S5 — My Path", §"Standard states", §"Semantic token roles"
- **Spec files:** `openapi/core-domain-service.yaml` (`getStudentPath`), `features/learning-paths/student-path-view.feature`
- **Backlog item:** PB-8d (Learning path view + progress & unlock)
- **Predecessor slice:** `plans/PB-8d-learning-path-sections.md` (Phases 1–3, section labels) + motifpath-web#7 (the `PathView` step `<li>` this plan extends)
- **Successor:** PB-8e — S6 node / lesson screen, consumes the `node` route seam
