# Plan: `POST /events` resolves the caller's MotifPath identity

**Task:** PB-8 (ADR-014)
**Date:** 2026-08-27
**Author:** Gilson Yamada
**Status:** In Progress — Phase 1 (spec) and Phase 2 (backend) implemented on their branches; pending review/merge

---

## Goal

Make the Event Ingestion Service validate an event's `student_id` against the caller's MotifPath
`user_id` (resolved from the Core Domain Service and cached), instead of against the raw Clerk
`sub` claim. Implements ADR-014. Unblocks a real event flowing end to end for the student alpha.

## Scope

**In scope:**
- OpenAPI: `503` on `POST /events`; `BearerAuth` description reworded (`student_id` = resolved
  MotifPath `user_id`).
- Gherkin: unregistered-caller and identity-service-unavailable scenarios in
  `ingest-tracking-event.feature`.
- `motifpath-core`: widen the `coredomain` client to return the full profile; add a sub-keyed
  caching identity resolver; move the payload identity check to the application layer against the
  resolved `user_id`; wire it through `main.go`.

**Out of scope:**
- Any Core Domain Service change (`GET /users/me` already returns `user_id`).
- An event-driven local replica of the `sub` → `user_id` mapping (ADR-014 rejected for MVP).
- A `user_id` claim in the Clerk JWT (ADR-014 rejected).
- The admin endpoints' behavior — only the shared `coredomain` client is refactored, not the
  ADR-013 authorization logic.

## Prerequisites

- [ ] ADR-014 merged to `motifpath-specs` `main`.
- [x] `coredomain` client + forwarded-token capture exist (ADR-013, merged core #6).
- [x] Core Domain Service `GET /users/me` returns `UserProfile.user_id`.

---

## Implementation Steps

### Phase 1 — Spec (motifpath-specs)

**Branch:** `adr/PB-8/014-events-identity-resolution` (same branch as ADR-014)

- [x] Step 1: `openapi/event-ingestion-service.yaml` — add a `503` response to
  `ingestTrackingEvent` referencing `ServiceUnavailableError` (added in ADR-013's spec work);
  reword the `BearerAuth` `securitySchemes` description: the body's `student_id` must equal the
  MotifPath `user_id` the service resolves for the caller from the Core Domain Service, not the
  raw `sub` claim; a caller with no registered profile is rejected with `401`; a `503` means the
  identity could not be resolved because the Core Domain Service was unreachable.
- [x] Step 2: `features/event-ingestion/ingest-tracking-event.feature` — add scenarios:
  - a caller whose identity has never been registered may not submit events (→ authentication
    error);
  - an event is refused as temporarily unavailable when the caller's identity cannot be resolved
    (Core Domain Service unreachable);
  - (keep) the existing "token belongs to a different student" scenario — now meaning the body
    carries a `student_id` other than the caller's resolved `user_id`.
- [x] Step 3: `npx @redocly/cli lint openapi/*.yaml` + `@cucumber/gherkin-streams` green.

**Definition of Ready check:**
- [x] OpenAPI endpoint(s) defined (`503` added, security description self-sufficient)
- [x] Gherkin: happy path + ≥2 edge cases + ≥1 failure case (existing happy paths + new failures)
- [x] ADR exists — ADR-014

---

### Phase 2 — Backend (motifpath-core)

**Branch:** `feat/PB-8/events-identity-resolution` (from `dev`)

TDD: failing test first, then implementation.

- [x] Step 1: `make generate` (picks up the `503` response type for `ingestTrackingEvent`).
- [x] Step 2: Widen the shared Core Domain client.
  - `ports`: rename `RoleResolver` → `ProfileResolver`, method
    `ResolveProfile(ctx, bearerToken) (Profile, error)` where `Profile{UserID, Role string}`.
    Rename `ErrRoleUnavailable` → `ErrProfileUnavailable` (keep `ErrIdentityNotRegistered`).
  - `adapters/coredomain`: `RoleResolver` → `Client`, one HTTP method returning both fields;
    decode `{user_id, role}` from `GET /users/me`; `200` with an empty `user_id` → `ErrProfileUnavailable`.
  - `application.AdminAuthorizer`: depend on `ports.ProfileResolver`, read `.Role`. Mechanical
    test updates (`fakeRoleResolver` → `fakeProfileResolver`).
- [x] Step 3: `ports.IdentityResolver` — `ResolveUserID(ctx, sub, bearerToken) (string, error)`.
  Failing tests first: cache hit returns without calling the client; cache miss calls the client
  and caches; `ErrIdentityNotRegistered` and `ErrProfileUnavailable` propagate and are **not**
  cached; entries expire after the TTL; LRU eviction past the cap.
- [x] Step 4: `adapters/coredomain.CachingIdentityResolver` — wraps a `ports.ProfileResolver`,
  bounded LRU (10k) + 1h TTL keyed on `sub`, stores only `Profile.UserID`. Implements
  `ports.IdentityResolver`. Use a small dependency-free LRU or `hashicorp/golang-lru/v2` if
  already in `go.sum` — decide during implementation.
- [x] Step 5: Move the payload identity check into the application layer.
  - `IngestEventService.Ingest(ctx, callerUserID string, event)` — validate
    `event.Base().StudentID == callerUserID`, else `domain.ErrIdentityMismatch` (new sentinel).
  - Update `IngestEventService` unit tests for the new parameter + the mismatch case.
- [x] Step 6: `adapters/http` — `IngestTrackingEvent` handler:
  - read `sub` (`StudentIDFromContext`) and token (`BearerTokenFromContext`); `401` if either
    absent.
  - `userID, err := identityResolver.ResolveUserID(ctx, sub, token)`; map
    `ErrIdentityNotRegistered` → `401`, `ErrProfileUnavailable` → `503`, else return `err`.
  - `h.service.Ingest(ctx, userID, event)`; map `domain.ErrIdentityMismatch` → `401`.
  - drop the inline `event.Base().StudentID != authenticatedStudentID` check.
- [x] Step 7: `cmd/main.go` — build `coredomain.Client` → `CachingIdentityResolver`, inject into
  the handler; the same `Client` still feeds `AdminAuthorizer`. `CORE_DOMAIN_BASE_URL` already
  required (ADR-013).
- [x] Step 8: BDD — `steps_ingest_test.go` / `world_test.go`: a `fakeIdentityResolver` (settable
  `user_id` / error); steps for "identity has never been registered" and "identity cannot be
  resolved"; the existing auth steps keep working (default resolver returns the token student's
  `user_id`). Wire the two new scenarios.
- [x] Step 9: `make lint test test:int test:bdd` green; coverage ≥ 80% on
  `internal/application/`.

**Coverage gate:** 80% on `services/event-ingestion/internal/application/`.

---

### Phase 3 — Frontend (motifpath-web)

Not applicable. (The frontend already reads `user_id` from `GET /users/me` and sends it as
`student_id` — that assumption is what this plan makes true on the ingestion side.)

### Phase 4 — Infrastructure (motifpath-infra)

None beyond the already-tracked `CORE_DOMAIN_BASE_URL` follow-up from ADR-013.

---

## Rollback Plan

Stateless HTTP service on EKS blue/green (ADR-004) — redeploy the previous image. No data
migration; `events` / `publish_outbox` schemas are untouched. Reverting restores the
`sub`-as-`student_id` check (and the alpha blocker); a superseding ADR would be required to make
that the intended state again.

## Validation

- [ ] A registered student whose `GET /users/me` `user_id` is `U` can submit an event with
  `student_id = U` and it is stored; the stored document's `student_id` is `U`.
- [ ] The same student submitting `student_id = <other UUID>` is rejected (authentication error).
- [ ] A valid Clerk token whose `sub` is not registered is rejected (authentication error).
- [ ] With the Core Domain Service stopped and a cold cache, `POST /events` returns `503` and
  stores nothing; with a warm cache entry, the same student's events still succeed.
- [ ] Steady-state: submitting 50 events for one student triggers exactly one `GET /users/me`.
- [ ] `grep -rn "authenticatedStudentID" services/event-ingestion` returns nothing.

## Open Questions

| Question | Owner | Resolution |
|---|---|---|
| Dependency-free LRU vs. `hashicorp/golang-lru/v2`? | Gilson | **Resolved** — dependency-free. Only `golang-lru` v1 is present (transitively); a ~40-line mutex-guarded TTL map with coarse overflow handling is enough at MVP and adds no direct dependency. |
| Should a cold-miss `503` also emit a structured error log? | Gilson | **Deferred** — the `Handler` struct carries no logger today, and a `503` is already visible through ADR-003's HTTP-level OTel/CloudWatch telemetry. A dedicated `logger.Warn` with `sub` can be added once the handler takes a logger. |

## Related

- **ADR:** [ADR-014](../adr/ADR-014-events-identity-resolution.md); amends
  [ADR-007](../adr/ADR-007-auth-clerk-jwt.md); reuses the mechanism from
  [ADR-013](../adr/ADR-013-admin-role-authorization-source.md).
- **Spec files:** `openapi/event-ingestion-service.yaml`,
  `features/event-ingestion/ingest-tracking-event.feature`
- **Backlog item:** PB-8
