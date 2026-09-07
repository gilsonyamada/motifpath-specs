# ADR-007: Clerk Authentication and JWT Local Validation

**Status:** Proposed
**Date:** 2026-05-27
**Deciders:** Gilson Yamada (product/engineering lead)

---

## Context

MotifPath serves two authenticated user types — students and teachers — across a Vue 3 SPA and
multiple Go backend services. Any service that processes user-specific data must verify the
identity of the requester before acting on it.

The authentication layer must satisfy four constraints:

1. **Social login as the primary entry point.** Informal learners and independent teachers have
   low tolerance for registration friction. Email/password forms are a known drop-off point.
   Google OAuth as the sole login method reduces the onboarding surface to a single click.

2. **No per-request network calls to a central auth service.** The Event Ingestion Service will
   receive high-frequency tracking events from the SPA. Calling an external API to validate each
   request would add latency and introduce a hard availability dependency on a third party.

3. **Operationally lightweight for a small team.** Building and operating a custom identity system
   — including session management, token rotation, JWKS rotation, and social provider
   integrations — is out of scope for MVP. A managed solution is required.

4. **Consistent across all services.** The validation mechanism must work identically in every Go
   service without service-specific auth logic.

Alternatives considered:
- **Auth0**: Feature-equivalent managed auth platform. Rejected due to higher cost at equivalent
  feature level, a more complex configuration model, and weaker Vue SDK ergonomics compared to Clerk.
- **Amazon Cognito**: AWS-native identity service. Rejected because it has poor UX customisation,
  high configuration complexity, and would couple the auth layer to AWS infrastructure — undesirable
  given that auth should be infrastructure-agnostic.
- **Custom auth**: Full control over session management, token format, and social login. Rejected
  because building this correctly exceeds the MVP engineering budget and introduces security risk
  that a managed provider eliminates.

## Decision

MotifPath will use **Clerk** as the identity and session management platform. The Vue 3 SPA will
integrate the Clerk JavaScript SDK to handle the full authentication lifecycle: Google OAuth login,
session creation, token refresh, and logout. Backend services will validate Clerk-issued JWTs
locally on every authenticated request.

The following specifics govern the implementation:

- **Login method:** Google OAuth only for MVP, configured as a Clerk social connection. No
  email/password or other providers at launch.
- **Token format:** Clerk issues short-lived session tokens signed with RS256. Services treat these
  as standard Bearer JWTs.
- **Local validation:** Each Go service fetches Clerk's JWKS endpoint at startup, caches the public
  keys in memory, and validates every incoming JWT without outbound network calls. The JWKS cache
  is refreshed every 60 minutes by default and force-refreshed on key-ID miss.
- **Identity claim mapping:** The JWT `sub` claim carries Clerk's internal user ID. At registration
  time, the Core Domain Service maps this `sub` value to the MotifPath `student_id` or `teacher_id`
  and stores it. All subsequent domain operations use the MotifPath ID; the `sub` claim is used
  only for identity verification.
- **Payload identity check:** For endpoints that receive a user-owned payload (e.g., the Event
  Ingestion Service's `POST /events`), the service must verify that the `student_id` in the request
  body matches the identity derived from the JWT `sub` claim. Mismatches are rejected with 401.
- **Token lifetime:** Clerk's default session token lifetime is 60 seconds. This limits the window
  during which a revoked token remains valid.
- **JWKS endpoint:** `https://<clerk-frontend-api>/.well-known/jwks.json`. The Clerk Frontend API
  hostname is injected at deployment time via the `CLERK_JWKS_URL` environment variable.

## Rationale

Clerk is chosen over Auth0 primarily on cost and DX. Auth0's pricing rises sharply past the free
tier, whereas Clerk's free tier is sufficient for the closed alpha and its paid tiers are
cost-competitive at scale. Clerk's Vue and Go SDKs have better documentation and a simpler
integration surface for the MotifPath stack.

Local JWT validation is preferred over per-request API calls because it eliminates the latency
cost and availability dependency of a network call on the hot path. The trade-off — that token
revocation is eventually consistent up to the token lifetime — is acceptable at 60 seconds. If
revocation guarantees become a requirement (e.g., for teacher account suspension), a short-lived
token denylist can be introduced without changing the validation architecture.

Google OAuth only at launch is a deliberate scope constraint. The informal learner and independent
teacher segments have near-universal Google account adoption. Additional providers can be added
through Clerk's dashboard without any backend change.

## Consequences

### Positive
- No auth infrastructure to build, operate, or monitor.
- The Vue SDK handles login, session refresh, and logout with minimal application code.
- Local JWT validation adds zero latency overhead on the service request path.
- A 60-second token lifetime limits the blast radius of a leaked or revoked token.
- JWKS-based validation is a stateless pattern that works identically across all Go services.

### Negative / Trade-offs
- Clerk is a third-party SaaS dependency. A Clerk outage prevents all user authentication.
  There is no offline fallback.
- Token revocation is eventually consistent. A student whose account is suspended can continue
  submitting events for up to 60 seconds after revocation.
- The `sub`-to-`student_id` mapping is a registration-time invariant. If this mapping is lost
  or corrupted, affected users cannot be authenticated to their domain identity.
- Every Go service must import or implement a JWKS-aware JWT validation middleware. This is a
  small repeatable concern that must be kept consistent across services.

### Neutral
- Clerk's pricing model must be reviewed before the platform exits closed alpha. The free tier
  covers development and early testing; production scale requires a paid plan.
- The `CLERK_JWKS_URL` environment variable must be present in every deployment environment
  (local dev, staging, production). Missing it causes service startup failure by design.

## Related ADRs

- ADR-003: Observability — OpenTelemetry + CloudWatch Logs. Auth failures should be captured
  as structured log events and traced via OTel spans for incident diagnosis.
- ADR-004: Deployment pipeline. The `CLERK_JWKS_URL` secret must be provisioned in each
  environment's secret store before deployment.

---

*This ADR was decided on 2026-05-27. To revise, create a new ADR with Status: Supersedes ADR-007.*
