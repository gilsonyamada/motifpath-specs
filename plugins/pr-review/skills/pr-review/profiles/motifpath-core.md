# Profile: motifpath-core

## Identification

- Repository / path scope: `motifpath/motifpath-core` — monorepo, both `services/core-domain/` and
  `services/event-ingestion/` (see `profiles/ROUTING.md`).
- Local reference repo: `motifpath-core` checkout, root `Makefile` / `devbox.json` / `.golangci.yml`
  for shared tooling.
- Comment language: English.
- Stack in one line: Go, hexagonal architecture, Postgres (core-domain, via `ent`), MongoDB Atlas
  (event-ingestion), oapi-codegen, clerk-sdk-go/v2.

## Sources of intent

- Spec: OpenAPI paths in `motifpath-specs/openapi/` are the source of truth for every HTTP contract;
  event shapes in `motifpath-specs/openapi/components/schemas/events.yaml`.
  (`motifpath-core/CLAUDE.md` — Spec-Driven Development)
- Gherkin scenarios: `motifpath-specs/features/*.feature`, run via `godog` (`make test:bdd`).
- Backlog item: task code in the branch name (`feat/MTP-NNN/...`), per the `git` skill.
- Fallback: ask the user for the activity's context.

## Local norms (with evidence)

| Norm | Evidence |
|---|---|
| Hexagonal layering: `internal/domain` (zero deps) → `internal/application` (use cases) → `internal/ports` (interfaces) → `internal/adapters/{http,repo}` | `motifpath-core/CLAUDE.md` — Hexagonal Architecture |
| Business logic never lives in HTTP handlers; handlers call application services only | `motifpath-core/CLAUDE.md` — Layering Rules |
| Dependency direction is inward — domain/application never import adapter packages | `motifpath-core/CLAUDE.md` — Layering Rules |
| Domain events are emitted only from the application layer, never adapters/handlers | `motifpath-core/CLAUDE.md` — Layering Rules |
| `ThresholdOverride` takes precedence over a `Node`'s default threshold, applied in the application layer | `motifpath-core/CLAUDE.md` — Domain Model |
| `internal/adapters/http/generated/` is oapi-codegen output — never hand-edited; regenerate via `make generate` | `motifpath-core/CLAUDE.md` — Spec-Driven Development |
| No cross-service Go package imports between `services/core-domain` and `services/event-ingestion`; shared code (if any) lives in root `shared/` and must stay non-domain-specific | `motifpath-core/CLAUDE.md` — Monorepo Boundaries |
| JWT validation goes through one `clerk.Client` per service via `clerk-sdk-go/v2` — no custom JWKS fetch/cache logic (ADR-009) | `motifpath-core/CLAUDE.md` — Auth |
| Errors are always handled explicitly — never a blank `_` on an error return; no `interface{}`/`any` | `motifpath-core/CLAUDE.md` — Code Quality |

## Boundaries

- **Public contract:** any HTTP handler shape or event schema field — breaking either requires an
  OpenAPI/event-schema version bump in `motifpath-specs` first (Spec-Driven Development).
- **Tolerated legacy:** none documented yet — ask the user before treating anything as
  grandfathered.
- **Automatic gates (don't re-flag):** `golangci-lint` via the committed `.golangci.yml`
  (`make lint`); the 80% coverage gate on `internal/application/` packages; `//nolint` without an
  inline reason is already a lint-time concern, but confirm the reason is *specific*, not generic,
  since the linter only checks presence, not quality.

## Tests

- Live at the service layer only: `internal/application/`. (`motifpath-core/CLAUDE.md` — Testing
  Discipline)
- Table-driven, `testify`, one test function per feature, one row per scenario.
- Database tests use `testcontainers` — mocking the repository layer is explicitly disallowed, so a
  test that only manipulates a mocked repo is itself a finding (Axis E, item 18).
- Gherkin scenarios from `motifpath-specs/features/` run via `godog`, `make test:bdd`.
- Naming: describe the behavior under test, never a ticket ID or incident number.

## Delivery

- Feature/fix/chore branches target `dev`; only `hotfix/BUG-NNN/...` branches from `main` directly.
  (`motifpath-core/CLAUDE.md` — Branching, mirrors the `git` skill)
- `make generate` (API stubs) and `make migrate:diff` (Atlas migration from `ent` schema diff,
  ADR-010) are separate commits from business logic, per the `git` skill's atomic-commit rule.

## Bootstrap notes

Seeded from `motifpath-core/CLAUDE.md` on 2026-08-25 — not yet confirmed against a live review. On
first real review in this repo, walk the Bootstrap steps in `_TEMPLATE.md` (read 2–3 files per
layer, read a mature module's tests, check recent merge history) and update this table with any
divergence between the documented and the practiced pattern.
