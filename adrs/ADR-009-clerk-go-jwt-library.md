# ADR-009: Clerk Go SDK for JWT Local Validation

**Status:** Proposed
**Date:** 2026-06-12
**Deciders:** Gilson Yamada (product/engineering lead)

---

## Context

ADR-007 decided that all Go backend services validate Clerk-issued JWTs locally — no per-request
network call to Clerk. The decision specified the validation behaviour in detail: fetch the JWKS
endpoint at startup, cache public keys in memory, validate every incoming Bearer token against
those keys, refresh the cache every 60 minutes, and force-refresh on a key-ID miss.

ADR-007 did not specify which Go library implements this behaviour. That decision is deferred to
this ADR because it affects every service in `motifpath-core` and creates a long-term dependency.

Three options were considered:

1. **`github.com/clerkinc/clerk-sdk-go/v2`** — Clerk's official Go SDK. Includes a `jwt.Verify()`
   function backed by a built-in JWKS-aware HTTP client. Handles key fetching, in-memory caching,
   TTL-based refresh, and key-ID miss recovery automatically.

2. **`github.com/golang-jwt/jwt/v5` + manual JWKS fetch** — A widely-used low-level JWT library.
   Parses and validates signed tokens but has no JWKS support. The JWKS fetch, cache, rotation
   logic, and key-ID miss handling would all be hand-written.

3. **`github.com/lestrrat-go/jwx/v2`** — A comprehensive JOSE/JWT library with built-in JWKS
   fetching and automatic key refresh. Provider-agnostic; not Clerk-specific.

## Decision

MotifPath will use **`github.com/clerkinc/clerk-sdk-go/v2`** for JWT local validation in all Go
backend services.

Each service instantiates a single `clerk.Client` at startup, injected as a dependency into the
HTTP middleware layer. The middleware calls `clerk.VerifyToken()` on every authenticated request,
extracts the `sub` claim, and attaches the resolved identity to the request context. No service
implements its own JWKS fetch or cache logic.

## Rationale

The Clerk SDK satisfies every requirement from ADR-007 without custom code: JWKS fetching,
in-memory caching with configurable TTL, and key-ID miss recovery are all built in and tested by
Clerk's own team. The operational risk of getting cache invalidation or key rotation wrong is
shifted to the SDK maintainer.

`golang-jwt/jwt/v5` was rejected because it requires hand-writing the JWKS layer. The JWKS cache
and rotation logic are non-trivial to get right and introduce a class of subtle bugs (stale keys,
thundering herd on rotation, missed key-ID) that the Clerk SDK already solves. The control gained
is not worth the implementation and maintenance cost at MVP.

`lestrrat-go/jwx/v2` is a well-engineered library and a reasonable alternative. It was rejected
on pragmatic grounds: it is provider-agnostic, which means integration still requires reading
Clerk's JWKS URL convention, interpreting Clerk-specific claims, and writing the middleware
manually. The Clerk SDK does all of this out of the box for the same dependency weight.

## Consequences

### Positive
- Zero custom JWKS or key-rotation code across the entire `motifpath-core` monorepo.
- Behaviour is consistent with ADR-007 by construction — the SDK implements exactly the refresh
  and miss-recovery semantics described there.
- The Clerk SDK is maintained by Clerk, so updates to Clerk's JWKS conventions are absorbed
  without changes to service code.

### Negative / Trade-offs
- `motifpath-core` is coupled to Clerk's Go SDK. Migrating away from Clerk requires replacing
  this library in every service simultaneously.
- The Clerk SDK pulls in the full Clerk API client, which is broader than what backend services
  need. Only the JWT validation subset is used; the rest is unused dependency surface.
- SDK updates may introduce breaking changes in the `jwt` package. This is mitigated by pinning
  the version in `go.mod` and reviewing Clerk's changelog on each bump.

### Neutral
- The `CLERK_JWKS_URL` environment variable requirement (from ADR-007) remains unchanged.
- The middleware pattern — one `clerk.Client` per service, injected as a dependency — applies
  identically to the Event Ingestion Service and the Core Domain Service.

## Related ADRs

- ADR-007: Clerk Authentication and JWT Local Validation — this ADR implements the Go-level
  tooling decision deferred by ADR-007.
- ADR-004: Deployment pipeline — `CLERK_JWKS_URL` must be provisioned in every deployment
  environment before the service starts.

---

*This ADR was decided on 2026-06-12. To revise, create a new ADR with Status: Supersedes ADR-009.*
