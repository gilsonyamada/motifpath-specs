# ADR-017: Student Path as a Copied Instance of a Reusable Template

**Status:** Proposed
**Date:** 2026-09-08
**Deciders:** Gilson Yamada (solo engineering at MVP)

---

## Context

The learning-path model was built for a single active path per student. `LearningPath` +
`LearningPathItem` hold a path definition; `PathAssignment` links one student to one path by
reference, with a `UNIQUE(student_id)` constraint; assigning a new path deletes the old
assignment and resets progress. `GET /students/me/path` returns "the" active assignment. The
student path is already meant to be self-contained (ADR-015) — but today it is self-contained
only by *reference*: every student on a given path shares the same `LearningPathItem` rows.

Two forces make this model wrong, not just limited:

1. **A revised product premise.** MotifPath's MVP validation and student retention must not
   depend on external teacher supply. The team is the concierge — building paths and producing
   the basic content — and the platform must show standalone value first. Retention is a product
   responsibility: a student who finishes their one path with nowhere to go is a cliff the
   product itself has to answer. This revises the earlier "teacher quality is the leverage
   point" framing (teacher leverage remains the *scaling* thesis, not an MVP dependency) and is
   recorded separately in Product HQ.

2. **The path must be individualised per student, and a student needs more than one over time.**
   A generic path — e.g. a beginner path every new student starts from — is a *template*. Each
   student's path is that template **copied** and then personalised by the concierge (steps
   added, removed, reordered; sections relabelled) without touching the template or any other
   student. Students will also hold several paths — parallel tracks now, a next path after
   finishing one — with one being the path they are actively working. "Paths as courses" (a
   catalog with teacher-mediated multi-enrollment) is a live direction, deferred past the alpha.

The database has **no production data**. There is no migration cost and no reason to model
minimally — the model can be designed correctly now.

Alternatives considered: (a) keep the reference model, add a nullable `deactivated_at` to
`PathAssignment` so reassignment is non-destructive (an earlier draft of this ADR) — rejected
because it leaves every student on a path sharing one set of item rows, so per-student
personalisation is impossible; (b) one path table with a `template` boolean discriminator —
rejected because templates and instances have different lifecycles, different editability, and
only instances carry progress; (c) copy the template into a per-student instance — chosen.

## Decision

MotifPath will model a student's path as a **copied, independently-owned instance of a reusable
template.**

**Two definitions:**

- **`LearningPath` / `LearningPathItem` — the template.** A reusable path definition: an
  ordered list of items, each an immutable `content_node_id` plus an optional `section_label`
  (ADR-015). No student, no progress. Authored once; reused across many students.
- **`StudentPath` / `StudentPathItem` — the instance.** Created by copying a template's items
  for one student. Belongs to exactly one student. Independently editable after creation. Fields
  on `StudentPath`: `id`, `student_id`, `source_template_id` (the `LearningPath` it was copied
  from, for provenance), `title` (copied, then editable), `assigned_by`, `assigned_at`,
  `archived_at` (nullable). `StudentPathItem`: `student_path_id`, `position`, `content_node_id`,
  `section_label`.

**`PathAssignment` is removed.** "Assigning a path to a student" *is* "copy the template into a
new `StudentPath`". The assign operation: copy the template's items into a new `StudentPath`,
and point the student's current path at it (see below).

**A student has many `StudentPath`s.** Accessibility is one axis: a `StudentPath` with
`archived_at IS NULL` is *active* and visible to the student; a non-null value hides it (a
concierge/admin action — distinct from "not the one I'm working on right now").

**The "current" path is a pointer on the student.** A new `StudentLearningState` row
(`student_id` primary key, `current_student_path_id` nullable FK) records which of the
student's active paths is the one the app opens by default. It may be null (a student between
paths, or with everything set aside). Invariant, enforced in the application layer:
`current_student_path_id`, when set, references a `StudentPath` that belongs to that student and
is not archived. Assigning a path sets it as the student's current path. Archiving the current
path clears or moves the pointer.

**Per-node completion stays keyed by `(student, content_node)`** — unchanged from ADR-011. The
Aggregation Worker continues to derive node-completion state per student, not per path. A
`StudentPathItem`'s status (`completed` / `in_progress` / `not_started` / `locked`) and the
path's `current_position` are **derived at read time** from those student-level completion
facts plus the item order — exactly as `BuildStudentPathItems` does today, now reading the
copied `StudentPathItem` rows instead of `LearningPathItem`. A consequence the concierge must be
aware of: a content node that a student already completed in an earlier path shows as
`completed` the moment it appears in a newly copied path ("you already learned this").

**Template edits do not propagate.** A `StudentPath` is a point-in-time copy. Changing a
`LearningPath` never changes an existing `StudentPath`. A "pull updates from the template"
action is explicitly out of scope.

**The MVP surface is unchanged in shape.** `GET /students/me/path` stays singular — it resolves
the student's `current_student_path_id`, returns that `StudentPath` with its derived per-item
status and `current_position`, and 404s when the pointer is null. The response field
`assignment_id` becomes `student_path_id`. No multi-path list endpoint, no catalog, no
enrollment UI in this decision — those are the two deferred backlog items ("Student path model
— copied instance, multi-path, running-path lifecycle" tracks the near-term implementation;
"Path catalog & teacher-mediated multi-enrollment" is the deferred epic).

This ADR **supersedes the earlier (never-accepted) draft of ADR-017** that proposed a
`deactivated_at` column on `PathAssignment`.

## Rationale

- **Copy over reference** is the only model that lets the concierge individualise a path
  without a per-student override table bolted onto shared template rows. It also makes ADR-015's
  "self-contained sequence" literally true, and makes template deletion safe (no instance
  depends on it).
- **Separate template and instance tables** because they diverge on every axis that matters:
  the template has no owner and no progress and is edited by content authors; the instance has
  one owner, derives progress, and is edited by the concierge for that student. A discriminator
  column would force every query and constraint to special-case the two.
- **Pointer on the student, not a `running` status on the path.** With completion tracked at
  `(student, node)`, a `StudentPath`'s progress state is almost entirely derivable — the only
  non-derivable per-path fact is "is this the one the student is working on". Putting that one
  fact in one place (`StudentLearningState.current_student_path_id`) keeps each `StudentPath`
  row free of mutable focus state and makes "switch current path" a single write. The cost — a
  pointer that must stay consistent with path archival — is contained by an FK plus one
  application-layer guard.
- **Completion at `(student, node)`, not `(student_path, node)`**, because "has this student
  learned this content" is a student-level truth, and re-teaching a node the student already
  completed is not the goal. It also leaves ADR-011 and the Aggregation Worker untouched. The
  trade-off — a freshly copied path can render partly pre-completed — is acceptable because the
  concierge chooses the copy's contents and because showing known material as already done is
  the desired behaviour, not a bug.
- **Deriving `StudentPathItem` status at read time** rather than storing it keeps a single
  source of truth (the completion facts) and means the copy operation only copies structure,
  never state.

## Consequences

### Positive
- The concierge can personalise each student's path freely; the template and other students are
  unaffected.
- A student can hold many paths; adding multi-path browsing, a catalog, or enrollment later is
  additive — no schema migration, because the instance model and the per-student pointer are
  already in place.
- `LearningPath` templates can be edited or deleted without touching any student's path.
- ADR-011 and the Aggregation Worker are unchanged; completion stays `(student, node)`.
- The MVP read surface and the derived-status logic are essentially as they are today.

### Negative / Trade-offs
- A substantial `motifpath-core` change: new `StudentPath` / `StudentPathItem` /
  `StudentLearningState` schemas, a copy-on-assign operation, removal of `PathAssignment`, and
  the `assignment_id` → `student_path_id` rename through the API and Gherkin. Cheap only because
  there is no data.
- Assigning a path is now an N-row copy rather than a single insert — negligible at MVP scale,
  but no longer O(1).
- `current_student_path_id` is a second piece of state to keep consistent with `archived_at`;
  a bug can point "current" at an archived or foreign path. Mitigated by the FK and a single
  application-layer guard, and by tests.
- A newly copied path can render with steps already `completed` if the student did those nodes
  elsewhere. Intended, but the concierge must understand it, and onboarding a brand-new student
  from a beginner template is the common case where it does *not* surprise anyone.
- Retained archived paths and per-student path copies grow storage and widen the surface a
  student data-erasure request must sweep (now `StudentPath`, `StudentPathItem`,
  `StudentLearningState`, plus completion facts).
- Two near-identical item shapes (`LearningPathItem`, `StudentPathItem`) to keep in step when
  the item structure changes (e.g. a future per-item field).

### Neutral
- `student_path_id` changes on every reassignment (a new copy), preserving today's contract
  that reassignment yields a fresh identifier.
- Whether `StudentLearningState` is its own table or a nullable column on `User` is an
  implementation detail; a dedicated table is preferred to keep student-only state off the
  shared identity row.
- "Paused" / "not started" / "completed" for a `StudentPath` are derivable from item completion
  and need not be stored; only `archived_at` is stored state on the accessibility axis.

## Related ADRs

- **ADR-015** (Challenge belongs to the path node; the student path is a self-contained
  sectioned sequence) — this ADR makes that self-containment literal by copying the sequence per
  student; `section_label` is copied per item.
- **ADR-011** (Minimal Aggregation Worker for MVP node-completion state) — unchanged; completion
  stays keyed by `(student, content_node)`, and `StudentPathItem` status is derived from it.
- **ADR-005** / **ADR-010** (Atlas + ent migration workflow) — the schema changes follow this
  workflow; since there is no data, the initial migration can be regenerated rather than
  layered.

---

*This ADR was decided on 2026-09-08. It supersedes the earlier unaccepted ADR-017 draft. To
revise, create a new ADR with Status: Supersedes ADR-017.*
