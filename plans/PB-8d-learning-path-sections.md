# Plan: Learning Path Sections — Persist and Render `section_label`

**Task:** PB-8d
**Date:** 2026-09-05
**Author:** Gilson
**Status:** Draft

---

## Goal

Carry the optional `section_label` field (added to the learning-path contract in
motifpath-specs#24) through the Core Domain Service and into the student's path view in
motifpath-web, so consecutive path items sharing a label render as a named section — and a
path with no labels keeps rendering exactly as it does today. Implements ADR-015 decision #2
and moves backlog item PB-8d (Learning path view + progress & unlock) forward.

## Scope

**In scope:**
- `motifpath-core`: persist `section_label` on path items, return it from `createLearningPath`,
  `getLearningPath`, and `getMyPath`
- `motifpath-web`: regenerate API types; group consecutive same-label `StudentPathItem`s into
  named sections in the student path view (`PathView`, per PB-8c); render unlabeled items as
  today's flat list
- godog step definitions for the three new Gherkin scenarios in
  `features/learning-paths/learning-paths.feature` and
  `features/learning-paths/student-path-view.feature`

**Out of scope:**
- Any teacher-facing UI for authoring paths or setting section labels. No such UI exists in
  `motifpath-web` yet — path creation for the alpha is API-only (concierge-driven, consistent
  with PB-8c's out-of-band intake decision). Building that UI is a separate, later item.
- Deriving sections from the taxonomy/knowledge graph — explicitly deferred by ADR-015 decision
  #3 and tracked as its own backlog item ("Derive path sections from the knowledge graph").
- Any change to `current_position` or item status computation — ADR-015 and motifpath-specs#24
  both keep this unchanged; sections are a display grouping only.

## Prerequisites

- [x] ADR-015 Accepted (motifpath-specs#23)
- [x] `section_label` contract merged (motifpath-specs#24) — `CreateLearningPathRequest`,
      `LearningPathItem`, `StudentPathItem` all carry the optional field
- [x] `PathView` component exists in `motifpath-web` (built for PB-8c) as the integration point
      for Phase 3

---

## Implementation Steps

### Phase 1 — Spec (motifpath-specs)

**Status: done.** `section_label` added to the OpenAPI schema and Gherkin scenarios merged in
PR #24 (`spec/PB-8j/section-label-contract`). No further spec work needed to start Phase 2.

---

### Phase 2 — Backend (motifpath-core)

**Branch:** `feat/PB-8d/learning-path-section-label`

- [ ] Step 1: Add a nullable `section_label` string field to the learning-path-item ent schema;
      generate the Atlas migration per ADR-010's CLI workflow
- [ ] Step 2: Run `oapi-codegen` to regenerate Go request/response types from the updated spec
- [ ] Step 3: Update the `createLearningPath` handler / application-layer service to accept and
      persist `section_label` per item (omitted → stored as null)
- [ ] Step 4: Update `getLearningPath` and `getMyPath` response mapping to include
      `section_label` per item, null-safe when absent
- [ ] Step 5: Table-driven tests: create with all items labeled, create with no items labeled,
      create with a mix (some labeled, some not), read-back round-trips the label exactly
- [ ] Step 6: godog step definitions for the three new scenarios (one in
      `learning-paths.feature`, two in `student-path-view.feature`)
- [ ] Step 7: testcontainers integration test confirming `section_label` persists across a
      real Postgres round-trip, including the null case

**Coverage gate:** 80% on `internal/application/` — CI fails below this.

**Definition of Ready check:**
- [x] OpenAPI endpoint(s) already defined (no new endpoint — existing three reused)
- [x] Gherkin: happy path + label-absent case + label-present case, already merged in #24
- [x] ADR exists (ADR-015)

---

### Phase 3 — Frontend (motifpath-web)

**Branch:** `feat/PB-8d/learning-path-section-label`

- [ ] Step 1: Run `openapi-typescript` to regenerate API client types, picking up
      `section_label` on `StudentPathItem`
- [ ] Step 2: Add a pure grouping function — given the flat `items` array from
      `GET /students/me/path`, partition it into `{ label: string | null, items: StudentPathItem[] }[]`
      by collapsing consecutive items that share a non-null label; items with no label, or a
      label different from their neighbor, each form their own single-item group with `label: null`
- [ ] Step 3: Unit test the grouping function directly: no labels → one ungrouped run; all one
      label → one group; alternating labels → multiple groups; a label reused non-consecutively
      (e.g. items 1 and 3 share a label but item 2 doesn't) → does **not** merge across the gap
- [ ] Step 4: Update `PathView` to render a section heading above each labeled group and no
      heading for ungrouped runs, preserving existing per-item status/position rendering
      unchanged
- [ ] Step 5: Component test confirming an unlabeled path renders identically to today (no
      visual regression) and a labeled path renders section headings in the right place

---

### Phase 4 — Infrastructure (motifpath-infra)

Not applicable — additive nullable column, no new service, no new infra.

---

## Rollback Plan

The migration adds a single nullable column with no default-value backfill and no constraint
changes — reversible with a straight `DROP COLUMN` per ADR-005's migration guard if Phase 2
needs to be rolled back. Phase 3 is a pure frontend rendering change behind existing endpoints;
reverting is a standard redeploy of the previous `motifpath-web` build per ADR-004. Because the
field is optional and additive, Phase 2 and Phase 3 can also ship independently — an unlabeled
API response degrades cleanly to today's flat list in a not-yet-updated frontend, and a
frontend build with the grouping logic degrades cleanly against an old backend that never
returns `section_label` (treated as absent).

## Validation

- [ ] `POST /learning-paths` persists `section_label` per item; `GET /learning-paths/{id}` and
      `GET /students/me/path` both return it unchanged from what was submitted
- [ ] All three new Gherkin scenarios pass against the real service via godog
- [ ] All pre-existing learning-path and student-path-view scenarios still pass unchanged
      (regression check — unlabeled paths are unaffected)
- [ ] `internal/application/` coverage stays ≥ 80%
- [ ] In `motifpath-web`, a manual check of an unlabeled path (e.g. `week-1-path`) renders
      identically to its current appearance, and a labeled test path renders visible section
      headings grouping the right items

## Open Questions

| Question | Owner | Resolution |
|---|---|---|
| Exact ent field/column naming convention for `section_label` (snake_case column vs Go field name) | motifpath-core implementer | — |
| Whether `PathView`'s existing status/locking rendering has any layout assumption that a section heading would disrupt (needs a look at the current component before Step 4) | motifpath-web implementer | — |

---

## Related

- **ADR:** [ADR-015 — Challenge belongs to the path node; the student path is a self-contained sectioned sequence](../adrs/ADR-015-node-challenge-and-path-sections.md)
- **Spec files:** `openapi/core-domain-service.yaml`, `features/learning-paths/learning-paths.feature`, `features/learning-paths/student-path-view.feature`
- **Backlog item:** PB-8d (Learning path view + progress & unlock)
- **Related plan:** `plans/PB-8c-student-onboarding-auth.md` (source of the `PathView` component this plan extends)
