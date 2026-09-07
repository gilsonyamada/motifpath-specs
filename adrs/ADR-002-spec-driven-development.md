# ADR-002: Spec-Driven Development with a Dedicated Spec Repository

Date: 2026-05-17
Status: Accepted

---

## Context

The team evaluated two approaches to managing API contracts and business rule
specifications across four repositories (specs, core, web, infra):

**Option A — Spec-in-repo:** Each service repo owns its OpenAPI spec. The frontend
pins to a published artifact. Business rules are documented in prose or not at all.

**Option B — Dedicated spec repository:** A single repository holds all contracts —
OpenAPI specs, domain event schemas, Gherkin feature files, ADRs, AI prompts, and
evaluation sets. Consuming repositories reference published artifacts.

The core trade-off evaluated:

| Factor | Spec-in-repo | Dedicated repo |
|---|---|---|
| Canonical source of truth | Ambiguous (which repo?) | Unambiguous |
| Spec-first discipline | Cultural only | Structural enforcement |
| PR friction | Low | Higher — cross-repo PR required |
| Version drift detection | Manual | CI-enforced |
| Cross-team parallelism | Harder | Easier (frontend/backend work off same spec) |

PR friction (the primary objection to a dedicated repo) was resolved by adopting
permissive merge policies on the spec repo at MVP: CI must pass, but no required
human reviewer. This preserves the structural discipline without creating bottlenecks
for a small team.

Additionally, the team identified that business rules require their own spec format
beyond what OpenAPI can express. Gherkin (BDD feature files) was selected for this
purpose, executable via `godog` in the Go services. This makes the spec repo the
home of three distinct contract types — API, event, and behavioral — all in one place.

---

## Decision

MotifPath adopts **Spec-Driven Development (SDD)** with a dedicated spec repository
(`motifpath-specs`) as the single source of truth for all platform contracts.

**What lives in motifpath-specs:**
- `/openapi` — REST API specs (OpenAPI 3.1 YAML), validated by Redocly CLI
- `/events` — Domain event schemas (JSON Schema), one file per event
- `/features` — Business rule specs (Gherkin `.feature` files), executed via godog
- `/adrs` — Architecture Decision Records (this file)
- `/prompts` — Versioned AI task prompts with semantic versioning
- `/evals` — Golden sets for PromptFoo prompt evaluation

**Consumption pattern:**
- Go services: spec published as GitHub Release artifact → `oapi-codegen` generates
  server stubs → committed generated code fails CI if it drifts from the spec
- Vue frontend: spec published as artifact → `openapi-typescript` generates types →
  same drift detection via committed generated types
- Consuming repos explicitly bump the spec version — no automatic propagation at MVP

**Definition of Ready:**
A feature is not ready for development until its spec exists and meets all criteria
defined in `motifpath-specs/README.md`. This is enforced by team convention,
not tooling, at MVP.

---

## Consequences

**Positive:**
- Single unambiguous canonical source of truth for all contracts
- Spec changes are visible, reviewable, and versioned independently of implementation
- Frontend and backend can work in parallel against the same published spec
- Gherkin feature files are executable via godog — the spec becomes the test,
  preventing documentation drift
- AI-assisted spec generation (Gherkin, OpenAPI) is centralized with versioned prompts
  and PromptFoo evaluation — prompt changes are reviewable like code changes

**Negative:**
- Every spec change requires a PR in a separate repository before implementation begins
- Cross-repo CI dependency: `motifpath-core` checks out `motifpath-specs` during BDD tests
- Consuming repos must explicitly update the pinned spec version — no automatic propagation

**Future:**
- When a second API consumer exists (mobile app, partner integration), the dedicated
  spec repo pays additional dividends with no structural change required
- Strict PR review policies (required reviewers) can be added to the spec repo
  when team size justifies it, without changing the underlying architecture
- PromptFoo eval pipeline can be extended to cover additional AI tasks as the
  prompt library grows

**Does not supersede:** Nothing — this is the first architectural decision recorded.
