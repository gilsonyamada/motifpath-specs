# ADR-013: Event Ingestion Service Resolves Admin Role from Core Domain Service

**Status:** Accepted
**Date:** 2026-08-27
**Deciders:** Gilson Yamada (product/engineering lead)

---

## Context

ADR-012 Part 3 added two admin-only endpoints to the Event Ingestion Service —
`POST /admin/publish-outbox/{event_id}/retry` and `POST /admin/publish-outbox/{event_id}/resolve` —
that let an operator act on a dead-lettered Kafka publish. Both gate on the caller carrying an
`admin` role. At the time ADR-012 was decided, the Core Domain Service did not exist, so there was
nowhere authoritative to look up a user's role. ADR-012 took the only option available: read a
`role` custom claim straight from the already-validated Clerk JWT, and it explicitly booked the
resulting divergence as debt — "once Phase 4 ships, role exists in two places that are not
automatically kept in sync ... reconciling them (or migrating these endpoints to check Core Domain
Service instead) is a follow-up this ADR does not resolve."

Phase 4 has now shipped (`motifpath-core` PR #5). The Core Domain Service owns `User.role` as a
Postgres-backed `ent` enum (`student | teacher | admin`) and resolves it per request from the
caller's Clerk identity, exposing it on `GET /users/me` via the `UserProfile.role` field. Its own
HTTP middleware reads only the JWT `sub` claim and looks role up from the `User` record — it never
trusts a role claim from the token.

The Event Ingestion Service is now the only place in the platform that still derives authorization
role from a JWT claim. That claim has to be configured in Clerk's JWT template and kept in step
with the domain model by hand; nothing enforces that the two agree. On endpoints that mutate
delivery state for real student data, a stale or mis-configured claim is an authorization-
correctness risk, not a cosmetic inconsistency. This ADR closes ADR-012's deferred follow-up by
deciding where the Event Ingestion Service reads role from.

Alternatives considered at a high level: keep the claim but make the Core Domain Service push role
into Clerk user metadata so the claim stays authoritative; add a dedicated internal
service-to-service endpoint on the Core Domain Service behind its own credential; give the Event
Ingestion Service a direct read of the Core Domain Service's `User` table via a shared library;
extract identity into a standalone service so the Event Ingestion Service depends on it rather
than on the Core Domain Service.

## Decision

The Event Ingestion Service will stop reading role from the JWT. On a request to either admin
endpoint, after it has locally validated the bearer token (ADR-007 / ADR-009), it will make a
server-to-server call to the platform's **identity/authorization capability** — today served by
the Core Domain Service at `GET /users/me` — forwarding the caller's bearer token verbatim in the
`Authorization` header, and authorize on the `role` field of the `200` response. That capability
is the single source of truth for role. This ADR names the Core Domain Service as its current
host, not as a permanent binding: if identity is later extracted into its own service, this
decision holds unchanged and only the Event Ingestion Service's `CORE_DOMAIN_BASE_URL` target
moves.

Outcome mapping for the admin endpoints:

| Core Domain Service response | Event Ingestion Service behavior |
|---|---|
| `200`, `role == "admin"` | Proceed with the operation |
| `200`, `role != "admin"` | `403` — admin role required |
| `404` (Clerk identity never registered) | `403` — admin role required |
| `401` (token rejected downstream, e.g. key rotation / clock skew) | `401` — passed through to the caller |
| unreachable, timeout, or `5xx` | Fail closed: `503`, with a structured error log |

Specifics:

- **New config:** `CORE_DOMAIN_BASE_URL` in the Event Ingestion Service's environment. The call
  uses a short timeout (3s) and no retry — the caller is an operator who can re-issue the request.
- **No caching** of the role lookup at MVP. Admin calls are rare and operator-initiated; caching a
  security-sensitive check trades role-revocation freshness for a round-trip that does not matter
  at this volume.
- **`/events` is untouched.** The tracking-event ingestion path gains no Core Domain Service
  dependency. Only the two admin endpoints make the call.
- **Middleware simplification:** the Event Ingestion Service's `ClerkAuthMiddleware` drops its
  `role` custom-claims constructor and the `WithRole` / `RoleFromContext` plumbing, returning to a
  `sub`-only middleware that matches the Core Domain Service's.
- **Single authorization seam:** both admin handlers gate through one `authorizeAdmin(ctx)`
  function rather than an inline `role == "admin"` string comparison, so the check has exactly one
  place to evolve when role gives way to a permission or group model.
- **Spec changes (follow-up, not part of this ADR):** `openapi/event-ingestion-service.yaml` adds
  a `503` response to both admin endpoints and updates their descriptions to state role is
  resolved from the Core Domain Service; `features/event-ingestion/` gains scenarios covering
  admin / non-admin / unregistered / Core-Domain-unavailable. `openapi/core-domain-service.yaml`
  needs no change — `GET /users/me` already returns `role`.

## Rationale

**Resolve from the Core Domain Service over keeping the claim authoritative via Clerk metadata.**
`role` is immutable through the API and `admin` is provisioned only by a direct database write, so
the claim could instead be populated from Clerk user metadata that the Core Domain Service (or an
operator) keeps in step with that database. This keeps the claim but makes Clerk a write target
for domain data, adds a Clerk Backend API call and failure mode wherever role is granted, and —
worst for a security check — leaves an already-issued token carrying the old value until it
refreshes, so a just-revoked `admin` still works until the session rotates. It also still keeps
two copies of role; it just adds a sync job between them. Reading from the Core Domain Service on
demand has one copy and no propagation lag.

**Forward the caller's own token to `GET /users/me` over a dedicated internal endpoint.** A
purpose-built `GET /internal/users/{id}` behind mTLS or a shared secret would work, but it
introduces a service-to-service authentication scheme that exists nowhere else in the platform
yet, for a single caller hitting a single rare path. `GET /users/me` already returns exactly the
field needed and already accepts the caller's Clerk JWT. Forwarding the user's own token adds no
new credential to store, rotate, or leak. If internal endpoints proliferate later, a real
service-to-service auth story deserves its own ADR then.

**An HTTP call over a shared library reading the `User` table.** A shared Go module that reads
role would still need either a direct connection to the Core Domain Service's Postgres database —
breaking service data-ownership boundaries — or an endpoint underneath it, which is the option
above. Neither is simpler than one HTTP call to an endpoint that already exists.

**Fail closed on a Core Domain Service outage.** These endpoints can change delivery state for
real student data. If role cannot be confirmed, the safe answer is to deny. The cost is that
outbox remediation is unavailable while the Core Domain Service is down — acceptable, because a
dead-lettered entry is already in a non-urgent state by definition, and the alternative
(fail open, or fall back to the JWT claim) reintroduces exactly the trust problem this ADR
removes.

**Extracting a standalone identity service was rejected for now — and is not what this problem
calls for.** A dedicated service does not remove the Event Ingestion Service's dependency; it
relocates it to a different box answering the same call, with the same failure modes. Meanwhile
`User` is heavily referenced across the learning domain (path assignments, content ownership,
caller resolution on every endpoint), so extracting it would turn those references into network
hops or denormalized copies for a second deployable, database, and pipeline — disproportionate at
MVP scale. Identity is already a clean module inside the Core Domain Service (`IdentityService`,
the `User` aggregate, `/users` and `/users/me`); that is the seam to extract along if and when
identity grows its own substantial logic (organizations, SSO, invitations, billing identity) or a
second consumer needs rich user data. This ADR is written so that extraction, when it happens, is
a configuration change rather than a superseding decision.

**Do nothing was rejected.** ADR-012 already recorded this as debt. The divergence is a genuine
authorization risk: `admin` is granted by a direct database write, and nothing makes the Clerk
JWT template's `role` claim follow it — an `admin` in the database with no matching claim cannot
use the endpoints, and a stale `admin` claim left after a database grant is removed still can.
This is also the last claim-derived authorization decision left in the platform.

## Consequences

### Positive

- One source of truth for role: the Core Domain Service's `User.role`. No Clerk JWT template
  configuration to maintain or reconcile for authorization purposes.
- The Event Ingestion Service's auth middleware returns to `sub`-only, identical in shape to the
  Core Domain Service's — one fewer divergence between the two services.
- No new authentication scheme, no new endpoint, no new credential. The mechanism (validate token
  locally, forward it to `GET /users/me`, read `role`) is reusable by any future service that
  needs the caller's role.
- Closes the negative consequence ADR-012 booked ("role exists in two places that are not
  automatically kept in sync").

### Negative / Trade-offs

- The admin endpoints now have a runtime dependency on the Core Domain Service being reachable.
  Contained: they are rare, operator-initiated, and off the hot path; `/events` ingestion is
  unaffected.
- An authorization decision that was a local claim read is now a network round-trip, with the
  failure surface that implies (timeouts, partial failures). The fail-closed policy bounds the
  security risk but lowers the availability of outbox remediation during a Core Domain Service
  outage.
- A new `503` outcome on both admin endpoints. Operators must learn that a failed remediation call
  can mean "Core Domain Service is unhealthy," not "the outbox entry is bad."
- Every admin call pays the round-trip; there is no cache. Fine at MVP volume, revisit only if
  admin traffic ever becomes non-trivial.
- Adds `CORE_DOMAIN_BASE_URL` to the Event Ingestion Service's deployment configuration
  (`motifpath-infra`).

### Neutral

- Role is expected to evolve — more roles, access groups, or per-group feature entitlements. This
  ADR accommodates that: the resolution endpoint (`GET /users/me` or a successor such as
  `GET /users/me/permissions`) is the extension seam, the payload grows, and the
  `authorizeAdmin(ctx)` seam localizes the check. What this ADR explicitly does **not** cover is
  **hot-path** entitlement enforcement — a per-request authorization check on a high-volume
  endpoint like `/events`. The rare, operator-initiated admin path tolerates an uncached network
  round-trip; a hot path would not, and would need its own decision (short-TTL token claims, a
  cache, or an event-driven local replica). That is a separate ADR if and when the need arises.
- The parallel gap in the Event Ingestion Service — using the JWT `sub` claim directly as
  `student_id` instead of resolving it through the Core Domain Service (ADR-007's known
  limitation) — is **not** resolved here, even though the same `GET /users/me` response now also
  carries the caller's MotifPath `user_id`. Wiring `/events` to use it is a separate change with
  its own scenarios.
- ADR-012 Part 2 is unchanged: the `publish_outbox` collection shape, the retry sweep, and the
  dead-letter status all stay exactly as specified. Only the authorization mechanism on the two
  Part 3 admin endpoints changes.
- `GET /users/me` on the Core Domain Service needs no modification — it already returns `role`.

## Related ADRs

- **ADR-012: Idempotency and delivery-guarantee strategy for the tracking-event pipeline** — added
  the admin endpoints and the JWT-claim role check as acknowledged debt; this ADR resolves the
  Part 3 follow-up it deferred and closes its "role in two places" negative consequence.
- **ADR-007: Clerk authentication and JWT local validation** — each service still validates the
  bearer token independently; the Event Ingestion Service forwards the same token it already
  validated to the Core Domain Service, which validates it again on its side.
- **ADR-009: Clerk Go SDK for JWT local validation** — the local-validation step that runs before
  the `GET /users/me` call is unchanged; only the role-resolution step after it changes.
- **ADR-006: Kafka topology — single topic, student_id partition, MSK** — unrelated to the
  decision, but the admin endpoints exist to remediate this pipeline's producer-side delivery
  failures.

---

*This ADR was decided on 2026-08-27. To revise, create a new ADR with Status: Supersedes ADR-013.*
