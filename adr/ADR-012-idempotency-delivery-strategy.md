# ADR-012: Idempotency and Delivery-Guarantee Strategy for the Tracking-Event Pipeline

**Status:** Accepted
**Date:** 2026-08-26
**Deciders:** Gilson Yamada (product/engineering lead)

---

## Context

The tracking-event pipeline (Vue 3 SPA → Event Ingestion Service → MongoDB `events` + Kafka
`motifpath.events` → Aggregation Worker → MongoDB `aggregates`) was built in three separate
phases (ADR-006, ADR-008, ADR-011), each of which touched idempotency from its own local
perspective. No single document ever asked what happens under each of the three ways a duplicate
or a retry can actually occur — the same message redelivered, a producer mistakenly sending two
different messages for what should have been one fact, or an error somewhere in the chain
triggering a retry. A design review surfaced two gaps this ADR closes.

**Gap 1 — a stale spec commitment.** `openapi/event-ingestion-service.yaml` states: "the
Aggregation Worker deduplicates on event_id." That sentence was written before ADR-011 was
implemented. The Aggregation Worker built under ADR-011 never reads or stores `event_id` at
all — its idempotency comes from `domain.NextStatus` being a convergent, monotonic function:
replaying `lesson.started`, `lesson.resumed`, or `lesson.completed` for the same
`(student_id, content_node_id)` pair always converges to the same completion status, regardless
of how many times, or under how many different `event_id`s, the same semantic fact arrives.
ADR-006's own Consequences section independently repeats the stale assumption ("Idempotency must
be keyed on `event_id`"). Both need to be reconciled against what was actually built.

**Gap 2 — a real reliability defect in Event Ingestion Service, but not the one it first appears
to be.** `IngestEventService.Ingest` (Phase 3, already merged) republishes to Kafka on every
call, regardless of whether `MongoEventRepository.Save` performed a fresh insert or hit the
`events` collection's unique index on `event_id` (a duplicate). This was initially treated as a
bug to fix by suppressing the republish on a detected duplicate. That framing does not survive
scrutiny: Kafka is already at-least-once at the broker level — redelivery can happen from a
consumer restart or rebalance with no involvement from Event Ingestion at all — so every consumer
of `motifpath.events` already has to tolerate duplicates regardless of what Event Ingestion does
on a retry. Suppressing Event Ingestion's own duplicate publishes adds mechanism to prevent an
outcome the system must handle correctly anyway, for a reason unrelated to this endpoint.

The actual defect is different: `publishAsync` attempts delivery exactly once and, on failure,
only logs the error and gives up — permanently, with no retry — regardless of whether the
triggering request was a first attempt or a retry. Because `POST /events` returns its 202 as soon
as the Mongo write succeeds, the client has already been told "done" by the time the asynchronous
Kafka publish fails; it has no reason to ever call again. The one mechanism that could have
triggered a second attempt — a client retry — cannot reliably occur, because success was already
reported. This is a plain reliability gap, not an idempotency problem: a failed publish needs its
own retry mechanism, independent of whether the client ever retries.

## Decision

**Part 1 — Idempotency mechanism for the Aggregation Worker is convergent state, not event_id
tracking.** This is a correction of documentation to match already-implemented, working
behavior, not a code change. `openapi/event-ingestion-service.yaml`'s endpoint description is
updated to state that duplicate submissions are safe because every downstream consumer is
required to tolerate reprocessing the same underlying fact, whether it arrives under the same
`event_id` or, in the case of a producer mistake, a different one. ADR-006's Consequences section
is amended to strike the "keyed on `event_id`" assumption for the Aggregation Worker and point to
this ADR.

**Part 2 — Event Ingestion Service gets a retryable publish outbox**, so a failed Kafka publish
gets additional attempts on its own schedule instead of depending on a client retry that may
never come.

A new MongoDB collection, `publish_outbox`, holds one document per event, using `event_id` as the
document's `_id` (uniqueness comes free from MongoDB's primary-key constraint):

```
{
  _id: event_id,
  status: "pending" | "published" | "dead",
  attempts: int,
  last_error: string (optional),
  next_attempt_at: timestamp,
  created_at: timestamp,
}
```

Flow:

1. On a fresh `events` insert (not a duplicate), create a `publish_outbox` entry with
   `status: "pending"`, `attempts: 0`, alongside the existing synchronous Mongo write. A duplicate
   `events` insert does not create a new outbox entry — one already exists from the original
   attempt, in whatever state it is in.
2. Attempt to publish immediately, same as today — this fast path keeps the common case (publish
   succeeds on the first try) exactly as fast as it is now, with no added latency.
3. On success, mark the outbox entry `status: "published"`. On failure, increment `attempts`,
   record `last_error`, and set `next_attempt_at` to 30 seconds later — a fixed interval, not
   exponential, since kafka-go's own internal retry already covers the fast-growing end of the
   backoff curve before an entry ever reaches this path.
4. A background ticker inside the same Event Ingestion Service process — no new deployable
   service — scans `publish_outbox` every 30 seconds for `status: "pending"` entries whose
   `next_attempt_at` has passed, and retries them using the same publish path. This interval is
   deliberately coarse: kafka-go's own `Writer` already retries transient, retriable broker
   errors internally (default `MaxAttempts: 10`, backoff up to 1s) before `Publish` ever returns
   an error, so by the time an entry reaches `publish_outbox` as `pending`, kafka-go has already
   absorbed the sub-second-to-few-seconds class of blip. The sweep exists for what that
   in-process retry structurally cannot cover: an outage outlasting its short retry budget, or
   the service process restarting mid-retry.
5. After 5 failed sweep attempts (roughly 2.5 minutes of total resilience beyond kafka-go's own
   retry budget), an entry's `status` is set to `"dead"` instead of being retried again, and a
   structured error log is emitted (`logger.Error("event permanently failed to publish", ...)`) —
   free to add given ADR-003 already wires every service through OpenTelemetry/CloudWatch Logs,
   so a dead entry is at least visible there without requiring anyone to remember to query
   `publish_outbox` directly. Dead entries are not automatically retried further by the sweep —
   see Part 3 for how they get resolved.

`POST /events`'s response behavior is unchanged: it still returns 202 as soon as the Mongo write
succeeds, and Kafka delivery — now including any retries — remains fully asynchronous from the
caller's perspective.

**Part 3 — Manual remediation for dead-lettered entries.** A `dead` entry with no path forward
except a direct database query is not actually operable. Two new admin-only endpoints on Event
Ingestion Service close that gap:

- `POST /admin/publish-outbox/{event_id}/retry` — looks up the entry, attempts publish
  synchronously (unlike the normal fire-and-forget path, so the caller gets an immediate
  success/failure result), and updates `status`/`attempts`/`last_error` accordingly. A failed
  manual retry leaves the entry `dead` — it does not silently re-enable the automatic sweep.
- `POST /admin/publish-outbox/{event_id}/resolve` — marks the entry as manually handled without
  attempting to publish again, for cases where an operator has confirmed the event doesn't need
  (re-)delivery or has delivered it through some other means. This sets `status` to a fourth
  value, `"resolved_manually"`, kept distinct from `"published"` so the audit trail always shows
  whether Kafka actually confirmed receipt or a human decided to stop trying. Accepts an optional
  `reason` field, stored on the entry, for exactly that audit purpose. Both endpoints are
  idempotent — calling either on an already-terminal entry (`published`, `dead`, or
  `resolved_manually`) is a no-op that returns the entry's current state rather than erroring.

Both endpoints require the caller's JWT to carry an `admin` role claim, read directly from the
already-validated Clerk JWT (no network call to Core Domain Service, which does not yet exist).
This is the first role-gated endpoint anywhere in `motifpath-core` — Core Domain Service's own
`User.role` model (Phase 4) is still unbuilt, so role is sourced from a Clerk-issued claim
instead. See Consequences for the reconciliation this implies once Phase 4 ships.

## Rationale

**Convergent state over event_id tracking (Part 1):** Event-id-based deduplication only
protects against the exact same `event_id` arriving twice. It gives zero protection against a
producer bug that emits two *different* `event_id`s for what should have been one logical fact
(e.g., a double-fired `lesson.completed` from a client-side bug) — by definition, the IDs
differ, so a dedup table keyed on `event_id` would treat them as two distinct, valid events. The
convergent-state approach the Aggregation Worker already uses handles both cases uniformly,
because it doesn't ask "have I seen this ID," it asks "does processing this event change the
stored outcome" — a strictly stronger guarantee for this specific consumer, achieved with less
mechanism (no dedup table to maintain, prune, or reason about TTLs for).

**An outbox-with-retry over suppressing duplicate publishes (Part 2):** The originally proposed
`publish_receipts` design (check-before-publish, to avoid a duplicate) was rejected on further
review: it optimizes against a problem — Kafka-level duplicates — that already has to be
tolerated by every consumer regardless, per Part 1 and per Kafka's own at-least-once delivery
model. It also does not address the actual failure mode: a publish that fails once and is never
retried at all, whether or not the client ever calls back. An outbox with its own retry schedule
fixes that directly, and does not need to distinguish "already published" from "being retried" to
avoid duplicates — duplicates from a retry are an accepted, already-required outcome, not a
failure.

**In-process ticker over a separate worker service:** A dedicated retry service would mirror the
Aggregation Worker's pattern, but at MVP scale (tens to hundreds of students, consistent with
ADR-006's own framing) a background goroutine inside Event Ingestion Service is proportionate.
It avoids a fourth deployable unit for what is a small, bounded reliability concern, consistent
with this project's recurring MVP principle that operational burden is the more expensive
currency until scale demands otherwise.

**A fixed retry cap with a dead-letter status over unbounded retries:** Retrying forever risks an
ever-growing backlog of entries that are failing for a structural reason (e.g., a
misconfigured broker) rather than a transient one, with no signal that something needs
attention. Five attempts on a fixed 30-second interval (~2.5 minutes total, on top of whatever
kafka-go's own internal retry already absorbed) is a small, easy-to-reason-about bound for MVP;
a `dead` status plus a structured error log gives those entries a visible landing place without
requiring alerting infrastructure to exist yet. This is deliberately the simplest version of a
dead-letter concept, not a full DLQ topic or service — Kafka itself has no native producer-side
DLQ mechanism to lean on here (Kafka Connect's dead-letter-queue feature is consumer/sink-side
only and would not help with a cluster-wide outage in any case, since a DLQ topic lives on the
same unreachable cluster) — and this can be revisited once real failure patterns are observed.

**A separate `publish_outbox` collection over a field on `events` documents:** ADR-008 fixed the
`events` collection as an append-only durable log — no updates, no deletes. Adding retry
bookkeeping fields to those documents would violate that invariant and complicate the
collection's role as a stable audit trail. A separate collection keeps each concern in its own
place: `events` answers "what did we receive," and `publish_outbox` answers "what still needs to
reach Kafka, and how many times have we tried" — a question that only matters for the lifetime of
the at-least-once handshake, not forever.

**Two admin endpoints over expecting direct database access (Part 3):** A `dead` status with no
supported way to act on it just relocates the silent-loss problem from "never retried" to "never
retried, and now also invisible to anyone without database access." Two small, purpose-built
endpoints — retry now, or mark resolved — cover the two things an operator actually needs to do,
without building a general-purpose admin UI or query tool this ADR has no reason to scope.

**A Clerk JWT role claim over waiting for Core Domain Service (Part 3):** Gating these endpoints
is not optional — they can mutate delivery state for real student data — but Core Domain Service's
`User.role` model does not exist yet (Phase 4 is still ahead of Phase 4.0/ADR-011's own work).
Reading role from a Clerk-issued JWT claim unblocks this now, consistent with ADR-009's existing
pattern of resolving identity concerns from the JWT without a network call. The trade-off is
explicit, not accidental: once Phase 4 ships, role will exist in two places (the Clerk claim and
Core Domain Service's own `User.role`), and those two sources are not guaranteed to agree unless
something keeps them in sync. That reconciliation is out of scope here — see Consequences.

**A fourth status (`resolved_manually`) over reusing `published`:** Collapsing a manual
resolution into `published` would make the outbox lie about whether Kafka actually confirmed
receipt. Keeping them distinct costs nothing beyond one more enum value and preserves an honest
audit trail: `published` always means "Kafka confirmed this," `resolved_manually` always means "a
human decided to stop trying, for a reason that isn't necessarily 'Kafka has it.'"

## Consequences

### Positive

- A Kafka publish failure now gets up to five additional attempts on a 30-second interval,
  independent of whether the client ever retries `POST /events` — closing the silent-loss gap
  this ADR exists for. A permanently failing entry is at least logged, not purely silent.
- The `events` collection's append-only invariant (ADR-008) is preserved; no migration or schema
  change is needed there.
- The documented idempotency strategy now matches what the Aggregation Worker actually does,
  removing a source of confusion for anyone reading the OpenAPI spec or ADR-006 without also
  reading the Aggregation Worker's source.
- No new service is introduced — the retry loop lives inside the existing Event Ingestion Service
  process.
- Entries that exhaust their five automatic attempts are no longer a dead end: `POST
  /admin/publish-outbox/{event_id}/retry` and `.../resolve` give an operator a defined, auditable
  way to act on them instead of requiring direct database access.

### Negative / Trade-offs

- A new collection (`publish_outbox`) and a new background loop are new operational surface: one
  more thing a future engineer must understand when reasoning about the ingestion path.
- This is the first role-gated (admin-only) endpoint anywhere in `motifpath-core`, and it sources
  role from a Clerk JWT claim rather than Core Domain Service's `User.role` model, because the
  latter doesn't exist yet. Once Phase 4 ships, role exists in two places that are not
  automatically kept in sync — reconciling them (or migrating these endpoints to check Core
  Domain Service instead) is a follow-up this ADR does not resolve.
- This ADR does not, and cannot, protect against a producer sending a *wrong* fact (e.g., the
  correct event type but the wrong `content_node_id`). Idempotency and delivery guarantees only
  ensure a true fact is applied, and applied at all — they cannot detect that a fact is false.
  That remains an unaddressed data-quality boundary, out of scope here.

### Neutral

- `publish_outbox` grows at the same rate as `events` in the steady state. Unlike `events`,
  entries have no long-term audit value once `published` or `resolved_manually`, so a retention
  policy (e.g., a short TTL index on terminal entries) is a reasonable future addition but is not
  required for correctness at MVP scale and is left open here.
- This ADR does not change the Aggregation Worker's behavior at all — Part 1 is a documentation
  correction. Only Event Ingestion Service's `internal/application/`, `internal/adapters/repo/`,
  and `internal/adapters/http/` change under Parts 2 and 3.

## Related ADRs

- **ADR-006: Kafka Topology** — its Consequences section previously stated Aggregation Worker
  idempotency "must be keyed on `event_id`." Amended here to point to this ADR's Part 1 for the
  actual mechanism.
- **ADR-008: MongoDB Atlas — Event Log and Aggregates Storage** — established the `events`
  collection as append-only, which is why `publish_outbox` is a separate collection rather than
  fields added to `events` documents.
- **ADR-011: Minimal Aggregation Worker for MVP Node-Completion State** — specified the
  transition rule that Part 1 formally recognizes as the Aggregation Worker's actual idempotency
  mechanism, in place of the event_id-keyed approach ADR-006 originally assumed.
- **ADR-009: Clerk Go SDK for JWT Local Validation** — Part 3's admin endpoints extend this
  ADR's existing pattern of resolving identity/authorization concerns directly from the validated
  JWT, applying it to a role claim rather than just the `sub` claim.

---

*This ADR was decided on 2026-08-26. To revise, create a new ADR with Status: Supersedes ADR-012.*
