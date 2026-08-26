# ADR-011: Minimal Aggregation Worker for MVP Node-Completion State

**Status:** Proposed
**Date:** 2026-08-26
**Deciders:** Gilson Yamada (product/engineering lead)

---

## Context

ADR-006 decided the Kafka topology for MotifPath and named the Aggregation Worker as the sole
consumer of `motifpath.events` at MVP, with consumer group `aggregation-worker` reading the topic
and writing consolidated summaries to MongoDB Atlas `aggregates`. ADR-006 established the topology
but deliberately left the Aggregation Worker's internal write shape and business logic
unspecified — that detail was deferred to whichever plan first needed it.

Separately, the PB-8 implementation plan (`plans/PB-8-motifpath-core-implementation.md`) scoped
the Aggregation Worker itself out of the MVP build, treating it as a post-MVP service. That scoping
decision was made independently of ADR-006 and did not account for a concrete dependency: the
Core Domain Service's `GET /students/me/path` endpoint, specified in
`features/learning-paths/student-path-view.feature`, must return each learning-path item's
progress status — `completed`, `in_progress`, `not_started`, or `locked` — computed per student,
per content node. That status can only be derived from the `lesson.started`, `lesson.resumed`,
and `lesson.completed` events flowing through Kafka; nothing in the Core Domain Service's own
Postgres-backed domain model produces it. With the Aggregation Worker deferred, there was no
service responsible for turning those events into state the Core Domain Service could read.

This is not a new architectural direction — it is closing a gap between two decisions that were
each individually reasonable (a lean single-consumer Kafka topology; deferring non-essential
aggregation work) but that collectively left a required MVP feature unbuildable. Three ways to
close the gap were considered:

1. **Build a minimal slice of the Aggregation Worker now**, scoped only to node-completion status,
   and defer everything else (exercise-answer scoring summaries, analytics rollups) to the
   post-MVP full Aggregation Worker.
2. **Have the Core Domain Service consume `motifpath.events` directly**, as a second consumer
   group alongside `aggregation-worker`, maintaining its own Postgres progress table.
3. **Have the Core Domain Service query MongoDB `events` directly** (the raw log written
   synchronously by the Event Ingestion Service, per ADR-006's producer step), computing
   completion status at read time instead of from a precomputed aggregate.

## Decision

MotifPath will build a **minimal Aggregation Worker** as part of MVP scope (PB-8, Phase 4.0),
scoped exclusively to deriving per-student, per-content-node completion status from lesson-family
events. It is the same service ADR-006 already named — this ADR specifies its first write shape
and business rule rather than introducing a new consumer.

### Write shape

The worker writes one document per `(student_id, content_node_id)` pair to MongoDB `aggregates`:

```json
{
  "student_id": "uuid",
  "content_node_id": "uuid",
  "status": "not_started | in_progress | completed",
  "updated_at": "ISO-8601 timestamp"
}
```

### Transition rule

- `lesson.started` or `lesson.resumed` → `in_progress`, unless the document is already
  `completed`, in which case no change is made.
- `lesson.completed` → `completed`. This state is terminal and is never downgraded by a
  subsequent `started` or `resumed` event for the same node.
- All other event types (`exercise.*`) are ignored by this worker at MVP.

### Idempotency

The write is an upsert keyed on `(student_id, content_node_id)`, applying the transition rule
above rather than blindly overwriting. Because `completed` is terminal and re-applying
`in_progress` to an already-`in_progress` document is a no-op, redelivery of the same event
(ADR-006's at-least-once guarantee) never produces an incorrect result, with or without
deduplication by `event_id`.

### Scope boundary

This worker does not compute exercise-answer scoring, subject-level mastery, or any other
summary. Those remain explicitly out of scope and are deferred to the full Aggregation Worker,
which will get its own ADR when that work is scheduled.

## Rationale

**A minimal slice now, over deferring entirely (rejected: option omitted — the status quo before
this ADR):** Deferring the Aggregation Worker made sense in isolation, but `student-path-view`
is an MVP-scoped feature (PB-12c, already merged and part of the 15-endpoint Core Domain Service
surface) that cannot function without it. The choice is not "build it or don't" — it is "build
the small part that a merged, in-scope feature already depends on."

**Minimal Aggregation Worker over a second Core Domain Service consumer group (rejected):**
Giving the Core Domain Service its own Kafka subscription would work, but it duplicates the
consumer-group topology ADR-006 already settled and splits event-derived state across two
independently-consumed paths for no benefit — there is exactly one thing that needs this data
(the Core Domain Service), and exactly one service ADR-006 already designated to produce
event-derived state (the Aggregation Worker). Routing through the worker keeps "one producer,
one designated consumer per derived-state concern" intact and keeps the Core Domain Service's
dependencies limited to Postgres plus a read-only MongoDB collection, rather than a Kafka client
and consumer-group lifecycle it would otherwise have no reason to own.

**Minimal Aggregation Worker over reading the raw MongoDB `events` log at request time
(rejected):** Computing completion status from the raw event log on every `GET /students/me/path`
call would avoid building a new service, but it pushes an unbounded, per-request table scan
(or a hand-rolled index-and-aggregate query) into the read path of the SPA's primary screen.
Precomputing status asynchronously, as ADR-006 already intended for the Aggregation Worker,
keeps the read path a single indexed lookup and matches the write-time/read-time split ADR-006
established for exactly this reason.

**Scoping out exercise scoring and analytics:** Nothing in `student-path-view.feature` or any
other merged MVP feature currently depends on those summaries. Building them now would be
speculative work with no consuming feature to validate the aggregation logic against — the same
reasoning that justified deferring the Aggregation Worker in the first place, applied at the
sub-feature level instead of the whole-service level.

## Consequences

### Positive

- Closes the gap between ADR-006's decided topology and PB-8's scope without reopening or
  reversing either decision.
- `GET /students/me/path` reads a single indexed MongoDB document per node instead of computing
  status from the raw event log at request time.
- The consumer-group and write-path pattern established here (Kafka → MongoDB `aggregates`,
  idempotent upsert) is the same shape the full Aggregation Worker will extend later — no
  throwaway design.

### Negative / Trade-offs

- PB-8's scope grows by one new service (`services/aggregation-worker`) that the original plan
  did not budget for. This is new implementation, testing, and deployment surface within the
  same MVP timeline.
- The Core Domain Service now has a runtime dependency on MongoDB in addition to Postgres,
  specifically for reads on the student-path-view endpoint. If the Aggregation Worker is down or
  lagging, `GET /students/me/path` will serve stale completion status rather than failing —
  this staleness window is not bounded by this ADR and should be monitored once deployed.
- Because `completed` is terminal by design, there is no way to reset a node's status back to
  `not_started` or `in_progress` short of deleting the document directly in MongoDB. No MVP
  feature currently requires this, but it is a real limitation if one emerges.

### Neutral

- The full Aggregation Worker (exercise scoring, analytics rollups) remains a separate,
  unscheduled piece of work and will need its own ADR when it is picked up. This ADR does not
  presuppose what that worker's eventual design looks like beyond reusing the same service and
  consumer group.
- The consumer group ID remains `aggregation-worker`, as fixed by ADR-006. No new consumer group
  is introduced by this ADR.

## Related ADRs

- ADR-006: Kafka topology — single topic, student_id partition, MSK — this ADR specifies the
  write shape and business rule for the `aggregation-worker` consumer group that ADR-006 named
  but left unspecified.
- ADR-005: Database migration — Atlas + ent, startup lock — the Core Domain Service's own
  migration and startup story is unaffected; this ADR only adds a read-only MongoDB dependency
  alongside it.
- ADR-008: MongoDB Atlas — event log and aggregates storage — this ADR defines the concrete
  document shape written to the `aggregates` collection that ADR-008 established.

---

*This ADR was decided on 2026-08-26. To revise, create a new ADR with Status: Supersedes ADR-011.*
