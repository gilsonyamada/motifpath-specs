# ADR-006: Kafka Topology — Single Topic, Student Partition, MSK

**Status:** Proposed
**Date:** 2026-05-25
**Deciders:** Gilson Yamada (solo engineering at MVP)

---

## Context

ADR-003 instrumented all services with OpenTelemetry and explicitly deferred Kafka until a second event consumer existed. That trigger has now fired: the addition of an **Aggregation Worker** as a distinct service that consolidates raw events into pre-computed summaries for the learning graph creates a genuine fan-out need — the same stream of student events must flow to two independent consumers.

MotifPath at MVP tracks seven student-facing events emitted by the Vue 3 SPA through the Event Ingestion Service: `lesson.started`, `lesson.resumed`, `lesson.completed`, `exercise.started`, `exercise.progress`, `exercise.answer_sent`, and `exercise.ended`. Event volume at MVP is low — a student population measured in tens or hundreds, not millions — but the event schema and Kafka topology chosen now will be inherited by production.

The core tension is between keeping the topology simple (few topics, clear ownership) and keeping it expressive (separate topics per domain area, independent retention and scaling per event type). A secondary tension is operational: AWS MSK (managed Kafka) vs. self-hosting Kafka on EKS, where managed reduces operational overhead at the cost of a new bill line.

## Decision

MotifPath will use a **single Kafka topic — `motifpath.events`** — hosted on **AWS MSK**, with messages **partitioned by `student_id`**.

### Concrete topology

- **Topic:** `motifpath.events` (single topic for all domain events at MVP)
- **Partitioning key:** `student_id` — guarantees ordered delivery of all events for a given student to the same partition
- **Partition count:** 12 (sufficient for MVP; supports up to 12 parallel consumers per group without rebalancing)
- **Replication factor:** 3 (MSK default; tolerates one broker failure without data loss)
- **Retention:** 7 days (accommodates Aggregation Worker replay without unbounded storage cost)
- **Broker:** AWS MSK, Kafka 3.7, `kafka.t3.small` at MVP

### Producer

The **Event Ingestion Service** is the sole Kafka producer. On receiving a valid event from the frontend:

1. Writes the raw event to MongoDB Atlas `events` collection (durable log, synchronous)
2. Publishes the event to `motifpath.events` (async, at-least-once semantics)

### Consumer groups

| Group ID | Service | Reads | Writes |
|---|---|---|---|
| `aggregation-worker` | Aggregation Worker | `motifpath.events` | MongoDB `aggregates` |

The Aggregation Worker is the sole Kafka consumer at MVP. The group ID `aggregation-worker` is stable across restarts, enabling offset commit and controlled replay from any point in the topic.

**Write shape and business rule:** This ADR fixes the topology and consumer group only. The
concrete `aggregates` document shape, the event-to-status transition rule, and the MVP scope
boundary (node-completion status only, not exercise scoring or analytics) are specified in
ADR-011.

## Rationale

**Single topic over one-topic-per-event-type:** At seven event types and MVP scale, a multi-topic topology adds consumer management complexity without delivering independent retention or scaling benefits that matter at this stage. An `event_type` field in every message envelope allows consumers to filter client-side. The upgrade path to domain-scoped topics (`motifpath.events.lesson`, `motifpath.events.exercise`) is additive — no topology rewrite required.

**`student_id` as partition key:** The Aggregation Worker's correctness depends on processing a given student's events in arrival order — computing summaries from out-of-order events would require stateful sorting. Partitioning by `student_id` ensures all events for a student land on the same partition and are consumed in order. An alternative key (`session_id`) would give finer-grained ordering but fragment student history across partitions, complicating aggregation.

**AWS MSK over self-hosted Kafka on EKS:** ADR-003 established the pattern: at MVP, operational burden is the more expensive currency. Self-hosting Kafka on EKS means managing KRaft quorum, broker upgrades, persistent volumes, and failure recovery — all before a single student has used the product. MSK removes this entirely.

**AWS MSK over EventBridge / SQS:** EventBridge and SQS lack consumer-group offset semantics — there is no "replay from offset N" in SQS. The Aggregation Worker's schema-migration replay requirement is a first-class design constraint, not an edge case, and Kafka's consumer group model is the right fit.

## Consequences

### Positive

- Event ordering per student is guaranteed — aggregation logic is stateless per message.
- Consumer groups allow the Aggregation Worker and any future consumer to advance their offsets independently.
- 7-day retention enables full replay for schema migrations without re-ingesting from MongoDB.
- MSK removes broker operations entirely — no KRaft management, no storage provisioning.
- Single topic keeps subscription logic simple: one `subscribe()` call per consumer.

### Negative

- **New AWS bill line.** `kafka.t3.small` on MSK (3-broker minimum) costs approximately $46/month. This is the first paid infrastructure addition beyond the base stack defined by the deployment pipeline.
- **No per-event-type retention control.** A single topic cannot apply different retention periods to lesson vs. exercise events. If retention requirements diverge — e.g., a regulatory hold on lesson completions — a topic split will be required.
- **Partition count is fixed post-creation.** 12 partitions is a safe choice, but increasing it later disrupts the `student_id` → partition mapping during the rebalance window, potentially reordering in-flight events. Reducing partitions is not supported.
- **At-least-once semantics require idempotent consumers.** The Aggregation Worker must handle duplicate messages (e.g., after a restart mid-batch). ~~Idempotency must be keyed on `event_id`~~ — superseded by ADR-012: the Aggregation Worker's idempotency is achieved via a convergent status-transition function, not `event_id` tracking.

### Neutral

- The consumer group ID `aggregation-worker` must be stable across deployments. Renaming it loses committed offsets and triggers a full-topic replay.
- Future consumers (real-time notifications, AI recommendation engine) can subscribe to `motifpath.events` as additional consumer groups without any topology change.
- LLM-driven event interpretation is out of scope for this ADR. If an AI consumer is added to this topic, it will require its own ADR covering model selection, latency expectations, and cost.

## Alternatives Considered

### 1. One topic per event type (seven topics)

e.g., `motifpath.events.lesson.started`, `motifpath.events.exercise.answer_sent`

**Rejected at MVP.** Fine-grained topics make sense when event types have meaningfully different retention, volume, or consumer sets. At MVP, the overhead of seven topics, seven topic policies, and multi-topic subscriptions is not justified. A single topic with an `event_type` field achieves the same logical separation at lower operational cost.

### 2. Two domain-scoped topics (`motifpath.events.lesson`, `motifpath.events.exercise`)

**Deferred.** A reasonable intermediate step when lesson and exercise event streams diverge in volume or retention requirements. Straightforward to introduce without a topology redesign — add topics, update producer routing and consumer subscriptions.

### 3. AWS EventBridge

Managed event bus, no brokers, generous free tier.

**Rejected.** EventBridge has no consumer-group offset model. Replay requires a separate EventBridge Archive (additional cost and configuration). The Aggregation Worker's schema-migration replay requirement eliminates EventBridge as a viable option.

### 4. Amazon SQS + SNS fan-out

Standard AWS async pattern with at-least-once delivery and SNS-based replication to multiple queues.

**Rejected.** No consumer offset semantics — replay requires a dead-letter queue strategy, not a rewind-to-offset operation. More moving parts (one SQS queue per consumer) for a weaker guarantee set than Kafka provides.

### 5. Self-hosted Kafka on EKS

Maximum control over version, configuration, and cost.

**Rejected at MVP.** Consistent with ADR-003's principle: operational burden is the most expensive currency at MVP. Kafka on EKS requires managing KRaft quorum, broker persistent volumes, upgrade runbooks, and failure recovery — before a single student has used the product. Start managed; bring in-house if cost or control requirements change at a later stage.

## Related ADRs

- **ADR-003: OpenTelemetry Instrumentation with Deferred Backend** — explicitly deferred Kafka until a second consumer existed. This ADR fires that trigger.
- **ADR-004: Deployment Pipeline** — EKS and AWS infrastructure model that MSK integrates with.
- **ADR-011: Minimal Aggregation Worker for MVP Node-Completion State** — specifies the write shape and business rule for the `aggregation-worker` consumer group named here.
- **ADR-012: Idempotency and Delivery-Guarantee Strategy for the Tracking-Event Pipeline** — corrects this ADR's assumption that consumer idempotency is keyed on `event_id`, and specifies the actual mechanism plus the Event Ingestion Service's delivery-guarantee fix.

## References

- Platform Architecture — MVP (Notion): `35e9ccc1-102f-8134-8918-d8d853b81f9c`
- AWS MSK pricing: <https://aws.amazon.com/msk/pricing/>

---

*This ADR was decided on 2026-05-25. To revise, create a new ADR with Status: Supersedes ADR-006.*
