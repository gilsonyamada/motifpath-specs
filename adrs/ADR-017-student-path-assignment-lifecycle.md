# ADR-017: Student Path Assignment Lifecycle — Append-Only History, Single Active for MVP, Multi-Path-Ready

**Status:** Proposed
**Date:** 2026-09-08
**Deciders:** Gilson Yamada (solo engineering at MVP)

---

## Context

The student path assignment model was built single-active. `PathAssignment.student_id` carries a
database `UNIQUE` constraint; `PathAssignmentRepository.ReplaceActive` deletes any existing row
for the student before inserting the new one; and `GET /students/me/path` /
`GetActiveByStudentID` assume exactly one assignment exists. Reassigning a path therefore
destroys the prior assignment record and its identity. `features/learning-paths/path-assignments.feature`
codifies this as "assigning a new path replaces it."

Two forces now push against this model:

1. **A revised product premise.** MotifPath's MVP validation must not depend on external teacher
   supply. The team acts as the concierge — building paths and producing the basic content —
   and the platform has to demonstrate standalone value first. Retention, in particular, cannot
   be assumed to come from a teacher relationship; it has to come from the product. This revises
   the earlier "teacher quality is the leverage point — all product decisions trace back to
   teacher outcomes" framing: teacher leverage remains the *scaling* thesis, but is explicitly
   **not a dependency for MVP validation or for retention**. A student who finishes their one
   path with nowhere to go is a retention cliff the product itself must eventually answer.

2. **A student will plausibly need more than one path** — parallel tracks (technique plus
   repertoire), or simply a next path after finishing one. "Paths as courses" — a catalog with
   teacher-mediated multi-enrollment — is a live product direction. It is deferred past the
   alpha but not rejected.

The single-active assumption is baked in at three levels: the schema (`UNIQUE(student_id)`), the
repository (`ReplaceActive` deletes), and the API (singular `getMyPath`). Of these, **only the
`UNIQUE(student_id)` constraint is expensive to reverse** — dropping it later means a migration
on a table that only grows, and every query written against it assumes 1:1. The API is
additively evolvable (a plural read endpoint alongside the singular one); the repository
behaviour is application-layer.

We are not building multi-path now. The decision is narrow: what is the minimum model change
that removes the irreversible cost and keeps the domain honest? Alternatives considered —
(a) leave the model as-is and record "drop the constraint" as a future prerequisite;
(b) drop only the `UNIQUE` constraint and keep delete-on-replace; (c) an append-only lifecycle
with an explicit active/inactive state.

## Decision

MotifPath will change the `PathAssignment` model to an **append-only lifecycle**:

- Remove the `UNIQUE` constraint on `student_id`.
- Add a nullable `deactivated_at` timestamp. An assignment with `deactivated_at IS NULL` is
  *active*; a non-null value marks it as historical.
- Assigning a path no longer deletes the prior row. The assign operation becomes
  deactivate-then-insert: it sets `deactivated_at = now()` on the student's current active
  assignment, if any, and inserts a new active row with a fresh `assignment_id`.
- `GetActiveByStudentID` reads `WHERE student_id = ? AND deactivated_at IS NULL`.
- **The domain invariant "at most one active assignment per student" is retained for the MVP**,
  now enforced in the application layer rather than by a schema constraint. `GET /students/me/path`
  continues to return that single active assignment, unchanged.
- The OpenAPI description of `getMyPath` will note that a multi-path read surface
  (`GET /students/me/paths`) is a planned additive extension, and that clients key off
  `assignment_id` rather than treating "the student's path" as a singleton.

Multi-path proper — allowing more than one concurrent active assignment, plus a catalog and an
enrollment surface — remains out of scope and will be its own decision. It will not require a
further schema migration.

## Rationale

- **Alternative (a) rejected.** Leaving a known-wrong constraint in place trades a small change
  now for a larger, riskier migration later against more data. The premise revision makes
  multi-path likely enough that "later" is a false economy.
- **Alternative (b) rejected.** Dropping the `UNIQUE` constraint while keeping delete-on-replace
  still destroys assignment history and progress identity on every reassignment. Even under a
  strict single-active rule, a concierge moving a student between paths and silently losing the
  prior record is a real data-loss defect, and it forecloses "resume a previous path" without
  yet another model change.
- **Alternative (c) chosen.** `deactivated_at` is the smallest addition that makes the model
  honest: assignments become an auditable history, the active-set query is explicit, and
  relaxing "one active" later is a pure application-layer change — allow multiple rows with
  `deactivated_at IS NULL` — with no migration and no backfill. It also preserves each
  assignment's progress identity, so a future "pick up where you left off" is a read, not a
  reconstruction.
- **The invariant stays in the application layer** because the MVP genuinely wants one active
  path per student — the concierge builds one journey at a time — and expressing that rule in
  code keeps it visible and testable without cementing it in the schema, where it would have to
  be migrated away.
- **Cost accepted:** a two-part migration (drop index, add column), repository and service
  semantics change with attendant test churn, and a `deactivated_at IS NULL` predicate on every
  active-assignment read.

## Consequences

### Positive
- The one expensive-to-reverse constraint is removed now, while the table is small.
- Assignment history is retained — reassignment is non-destructive; audit trails and a "past
  paths" view become possible later.
- Concurrent multi-path later is an application-layer change: no schema migration, no data
  backfill.
- Each assignment's progress state keeps a stable identity across reassignment, enabling
  "resume a previous path."
- Forces the frontend to key off `assignment_id` now — the correct shape regardless of when
  multi-path lands.

### Negative / Trade-offs
- A migration and non-trivial test churn in `motifpath-core` for a change with **no
  user-visible behaviour difference at MVP** — this is pure future-proofing, justified only by
  the cost asymmetry.
- Every active-assignment read now carries a `deactivated_at IS NULL` predicate; omitting it
  silently returns historical rows. Requires a single choke-point repository method and tests
  that assert historical rows are excluded.
- `features/learning-paths/path-assignments.feature` and
  `features/learning-paths/student-path-view.feature` need rewording: "replaces it" becomes
  "deactivates the previous assignment; the previous assignment is retained as history."
- Retaining assignment history indefinitely adds a (small, deferred) storage cost and a privacy
  obligation: a student data-erasure request must sweep inactive assignments too.
- Keeping "one active" in application code means a bug can violate an invariant that a schema
  constraint would have caught; mitigated by the choke-point method and its tests.

### Neutral
- `assignment_id` already changes on every reassignment (previously via delete-and-insert, now
  via deactivate-and-insert) — the contract that reassignment yields a fresh id is unchanged.
- No change to how node-completion state is derived by the Aggregation Worker (ADR-011); that
  state is keyed by student and node, orthogonal to assignment lifecycle. How "resume a
  previous path" interacts with per-node completion state is a question for the future
  multi-path work, not this ADR.
- The revised product premise (point 1 above) needs to be reflected in the Product HQ page and
  the team's working premises; that is done separately from this ADR.

## Related ADRs

- **ADR-015** (Challenge belongs to the path node; the student path is a self-contained
  sectioned sequence) — this ADR extends the *assignment* dimension (how many, what lifecycle)
  without touching a path's internal structure.
- **ADR-011** (Minimal Aggregation Worker for MVP node-completion state) — completion state is
  orthogonal to assignment lifecycle; flagged here as an open interaction for the future
  multi-path work.
- **ADR-005** (Database migration — Atlas + ent, startup guarded by lock) and **ADR-010** (Atlas
  CLI migration workflow) — the two-part migration follows this workflow.

---

*This ADR was decided on 2026-09-08. To revise, create a new ADR with Status: Supersedes ADR-017.*
