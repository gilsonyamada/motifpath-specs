# Plan: Event Ingestion admin endpoints authorize via Core Domain Service

**Task:** PB-8 (ADR-012 Part 3 reconciliation)
**Date:** 2026-08-27
**Author:** Gilson Yamada
**Status:** In Progress — Phase 1 (spec) and Phase 2 (backend) implemented on their branches; pending review/merge and the Phase 4 infra follow-up

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

- [x] Step 1: In `openapi/event-ingestion-service.yaml`, add a `503` response referencing a new
  `ServiceUnavailableError` schema to both `retryPublishOutboxEntry` and
  `resolvePublishOutboxEntry`.
- [x] Step 2: Update both endpoint descriptions: role is resolved from the Core Domain Service by
  forwarding the caller's bearer token; `403` covers "not admin" and "identity not registered";
  `503` means the Core Domain Service could not be reached to confirm the role. Descriptions kept
  self-sufficient — no "per ADR-013" references (OpenAPI Standards rule).
- [x] Step 3: Wrote `features/event-ingestion/publish-outbox-remediation.feature` — 2 happy path,
  3 edge, 5 authorization-failure scenarios (the admin endpoints had no Gherkin coverage before).
- [x] Step 4: `npx @redocly/cli lint openapi/*.yaml` and `@cucumber/gherkin-streams` both green.

**Definition of Ready check:**
- [x] OpenAPI endpoint(s) defined (503 added, descriptions self-sufficient)
- [x] Gherkin: happy path + ≥2 edge cases + ≥1 failure case (met by Step 3)
- [x] ADR exists — ADR-013

---

### Phase 2 — Backend (motifpath-core)

**Branch:** `feat/PB-8/admin-role-core-domain-authz` (from `dev`)

TDD order per phase: failing test first, then implementation.

- [x] Step 1: `make generate` regenerated `event-ingestion/internal/adapters/http/generated` —
  adds `ServiceUnavailableError` and the two `*PublishOutboxEntry503JSONResponse` types.
- [x] Step 2: `ports.RoleResolver` — `ResolveRole(ctx, bearerToken string) (string, error)` with
  sentinels `ErrIdentityNotRegistered` and `ErrRoleUnavailable`.
- [x] Step 3: `application.AdminAuthorizer.RequireAdmin` is the authorize seam (tests written
  first): `admin` → nil; other role / `ErrIdentityNotRegistered` → `domain.ErrForbidden`;
  `ErrRoleUnavailable` / any other resolver error → `domain.ErrAuthorizationUnavailable`.
  `AdminOutboxService.{RetryEntry,ResolveEntry}` call it before touching outbox state.
- [x] Step 4: `internal/adapters/coredomain/role_resolver.go` — `http.Client` (3s timeout),
  `GET {baseURL}/users/me` with the forwarded bearer token; `200`→role, `404`→
  `ErrIdentityNotRegistered`, `401`/`5xx`/transport/timeout/malformed→`ErrRoleUnavailable`.
  `httptest.Server` unit tests cover every mapping (95.2% coverage).
- [x] Step 5: `admin_handler.go` — 401 when no bearer token in context; maps
  `domain.ErrForbidden`→`403`, `domain.ErrAuthorizationUnavailable`→`503`,
  `domain.ErrOutboxEntryNotFound`→`404`.
- [x] Step 6: `auth_middleware.go` — dropped `roleClaims` / `CustomClaimsConstructor` /
  `WithRole`; captures the raw bearer token via `WithBearerToken`. `context.go` —
  `roleContextKey`→`bearerTokenContextKey`, `WithRole`/`RoleFromContext`→
  `WithBearerToken`/`BearerTokenFromContext`.
- [x] Step 7: `cmd/main.go` — `loadConfig` requires `CORE_DOMAIN_BASE_URL`; constructs
  `coredomain.NewRoleResolver` → `application.NewAdminAuthorizer` → `NewAdminOutboxService`.
- [x] Step 8: BDD — `internal/bdd/steps_admin_test.go` + `fakeRoleResolver` in `world_test.go` +
  registered in `InitializeScenario`. 10 new scenarios, all green (30 total).
- [x] Step 9: `make lint` (0 issues), `make test`, `make test:int`, `make test:bdd` all green.

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
| Should a downstream `401` from `GET /users/me` be surfaced to the caller as `401` or folded into `503`? | Gilson | **Resolved** — folded into `ErrRoleUnavailable`→`503`. The token was validated locally microseconds earlier; a downstream `401` means clock skew or key-rotation timing, i.e. "cannot confirm right now," not "you are unauthenticated." |
| New `ServiceUnavailableError` schema vs reuse of an existing error body? | Gilson | **Resolved** — added a minimal `ServiceUnavailableError` (`{message}` shape, mirrors `ForbiddenError`). |

---

## Related

- **ADR:** [ADR-013](../adr/ADR-013-admin-role-authorization-source.md); supersedes the deferral in
  [ADR-012](../adr/ADR-012-idempotency-delivery-strategy.md) Part 3.
- **Spec files:** `openapi/event-ingestion-service.yaml`,
  `features/event-ingestion/publish-outbox-remediation.feature`
- **Backlog item:** PB-8
