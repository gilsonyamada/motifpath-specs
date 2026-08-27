# Plan: Event Ingestion admin endpoints authorize via Core Domain Service

**Task:** PB-8 (ADR-012 Part 3 reconciliation)
**Date:** 2026-08-27
**Author:** Gilson Yamada
**Status:** Draft

---

## Goal

Make the Event Ingestion Service's two `publish_outbox` admin endpoints authorize the caller's
`admin` role by asking the Core Domain Service (`GET /users/me`) instead of trusting a Clerk JWT
`role` claim, per ADR-013. This pays down the debt ADR-012 Part 3 explicitly deferred.

## Scope

**In scope:**
- OpenAPI: `503` response + description updates on both admin endpoints in
  `openapi/event-ingestion-service.yaml`.
- Gherkin: a new `features/event-ingestion/publish-outbox-remediation.feature` covering the two
  admin endpoints, including the ADR-013 authorization outcomes.
- `motifpath-core`: a role-resolution port + Core Domain Service HTTP adapter in the Event
  Ingestion Service; `authorizeAdmin(ctx)` seam in the admin handler; removal of the `role`
  custom-claim plumbing; `CORE_DOMAIN_BASE_URL` config; unit + integration + BDD tests.

**Out of scope:**
- The `sub`→`student_id` resolution gap on `/events` (ADR-007's known limitation). ADR-013
  Neutral section — separate change, separate scenarios.
- Any change to the Core Domain Service. `GET /users/me` already returns `role`.
- Caching, retries, or a shared service-to-service auth scheme (ADR-013 rejected all three for
  MVP).
- `motifpath-infra` wiring of `CORE_DOMAIN_BASE_URL` — tracked as a follow-up infra task; the
  service must fail to start without it, which is the safety net until infra lands.

## Prerequisites

- [ ] ADR-013 merged to `motifpath-specs` `main` (Status: Accepted).
- [x] Core Domain Service `GET /users/me` returns `UserProfile.role` (Phase 4, `motifpath-core` PR #5).
- [x] Event Ingestion admin endpoints + `publish_outbox` exist (`motifpath-core` PR #4).

---

## Implementation Steps

### Phase 1 — Spec (motifpath-specs)

**Branch:** `adr/PB-8/013-admin-role-via-core-domain` (same branch as ADR-013 — one specs PR for the whole decision)

- [ ] Step 1: In `openapi/event-ingestion-service.yaml`, add a `503` response referencing a new
  `ServiceUnavailableError` schema (or reuse an existing error shape) to both
  `retryPublishOutboxEntry` and `resolvePublishOutboxEntry`.
- [ ] Step 2: Update both endpoint descriptions: role is resolved from the Core Domain Service by
  forwarding the caller's bearer token; `403` covers "not admin" and "identity not registered";
  `503` means the Core Domain Service could not be reached to confirm the role. Keep descriptions
  self-sufficient — no "per ADR-013" references (OpenAPI Standards rule).
- [ ] Step 3: Write `features/event-ingestion/publish-outbox-remediation.feature`:
  - Happy path: an admin retries a dead-lettered entry and it publishes; an admin resolves a
    dead-lettered entry with a reason.
  - Edge: retry/resolve on an already-terminal entry is a no-op returning current state; resolve
    without a reason is accepted.
  - Failure: a caller whose role is not admin is refused; a caller with no registered MotifPath
    identity is refused; the role cannot be confirmed because the Core Domain Service is
    unavailable → remediation is refused as temporarily unavailable; missing token is refused.
- [ ] Step 4: `make -C ../motifpath-core generate` dry-run equivalent — bundle + lint the spec
  (`npx @redocly/cli lint openapi/event-ingestion-service.yaml`) so CI's OpenAPI check will pass.

**Definition of Ready check:**
- [ ] OpenAPI endpoint(s) defined (503 added, descriptions self-sufficient)
- [ ] Gherkin: happy path + ≥2 edge cases + ≥1 failure case (met by Step 3)
- [ ] ADR exists — ADR-013

---

### Phase 2 — Backend (motifpath-core)

**Branch:** `feat/PB-8/admin-role-core-domain-authz` (from `dev`)

TDD order per phase: failing test first, then implementation.

- [ ] Step 1: `make generate` to regenerate `event-ingestion/internal/adapters/http/generated`
  from the updated spec (adds the `503` response type to both admin operations).
- [ ] Step 2: Define `ports.RoleResolver` — `ResolveRole(ctx, bearerToken string) (role string, err error)`
  with sentinel errors `ErrIdentityNotRegistered` and `ErrRoleUnavailable`. Write the port's
  contract test expectations into the admin service tests first.
- [ ] Step 3: `application.AdminOutboxService` (or a thin `Authorizer`) gains an `authorize` step
  that calls `RoleResolver`. Unit tests with a fake resolver:
  - role `admin` → operation proceeds
  - role `student`/`teacher` → `domain.ErrForbidden`
  - `ErrIdentityNotRegistered` → `domain.ErrForbidden`
  - `ErrRoleUnavailable` → a new `domain.ErrAuthorizationUnavailable`
  Write these tests before touching the service.
- [ ] Step 4: HTTP adapter `internal/adapters/coredomain/role_resolver.go` — an `http.Client`
  with a 3s timeout, `GET {baseURL}/users/me` with `Authorization: Bearer <token>`, decode
  `{"role": "..."}`; map `200`→role, `404`→`ErrIdentityNotRegistered`, `401`→`ErrRoleUnavailable`
  (token unexpectedly rejected downstream — treat as cannot-confirm), everything else / transport
  error / timeout → `ErrRoleUnavailable`. Testcontainers or `httptest.Server` integration test
  covering each mapping.
- [ ] Step 5: `internal/adapters/http/admin_handler.go` — replace `isAdmin(ctx)` string check
  with `authorizeAdmin(ctx)` that runs the application authorize step; map
  `domain.ErrForbidden`→`403`, `domain.ErrAuthorizationUnavailable`→`503`. The bearer token must
  reach the handler — capture it in `ClerkAuthMiddleware` via `WithBearerToken(ctx, raw)` (new,
  replacing `WithRole`).
- [ ] Step 6: `internal/adapters/http/auth_middleware.go` — drop `roleClaims`,
  `CustomClaimsConstructor`, `WithRole`; keep `sub` via `WithStudentID`; add `WithBearerToken`.
  `internal/adapters/http/context.go` — remove `roleContextKey`/`WithRole`/`RoleFromContext`,
  add `bearerTokenContextKey`/`WithBearerToken`/`BearerTokenFromContext`.
- [ ] Step 7: `cmd/main.go` — `loadConfig` requires `CORE_DOMAIN_BASE_URL` (via `mustGetenv`);
  construct the `coredomain.RoleResolver` and inject it into `AdminOutboxService` /
  `NewHandler`.
- [ ] Step 8: BDD — `internal/bdd/steps_admin_test.go` + register in `InitializeScenario`.
  Add a `fakeRoleResolver` to `world_test.go` with settable role / error; steps for "an admin
  operator", "a non-admin user", "an unregistered caller", "the Core Domain Service is
  unavailable", and the retry/resolve When/Then steps. Wire `publish-outbox-remediation.feature`.
- [ ] Step 9: `make lint test test:int test:bdd` all green.

**Coverage gate:** 80% on `services/event-ingestion/internal/application/` — CI fails below this.

---

### Phase 3 — Frontend (motifpath-web)

Not applicable — no student- or teacher-facing surface. Admin remediation is operator-only.

### Phase 4 — Infrastructure (motifpath-infra)

Follow-up task (separate branch/PR): add `CORE_DOMAIN_BASE_URL` to the Event Ingestion Service's
EKS task definition / Helm values, pointing at the Core Domain Service's in-cluster address.
Until then the service fails fast on startup without it — acceptable, and the safer default.

---

## Rollback Plan

The Event Ingestion Service is a stateless HTTP service on EKS blue/green (ADR-004). Rollback =
redeploy the previous image. No data migration: `publish_outbox` is unchanged by this work. If
the Core Domain Service dependency proves too fragile in practice, the rollback image restores
the JWT-claim check; ADR-013 would then need a superseding ADR to record the reversal.

## Validation

- [ ] An operator whose Core Domain `role` is `admin` can retry and resolve a dead-lettered
  `publish_outbox` entry; the entry reaches `published` / `resolved_manually`.
- [ ] A caller whose Core Domain `role` is `student` or `teacher` receives `403` from both admin
  endpoints, regardless of any `role` claim in their JWT.
- [ ] With the Core Domain Service stopped, both admin endpoints return `503` (not `403`, not a
  publish) and emit a structured error log.
- [ ] `/events` ingestion succeeds with the Core Domain Service stopped — no new dependency on
  the hot path.
- [ ] `grep -r "roleClaims\|WithRole\|RoleFromContext" services/event-ingestion` returns nothing.
- [ ] The service refuses to start when `CORE_DOMAIN_BASE_URL` is unset.

---

## Open Questions

| Question | Owner | Resolution |
|---|---|---|
| Should a downstream `401` from `GET /users/me` be surfaced to the caller as `401` or folded into `503`? | Gilson | **Proposed:** fold into `ErrRoleUnavailable`→`503`. The token was already validated locally microseconds earlier; a downstream `401` means clock skew or key-rotation timing, i.e. "cannot confirm right now," not "you are unauthenticated." Revisit if it proves confusing in logs. |
| New `ServiceUnavailableError` schema vs reuse of an existing error body? | Gilson | Open — decide during Phase 1 Step 1. Leaning toward a minimal new schema mirroring `ForbiddenError` for a consistent `{message}` shape. |

---

## Related

- **ADR:** [ADR-013](../adr/ADR-013-admin-role-authorization-source.md); supersedes the deferral in
  [ADR-012](../adr/ADR-012-idempotency-delivery-strategy.md) Part 3.
- **Spec files:** `openapi/event-ingestion-service.yaml`,
  `features/event-ingestion/publish-outbox-remediation.feature`
- **Backlog item:** PB-8
