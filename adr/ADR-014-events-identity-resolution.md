# ADR-014: `POST /events` Resolves the Caller's MotifPath Identity from the Core Domain Service

**Status:** Proposed
**Date:** 2026-08-27
**Deciders:** Gilson Yamada (product/engineering lead)

---

## Context

ADR-007 established two rules for identity on `POST /events`:

- **Identity claim mapping** — the JWT `sub` claim is Clerk's internal user ID; the Core Domain
  Service maps `sub` to the MotifPath `student_id` at registration, and "all subsequent domain
  operations use the MotifPath ID."
- **Payload identity check** — the service must verify that the `student_id` in the event body
  matches "the identity derived from the JWT `sub` claim," rejecting a mismatch with `401`.

When ADR-007 was written the Core Domain Service did not exist, so there was nothing to perform
the `sub` → `student_id` mapping. The Event Ingestion Service shipped an interim reading of the
second rule: it treats the raw `sub` claim *as* the `student_id` and compares the event body
against it directly (`ClerkAuthMiddleware` → `WithStudentID(sub)` → `IngestTrackingEvent`).

That interim behavior is now a correctness blocker for the student-facing alpha (PB-8):

1. The frontend obtains the caller's MotifPath `user_id` from the Core Domain Service's
   `GET /users/me` and puts *that* value in each event's `student_id` field — the value every
   downstream consumer expects. The Aggregation Worker keys node-completion state on
   `student_id`, and `GET /students/me/path` reads it back by the same key.
2. The Event Ingestion Service compares that `user_id` against the Clerk `sub`. The two values
   are structurally different (a MotifPath UUID vs. a `user_...` Clerk ID), so **every event from
   a correctly-behaving, registered client is rejected with `401`.**

So the pipeline cannot carry a single real event end to end until the Event Ingestion Service
resolves the same MotifPath identity the rest of the platform uses.

ADR-013 resolved the analogous problem for the *admin* endpoints (role from the Core Domain
Service) but explicitly scoped out the hot path: "a per-request authorization check on a
high-volume endpoint like `/events` ... would need its own decision (short-TTL token claims, a
cache, or an event-driven local replica)." This is that decision.

The binding constraint is ADR-007's own rationale #2: **no per-request network call to a central
service on the `/events` hot path** — it would add latency to every event and make Core Domain
Service availability a hard dependency of ingestion.

Alternatives considered: resolve `sub` → `user_id` per event with no cache; have the Core Domain
Service write `user_id` into the Clerk JWT as a custom claim at registration; run an
event-driven local replica of the `sub` → `user_id` table in the Event Ingestion Service.

## Decision

The Event Ingestion Service will resolve the caller's MotifPath `user_id` by calling the Core
Domain Service's `GET /users/me` with the caller's forwarded bearer token (the same mechanism
ADR-013 introduced), and validate that the event body's `student_id` equals that resolved
`user_id`. The raw `sub` claim is no longer treated as an identity for payload validation.

**The resolution is cached in-process, keyed by the `sub` claim.** This is sound — not a
compromise — because the `sub` → `user_id` mapping is a **registration-time invariant** (ADR-007:
"a registration-time invariant"; `user_id` is immutable, `role` notwithstanding): once known for a
`sub` it never changes. The cache therefore cannot serve a stale answer.

- **Cache:** bounded LRU (10,000 entries) with a 1-hour TTL. At MVP scale the TTL is effectively
  "for the process lifetime"; it exists only to bound memory and to eventually pick up the
  should-never-happen case of a re-created mapping.
- **Steady state:** one `GET /users/me` per caller per hour (per service instance), not per
  event. ADR-007 rationale #2 is preserved — the hot path makes no network call once warm.
- **Cold miss, Core Domain Service reachable:** resolve and cache, then proceed.
- **Cold miss, Core Domain Service unreachable / times out / `5xx`:** fail closed. `POST /events`
  returns `503` and the event is **not** stored. The client retries the event later. (A warm
  cache entry is unaffected by a Core Domain Service outage.)
- **`GET /users/me` returns `404`** (valid token, `sub` never registered): the caller is not a
  MotifPath student. `POST /events` returns `401`, consistent with ADR-007's "mismatch → 401."
- **Resolved `user_id` ≠ body `student_id`:** unchanged from today — `401` (a client sending
  another user's `student_id`).

The lookup uses a 3-second timeout and no retry, matching ADR-013. The forwarded token is
validated locally first (ADR-009), exactly as for the admin endpoints.

**Spec changes (follow-up, not part of this ADR):** `openapi/event-ingestion-service.yaml` adds a
`503` response to `POST /events` and rewords the `BearerAuth` security-scheme description to say
the body's `student_id` must equal the caller's resolved MotifPath `user_id`;
`features/event-ingestion/ingest-tracking-event.feature` gains scenarios for the unregistered
caller and the identity-service-unavailable outcomes. `GET /users/me` needs no change — it
already returns `user_id`.

## Rationale

**Cache keyed on an immutable mapping, over a per-event call.** ADR-007 rationale #2 rules out a
per-request network call on `/events`, and it is right to — but that constraint is about
*repeated* calls for a value that does not change. Because `sub` → `user_id` is fixed at
registration, a single resolution per `sub` is enough forever; the cache turns "per event" into
"once per caller per instance." This is the cheapest correct option and it keeps the hot path
network-free in steady state, which is what ADR-007 actually cares about.

**Resolve from the Core Domain Service, over a `user_id` claim in the Clerk JWT.** Having the
Core Domain Service write `user_id` into Clerk user metadata at registration would put the value
in the token and need no lookup at all. It was rejected for the same reasons ADR-013 rejected the
equivalent for `role`, minus the staleness concern (this mapping is immutable): it makes Clerk a
write target for domain data, adds a Clerk Backend API call and failure mode to the registration
path, and couples the token's contents to a second system's schema. The cache achieves the same
"no per-event network call" outcome without any of that, and `GET /users/me` already returns
exactly the field needed.

**A shared in-process cache, over an event-driven local replica of the mapping table.** A replica
(Core Domain Service publishes `user.registered`, the Event Ingestion Service consumes it into a
local store) would also eliminate the hot-path call and would survive a Core Domain Service
outage even for cold entries. It is rejected for MVP as disproportionate: a new event type, a new
consumer, a new local store, and a new class of "replica drift" bug, to serve a lookup that a
10-line cache handles. It is the right answer if the Event Ingestion Service ever needs the
mapping while Core Domain Service is down *and* cold — revisit then.

**Fail closed with `503`, over `sub`-as-fallback.** If identity cannot be resolved on a cold
cache during a Core Domain Service outage, accepting the event on the old `sub`-as-`student_id`
basis would write a document keyed on a value no consumer can match — silent data corruption that
surfaces later as missing progress. Rejecting with `503` keeps the client's event (it retries)
and keeps the `events` collection correct. The blast radius is small: only callers not seen in
the last hour by that instance, only during an actual Core Domain Service outage.

**`401` for an unregistered `sub`.** A valid Clerk token whose `sub` has no MotifPath user is
indistinguishable, for `/events`, from a payload whose `student_id` cannot be matched to the
caller — ADR-007 already maps that to `401`. Using the same code avoids inventing a `403` for a
case the existing contract already covers.

## Consequences

### Positive

- The tracking pipeline can carry a real event end to end for the first time: the `student_id`
  written to `events` is the same MotifPath `user_id` the Aggregation Worker and
  `GET /students/me/path` key on.
- ADR-007's stated intent ("all subsequent domain operations use the MotifPath ID") is finally
  realized on `/events`; the raw `sub` claim stops leaking into domain data.
- Reuses ADR-013's `coredomain` client and forwarded-token pattern — no new auth mechanism, no
  new credential.
- The hot path stays network-free in steady state, honoring ADR-007 rationale #2.

### Negative / Trade-offs

- `POST /events` gains a cold-start dependency on the Core Domain Service: the first event from a
  given caller on a given instance (or the first after a TTL expiry / eviction) blocks on a
  `GET /users/me` call, and fails with `503` if the Core Domain Service is down at that moment.
  Warm callers are unaffected.
- New in-process state (the cache) and a new `503` outcome on `/events` — more for a future
  engineer to understand on the ingestion path, and an operator must know a `503` here can mean
  "Core Domain Service is unhealthy."
- Cache memory: bounded, ~10k × (≈40 B key + 16 B value) ≈ under 1 MB per instance at the cap.
- The cache assumes the mapping's immutability. If a `sub` → `user_id` mapping is ever
  deliberately re-pointed (not a supported operation today), events would validate against the
  stale `user_id` for up to the TTL.

### Neutral

- This ADR changes only the Event Ingestion Service's `internal/adapters/http`,
  `internal/adapters/coredomain`, and `internal/application` (payload check). No change to the
  Aggregation Worker, the Core Domain Service, or the `events` / `publish_outbox` schemas.
- The `coredomain` client currently exposes only `role` (ADR-013). Whether to widen it to return
  the whole profile (`user_id` + `role`) for both callers, or add a second method, is an
  implementation detail for the plan — not a decision this ADR needs to make.
- ADR-007's `sub`-as-`student_id` interim behavior is fully retired by this ADR. ADR-007's
  "Payload identity check" bullet should be read as amended: "the identity derived from the JWT"
  means the MotifPath `user_id` the Core Domain Service maps `sub` to, not `sub` itself.

## Related ADRs

- **ADR-007: Clerk authentication and JWT local validation** — this ADR amends its "Payload
  identity check" and "Identity claim mapping" bullets to their originally-intended meaning now
  that the Core Domain Service exists, and satisfies its rationale #2 (no per-request hot-path
  network call) via the immutable-mapping cache rather than by avoiding the call entirely.
- **ADR-013: Event Ingestion resolves admin role from Core Domain Service** — this ADR is the
  hot-path identity decision ADR-013 explicitly deferred. It reuses ADR-013's `coredomain` client
  and forwarded-token mechanism, adding the cache that the rare admin path did not need.
- **ADR-009: Clerk Go SDK for JWT local validation** — the local validation that runs before the
  `GET /users/me` call is unchanged.
- **ADR-011: Minimal Aggregation Worker** — consumes `student_id` from `motifpath.events`; this
  ADR ensures that value is the MotifPath `user_id` the worker's `aggregates` documents are keyed
  on.

---

*This ADR was decided on 2026-08-27. To revise, create a new ADR with Status: Supersedes ADR-014.*
