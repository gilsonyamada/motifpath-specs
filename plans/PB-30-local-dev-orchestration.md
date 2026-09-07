# Plan: Local Dev Orchestration & Release-Image Smoke

**Task:** PB-30
**Date:** 2026-09-07
**Author:** Gilson Yamada
**Status:** Ready

---

## Goal

Give MotifPath a one-command local full stack for manual smoke testing and an
automated boot-and-serve check for the three service Docker images in CI,
implementing ADR-016. Fold in the `core-domain` and `aggregation-worker` health
endpoints that ADR-016 identified as a shared prerequisite.

## Scope

**In scope:**

- ADR-016 (committed with this plan).
- `core-domain` OpenAPI: `GET /healthz` + `GET /readyz`, mirroring
  `event-ingestion`; Gherkin scenarios; Go implementation + tests.
- `aggregation-worker`: minimal HTTP health server (`/healthz` + `/readyz`) +
  tests.
- `motifpath-core`: `process-compose.yaml` (inner-loop + full-stack profiles),
  `compose.images.yaml`, per-service `.env.example`, a `image-smoke` CI job,
  README updates.
- `motifpath-web`: `.env.example` already exists — document the process-compose
  entry and confirm the keys.

**Out of scope:**

- Production deployment / hosting — PB-8a (on hold). No `motifpath-infra` change.
- A production-shaped full-stack `docker-compose.yml` running the services —
  deferred to PB-8a per ADR-016 §6.
- k3d / Tilt / Skaffold — deferred with the EKS path per ADR-016 §6.
- Browser E2E tests (Playwright/etc.) — out of MVP scope; ADR-016 §7 records the
  seam a future suite plugs into (`full-stack` profile / `compose.images.yaml`,
  `/readyz` gate, `CLERK_SECRET_KEY` in the §5 contract) and what it adds
  (Playwright, state seeding, `build && preview` over `dev`).
- Web containerization — it ships as static assets (ADR-004).
- ECR image-retention lifecycle policy — noted in ADR-016, tracked with PB-8a.
- `aggregation-worker` readiness reflecting Kafka **consumer-group membership** —
  v1 readiness is broker reachability + MongoDB; membership is a later refinement.

## Prerequisites

- [x] ADR-016 reviewed and set to Accepted (2026-09-07).
- [ ] Devbox `devbox.json` already provides `go`, `atlas`, `nodejs` — confirm
      `process-compose` resolves via `devbox services` (bundled) and add `wgo` to
      `devbox.json` packages.
- [ ] Docker available locally and on the GitHub Actions runner (it is —
      `test-integration` already uses testcontainers).

---

## Implementation Steps

### Phase 1 — Spec (motifpath-specs)

**Branch:** `feat/PB-30/adr-016-local-dev-orchestration` (this branch)

- [ ] Step 1: Commit `adrs/ADR-016-local-dev-orchestration-and-image-smoke.md`
      and this plan.
- [ ] Step 2: In `openapi/core-domain-service.yaml`, add `/healthz`
      (`operationId: livenessCheck`) and `/readyz` (`operationId: readinessCheck`,
      200 + 503), `security: []`, `tags: [Operations]` — copy the shape verbatim
      from `openapi/event-ingestion-service.yaml`.
- [ ] Step 3: Extract the `HealthStatus` schema from `event-ingestion-service.yaml`
      into `openapi/components/schemas/health.yaml` and `$ref` it from **both**
      service documents (Q1 resolved — shared file, matching how `events.yaml`
      schemas are already shared). Confirm `@redocly/cli bundle` resolves the
      cross-file `$ref` at `make generate` time in `motifpath-core`.
- [ ] Step 4: Write `features/core-domain/service-health.feature` — domain
      language only, no status codes (per specs CLAUDE.md):
  - the liveness probe reports the service is running (happy)
  - the readiness probe reports ready when the learning-graph store and the
    completion-state store are both reachable (happy)
  - the readiness probe reports not-ready, naming the learning-graph store, when
    it is unreachable (failure)
  - the readiness probe reports not-ready, naming the completion-state store,
    when it is unreachable (edge)
  - the readiness probe reports not-ready when both stores are unreachable (edge)
  - the readiness probe returns to ready once an unreachable store recovers (edge)

**Definition of Ready check:**

- [ ] `/healthz` + `/readyz` defined in `core-domain-service.yaml`, referencing
      the shared `HealthStatus` schema.
- [ ] Gherkin: 2 happy + 3 edge + 1 failure (meets "happy + 2 edge + 1 failure").
- [x] ADR-016 Accepted (2026-09-07).

---

### Phase 2 — core-domain health endpoints (motifpath-core)

**Branch:** `feat/PB-30/core-domain-health-endpoints`

- [ ] Step 1: `make generate` — regenerate `internal/adapters/http/generated/`
      from the updated bundled spec. Confirm `LivenessCheck` / `ReadinessCheck`
      request/response types appear.
- [ ] Step 2 (test first): add a `ports.Pinger` interface to `core-domain`
      (mirror `event-ingestion/internal/ports`), and write table-driven tests in
      `internal/adapters/http` for a `ReadinessCheck` handler using fake pingers
      — 200 all-ok, 503 postgres-fail, 503 mongo-fail, per-check map asserted.
      Add the liveness test (always 200).
- [ ] Step 3: implement `LivenessCheck` / `ReadinessCheck` on the `core-domain`
      HTTP handler; extend `NewHandler(...)` to take `postgresPinger,
      mongoPinger ports.Pinger`.
- [ ] Step 4: implement the two pingers in `internal/adapters/repo` — Postgres
      via `db.PingContext` on the `ent` driver's underlying `*sql.DB`, MongoDB via
      `client.Ping`. Unit-test the adapters against testcontainers (reuse the
      PB-29 shared-container harness).
- [ ] Step 5: wire both pingers in `cmd/main.go`; register `/healthz` + `/readyz`
      on the router **outside** `ClerkAuthMiddleware` (they are `security: []`).
- [ ] Step 6: godog step definitions for `service-health.feature`
      (`internal/bdd/`), following `event-ingestion/internal/bdd/steps_health_test.go`.
- [ ] Step 7: `make lint`, `make test` (80% gate on `internal/application/` — the
      handlers live in `adapters/http`, so watch that this does not dilute an
      `application` package's coverage), `make test:bdd`, `make test:int`.

**Coverage gate:** 80% on `internal/application/` — CI fails below this.

---

### Phase 3 — aggregation-worker health server (motifpath-core)

**Branch:** `feat/PB-30/aggregation-worker-health-server`

- [ ] Step 1 (test first): table-driven tests for a small
      `internal/adapters/health` HTTP server — `/healthz` → 200; `/readyz` → 200
      when broker + mongo pingers ok, 503 with per-check map otherwise.
- [ ] Step 2: implement the health server (`net/http`, `ReadHeaderTimeout`,
      graceful shutdown on the same signal context as the consumer). Reuse the
      `HealthStatus` JSON shape (hand-written struct — the worker has no
      generated HTTP layer).
- [ ] Step 3: Kafka broker pinger via `segmentio/kafka-go` (`kafka.Dial` +
      `Brokers()` or a metadata read with a short deadline); MongoDB pinger via
      `client.Ping`. Unit-test against testcontainers.
- [ ] Step 4: start the health server from `cmd/main.go` on `PORT` (default
      `8082`), alongside the consumer loop; ensure a consumer-loop failure still
      lets `/healthz` answer until shutdown completes.
- [ ] Step 5: `make lint`, `make test`, `make test:int`.

**Note:** readiness = broker reachable + MongoDB reachable. Consumer-group
membership is explicitly a later refinement (see PB-29's "the real fix is waiting
on group membership").

---

### Phase 4 — Local orchestration files (motifpath-core)

**Branch:** `feat/PB-30/local-orchestration`

- [ ] Step 1: add `wgo` to `devbox.json` `packages`.
- [ ] Step 2: `services/core-domain/.env.example`,
      `services/event-ingestion/.env.example`,
      `services/aggregation-worker/.env.example` — every key from ADR-016 §5 with
      placeholder values and a one-line comment each. Add `*/.env` to
      `.gitignore` (root `.gitignore` already ignores `.env`, `.env.local` —
      confirm `services/*/.env` is covered, tighten if not).
- [ ] Step 3: `process-compose.yaml` at the repo root:
  - processes `core-domain`, `event-ingestion` — `command: wgo run ./cmd`,
    `working_dir: services/<svc>`, `env_files: [services/<svc>/.env]`,
    `readiness_probe.http_get` on `/readyz`, `depends_on` the compose deps
    `process_healthy`.
  - **process-compose does not start or stop the dependency containers** (Q2
    resolved). `make dev` must run first; each service `depends_on` a `deps-ready`
    process whose `readiness_probe.exec` runs `pg_isready`, `mongosh --eval
    "db.runCommand({ping:1})"`, and a Redpanda check, so services wait for the
    already-running containers without a second `docker compose up`.
  - a `full-stack` profile / namespace adding `aggregation-worker`
    (`wgo run ./cmd`) and `web` (`command: npm run dev`,
    `working_dir: ../motifpath-web`) — the sibling-checkout assumption already
    used by the BDD tests and documented in the READMEs.
- [ ] Step 4: `compose.images.yaml`:
  - `build:` each service from `services/<svc>/Dockerfile`, context `.`.
  - throwaway `postgres:16-alpine`, `mongo:7`, `redpandadata/redpanda` deps with
    healthchecks + `start_period`.
  - `depends_on: { <dep>: { condition: service_healthy } }` on each service.
  - service `healthcheck` hitting `/healthz`.
  - env inline, test values only — **no Clerk secret** (Q4 resolved). The smoke
    stays on unauthenticated paths, so `CLERK_SECRET_KEY` can be any non-empty
    dummy string that lets the process boot.
- [ ] Step 5: README — replace the multi-terminal "Running the services locally"
      block with `make dev && devbox services up`; document the `full-stack`
      profile and the `.env.example` copy step; keep the raw `go run` invocation
      as a fallback note.

---

### Phase 5 — Image-smoke CI job (motifpath-core)

**Branch:** `feat/PB-30/ci-image-smoke` (may combine with Phase 4)

- [ ] Step 1: add job `image-smoke` to `.github/workflows/ci.yml`:
  - `on` path filter (via `dorny/paths-filter` or a job-level `if` on
    `github.event.pull_request` + a changed-files check) — run only when
    `services/**` or `**/Dockerfile` changed.
  - `docker compose -f compose.images.yaml build` (with GHA layer cache:
    `cache-from`/`cache-to` type=gha).
  - `docker compose -f compose.images.yaml up --wait --wait-timeout 120`.
  - assert: `curl -fsS localhost:8080/healthz`, `.../readyz`,
    `localhost:8081/healthz`, `.../readyz`, `localhost:8082/healthz`; one real
    request (e.g. `GET /students/me/path` without a token → expect 401, proving
    routing + middleware, not just the health path).
  - `docker compose -f compose.images.yaml logs` on failure; `down -v` always.
- [ ] Step 2: add `image-smoke` to the `all-checks` `needs:` list, but guard so a
      skipped (path-filtered-out) run does not block merges — use
      `if: always()` + explicit result check, or make the job itself always run
      and no-op fast when the filter misses.
- [ ] Step 3: verify on this branch by touching a `Dockerfile` and confirming the
      job runs; touch only a `.md` and confirm it is skipped/no-ops.

---

### Phase 6 — Frontend (motifpath-web)

**Branch:** `feat/PB-30/web-dev-env-doc`

- [ ] Step 1: confirm `.env.example` keys match ADR-016 (`VITE_CLERK_PUBLISHABLE_KEY`,
      `VITE_CORE_API_URL`, `VITE_EVENTS_API_URL`) — already present.
- [ ] Step 2: README — point "Local development" at the `motifpath-core`
      `full-stack` process-compose profile as the one-command path, keeping
      standalone `npm run dev` as the frontend-only option.

---

### Phase 7 — Infrastructure (motifpath-infra)

Nothing in this plan. ADR-016 §6 defers the production-shaped orchestration and
any k3d/K8s work to PB-8a. Left here explicitly so the reader knows it was
considered.

---

## Rollback Plan

All changes are additive and non-stateful:

- Health endpoints are new routes with no migration — revert the `motifpath-core`
  PR; the OpenAPI addition is backward-compatible so no coordinated rollback is
  needed (per ADR-004's expand-only discipline).
- `process-compose.yaml`, `compose.images.yaml`, `.env.example` files are new —
  deleting them restores the prior manual workflow.
- The `image-smoke` CI job — remove the job and its entry in `all-checks.needs`.
- No ECR push, no deploy, no infra change to roll back.

## Validation

- [ ] `make dev && devbox services up` → `core-domain` and `event-ingestion`
      reach `process_healthy`; `curl -fsS localhost:8080/readyz` and
      `localhost:8081/readyz` return 200 with `{"status":"ok","checks":{...}}`.
- [ ] `devbox services up` with the `full-stack` profile additionally starts
      `aggregation-worker` (`localhost:8082/healthz` 200) and `web`
      (`localhost:5173` serves the SPA).
- [ ] Stop the Postgres container → `core-domain` `/readyz` returns 503 naming
      the failed store in its `checks` map; restart → back to 200.
- [ ] `docker compose -f compose.images.yaml up --wait` exits 0 locally; all
      three `/healthz` return 200; an authenticated route with no token returns
      401 (proves routing + middleware, not just the health path).
- [ ] CI: a PR touching `services/core-domain/Dockerfile` runs `image-smoke` and
      it passes; a docs-only PR does not run it (or no-ops in <10s).
- [ ] The PB-8c manual onboarding smoke (web README) is completed end to end
      using `devbox services up` instead of hand-run terminals.
- [ ] `make lint`, `make test`, `make test:bdd`, `make test:int` all green in
      `motifpath-core`; `npm run lint && npm run test` green in `motifpath-web`.

---

## Resolved Decisions

All five resolved 2026-09-07 (Gilson). Rationale in the session discussion; carried
into the phase steps above.

| # | Question | Decision |
|---|---|---|
| Q1 | `HealthStatus` schema — shared file or per-service copy | **Shared** `openapi/components/schemas/health.yaml`, `$ref` from both service docs. One contract cannot drift; matches how `events.yaml` is already shared. |
| Q2 | process-compose owns the dep containers, or `make dev` first | **`make dev` first** + an `exec` readiness probe per dep. Single owner for the containers; DB volumes persist across app restarts; no double-`up` races. |
| Q3 | aggregation-worker health port — `8082` default or required `PORT` | **`PORT` with `8082` default**, matching `core-domain` / `event-ingestion`. Cross-service `main.go` consistency outweighs the worker's fail-closed habit for a port (a wrong port fails loudly at the health check anyway). |
| Q4 | image-smoke needs a Clerk CI secret, or unauthenticated-only | **Unauthenticated-only for v1.** Health + one 401 proves boot + migrate + route + middleware + DB. Deep auth path stays covered by `test-integration`. No secret, no fork-PR breakage, no Clerk-API flake. |
| Q5 | `wgo` or plain `go run` in `process-compose.yaml` | **`wgo`.** Rebuild-on-save is the point of an inner-loop tool. Debugger tension resolved by running the one service-under-test directly under Delve and leaving the rest to process-compose. |

---

## Related

- **ADR:** `adrs/ADR-016-local-dev-orchestration-and-image-smoke.md`
- **Refines:** ADR-004 (local-env line; closes the accepted image-smoke gap),
  ADR-011 (adds a health server to the aggregation worker)
- **Spec files:** `openapi/core-domain-service.yaml`,
  `openapi/components/schemas/health.yaml` (new),
  `features/core-domain/service-health.feature` (new)
- **Backlog item:** PB-30 (`3d49ccc1-102f-81ac-8ca9-fe96d6b5d099`)
- **Reference implementation:** `event-ingestion`'s `LivenessCheck` /
  `ReadinessCheck` handler, `ports.Pinger`, and
  `internal/bdd/steps_health_test.go`
