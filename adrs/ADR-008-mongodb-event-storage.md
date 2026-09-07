# ADR-008: MongoDB Atlas for Event Log and Aggregates Storage

**Status:** Proposed
**Date:** 2026-06-04
**Deciders:** Gilson Yamada (product/engineering lead)

---

## Context

The MotifPath platform records two categories of persistent data with fundamentally different
characteristics:

1. **Core domain data** — learning graphs, users, content nodes, exercises, thresholds, and path
   state. This data is highly relational, mutation-heavy, and transactionally consistent. It is
   covered by ADR-005 (Postgres via `ent`).

2. **Event log and aggregates** — the append-only stream of student tracking events and the
   summarised progress state derived from it. This data is write-heavy, schema-flexible, and
   queried primarily by `student_id` and time range. It has no relational joins with the core
   domain at query time.

ADR-005 does not address the event storage layer. This ADR records the decision for that layer.

The event payload schema presents a specific design constraint: two fields — `content_context` and
`trigger_context` — are intentionally flexible objects whose shape varies by event type and is
expected to evolve as new content modalities are added. Encoding this in a relational schema would
require JSONB columns or an EAV model, both of which degrade query clarity and make schema
evolution harder. A document model is a natural fit.

Alternatives considered:

- **Postgres (same instance as core domain):** Operationally simple. Rejected because the
  flexible payload fields (`content_context`, `trigger_context`) are a poor fit for relational
  schema, and the high-frequency append workload of the event log should not compete for I/O with
  the transactional core domain.
- **Amazon DynamoDB:** Managed, highly scalable, and AWS-native. Rejected because its query model
  (primary key + sort key only, with limited secondary index flexibility) is too restrictive for
  the analytics queries the Aggregation Worker will need. Operational and pricing complexity also
  exceeds what is justified at MVP scale.
- **TimescaleDB / InfluxDB:** Purpose-built for time-series metrics. Rejected because student
  tracking events are not pure metric streams — they carry rich, variable payload objects that
  benefit from document storage, not columnar time-series compression.
- **Kafka as the store of record:** Kafka provides durable event retention but is not designed
  for ad-hoc queries or point lookups. Using Kafka log retention as the primary event store
  would require replaying the full topic to reconstruct state. A dedicated queryable store is
  required alongside Kafka.

## Decision

MotifPath will use **MongoDB Atlas** (M10 tier for production) as the storage layer for the event
log and aggregated learning progress summaries. Two collections are defined within a single
`motifpath_events` database:

### `events` collection

Stores one document per tracking event, written synchronously by the Event Ingestion Service on
receipt. Documents are never updated or deleted; the collection is append-only.

**Document schema:**

| Field | Type | Notes |
|---|---|---|
| `event_id` | UUID string | Client-supplied. Unique index for idempotency. |
| `event_type` | string (enum) | One of the seven defined tracking event types. |
| `student_id` | UUID string | Partition key for all student-scoped queries. |
| `session_id` | UUID string | Groups events within a single browser session. |
| `occurred_at` | ISODate | Client-supplied event timestamp. |
| `received_at` | ISODate | Server-side write timestamp, set by Event Ingestion Service. |
| `content_context` | object (optional) | Flexible payload for lesson-family events. Shape varies by content type. |
| `exercise_id` | UUID string (optional) | Present on exercise-family events. |
| `trigger_context` | object (optional) | Flexible payload for exercise-family events. |
| `attempt_number` | integer (optional) | Present on `exercise.answer_sent`. Minimum value: 1. |
| `answer_payload` | object (optional) | Present on `exercise.answer_sent`. Shape varies by exercise type. |
| `outcome` | string (optional) | Present on `exercise.ended`. Values: `completed`, `abandoned`. |
| `final_score` | integer (optional) | Present on `exercise.ended` with outcome `completed`. |
| `duration_seconds` | integer (optional) | Present on `lesson.completed`. |

**Indexes:**
- `{ event_id: 1 }` — unique. Enforces idempotency at the storage layer.
- `{ student_id: 1, occurred_at: -1 }` — compound. Primary query pattern for retrieving a
  student's event history in reverse chronological order.
- `{ event_type: 1, occurred_at: -1 }` — compound. Supports analytics and backfill queries
  filtered by event type.

### `aggregates` collection

Stores one document per student per aggregation period, written and upserted by the Aggregation
Worker. Represents the current summarised progress state derived from the event stream.

**Document schema:**

| Field | Type | Notes |
|---|---|---|
| `student_id` | UUID string | Owner of this aggregate. |
| `period` | string (`YYYY-MM-DD`) | Aggregation window. One document per student per day. |
| `event_counts` | object | Map of event type to count for the period. |
| `total_duration_seconds` | integer | Sum of `duration_seconds` across `lesson.completed` events. |
| `exercises_completed` | integer | Count of `exercise.ended` events with outcome `completed`. |
| `exercises_abandoned` | integer | Count of `exercise.ended` events with outcome `abandoned`. |
| `last_event_id` | UUID string | `event_id` of the most recent event processed into this aggregate. Used for deduplication. |
| `last_updated` | ISODate | Timestamp of the most recent upsert. |

**Indexes:**
- `{ student_id: 1, period: 1 }` — unique compound. Enforces one aggregate document per
  student per day and is the primary lookup key.
- `{ student_id: 1, last_updated: -1 }` — supports queries for the most recent aggregate
  state for a given student.

### Write pattern

The Event Ingestion Service performs a **synchronous write** to the `events` collection before
returning 202 to the caller. Kafka publication is asynchronous and happens after the write
completes. The 202 response signals durable receipt, not Kafka delivery.

The Aggregation Worker reads from the `motifpath.events` Kafka topic and performs **upserts**
into the `aggregates` collection using `{ student_id, period }` as the filter key. It uses
the `last_event_id` field to detect and skip already-processed events, providing
at-least-once processing with application-level deduplication.

## Rationale

MongoDB Atlas is chosen over the alternatives primarily because the document model directly
accommodates the flexible payload fields that are a core part of the event schema. Adding new
event types or extending existing payload objects requires no schema migration — the Aggregation
Worker and any future consumers simply ignore unrecognised fields. This is critical given that
the event taxonomy will evolve as new content modalities are introduced.

Separating event storage from the core domain Postgres instance is a deliberate isolation
boundary. The event log's write profile (high-frequency appends from the SPA) is incompatible
with the transactional, update-heavy workload of the core domain. Sharing an instance would
degrade both workloads and couple their scaling paths.

The two-collection design (raw events + daily aggregates) reflects the two consumption patterns:
point-in-time audit and replay (events collection) versus low-latency current-state queries
(aggregates collection). The Aggregation Worker maintains the aggregates, keeping read latency
low for the Core Domain Service without requiring it to scan the raw event log.

MongoDB Atlas M10 is chosen over a self-managed MongoDB deployment for the same reason Clerk
is chosen over a custom auth system: operating a MongoDB cluster correctly (replication,
backups, index monitoring, version upgrades) exceeds the MVP engineering budget.

## Consequences

### Positive
- Flexible document model accommodates evolving payload shapes without migrations.
- Event log is isolated from core domain; each can scale independently.
- Atlas M10 provides managed replication, automated backups, and index performance monitoring.
- Idempotency is enforced at the storage layer via the unique `event_id` index.
- Daily aggregate documents keep Core Domain Service queries O(1) in event volume.

### Negative / Trade-offs
- Two database technologies in the stack increase operational surface: teams must understand
  both Postgres and MongoDB.
- No cross-store transactions: the synchronous MongoDB write and the Kafka publish are not
  atomic. A crash between them leaves the event stored but unpublished. The Event Ingestion
  Service must be designed to tolerate and retry Kafka publish failures independently.
- Atlas M10 is a cost commitment; the free tier (M0) is insufficient for production write
  throughput. Budget must account for this before exiting closed alpha.
- The `sub`-to-`student_id` mapping (ADR-007) must be resolved before writing events, since
  `student_id` is the partition key for all event queries.

### Neutral
- The `motifpath_events` database name and collection names (`events`, `aggregates`) must be
  consistent across all services and environments. They are injected via environment variables
  (`MONGO_DATABASE`, `MONGO_EVENTS_COLLECTION`, `MONGO_AGGREGATES_COLLECTION`).
- Index creation is the responsibility of the service that owns the collection. The Event
  Ingestion Service creates `events` indexes at startup; the Aggregation Worker creates
  `aggregates` indexes at startup. Both are idempotent operations.

## Related ADRs

- ADR-005: Database migration — Atlas + `ent`, startup lock. Governs the Postgres layer;
  this ADR governs the complementary MongoDB layer.
- ADR-006: Kafka topology — single topic, `student_id` partition. The Kafka topic is the
  bridge between the `events` collection (written by Event Ingestion Service) and the
  `aggregates` collection (written by Aggregation Worker).
- ADR-007: Clerk authentication and JWT local validation. The `student_id` written to both
  collections derives from the JWT `sub` claim mapping established in ADR-007.

---

*This ADR was decided on 2026-06-04. To revise, create a new ADR with Status: Supersedes ADR-008.*
