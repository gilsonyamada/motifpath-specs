# ADR-016: Local Dev Orchestration via process-compose; Release-Image Smoke in CI

**Status:** Accepted — 2026-09-07
**Date:** 2026-09-07
**Deciders:** Gilson Yamada (solo engineering at MVP)

---

## Context

There is no one-command way to run MotifPath locally. A developer runs `make dev`
(which starts only the Postgres / MongoDB / Redpanda dependency containers via
`docker-compose`), then hand-starts three Go services in separate terminals with
inline environment variables, and starts `motifpath-web` separately again. Two
manual end-to-end smoke tests have already stalled on this friction: the PB-8b
browser smoke and the PB-8c Clerk onboarding smoke, both of which need
`core-domain` plus the SPA running together against a real Clerk development key.

Separately, ADR-004 records an explicitly **accepted gap**: *"the pipeline does
not include automated production smoke tests at MVP. Manual verification
post-deploy is the substitute. This is a known gap, accepted for now."* The three
Go service Docker images are never exercised anywhere — not locally, not in CI.
Running the services with `go run` masks image-only failure modes: missing CA
certificates, the non-root user being unable to write, the bundled `atlas` binary
not being on the image's `PATH`, a broken `ENTRYPOINT`, a wrong `EXPOSE`.

Three constraints frame this decision, consistent with ADR-003 and ADR-006:

1. **The production deployment target is itself in flux.** The Project Index
   records PB-8a (deployment & hosting) as *on hold* — "the alpha will use a
   simpler hosting approach than full EKS/Terraform (TBD); `motifpath-infra`
   stays untouched." There are zero Kubernetes manifests, Helm charts, or
   build/deploy workflows in any repo. Any local tooling that buys parity with
   EKS blue/green (ADR-004) buys parity with a design that is paused.
2. **Operational and learning burden is the most expensive currency at MVP.**
   Running a local Kubernetes control plane (k3d) and a live-sync tool (Tilt,
   Skaffold) is real operational surface to learn and debug, at exactly the
   moment attention belongs on the learning graph, `ent`, and Vue 3.
3. **The inner loop must stay fast.** Rebuilding a container image on every Go
   file save is the anti-pattern the Skaffold/Tilt literature itself warns about;
   for a solo developer it is the difference between iterating and waiting.

A further finding surfaced during analysis: **`core-domain` has no `/healthz` or
`/readyz` endpoint** (not in its OpenAPI, not generated, not implemented), and
**`aggregation-worker` has no HTTP server at all**. `event-ingestion` has both,
and is the reference pattern. Health endpoints are a prerequisite for *every*
candidate hosting model (Fly, Render, Railway, ECS/ALB, k3d) and for any
image-boot smoke, so their absence blocks both this decision and PB-8a.

Three distinct jobs are in play and must not be conflated:

| Job | What it needs |
|---|---|
| **Inner loop** — edit a service, see it run | sub-second restart, native logs, a debugger |
| **Full-stack manual smoke** — walk a feature in a browser | all services + web + deps up together, one command |
| **Release confidence** — does the *image* boot, migrate, serve? | the real Dockerfile artifact, run once, in CI |

High-level alternatives considered: docker-compose running the service images;
k3d + Tilt or Skaffold; a Makefile target chaining background processes; and
doing nothing.

## Decision

MotifPath will treat the three jobs above as three mechanisms, and commit now
only to the parts that are independent of the unresolved hosting choice.

### 1. Inner loop — process-compose running the services as processes

The Go services run locally as `go run ./cmd` processes orchestrated by
[**process-compose**](https://github.com/F1bonacc1/process-compose), which is
already bundled with Devbox (`devbox services`). A committed
`process-compose.yaml` at the `motifpath-core` root defines one process per
service, each with a `readiness_probe` and `depends_on … process_healthy`
ordering on the dependency containers. The dependency containers
(Postgres / MongoDB / Redpanda) stay exactly as they are in the existing
`docker-compose.yml`; `make dev` continues to start only those. The developer
runs `make dev` then `devbox services up`.

Services are wrapped in [`wgo`](https://github.com/bokwoon95/wgo) for
rebuild-on-save (chosen over `air` for having no config file). `go run` still
executes the real `atlas migrate apply` shell-out (ADR-005) and the real
OpenTelemetry-to-stdout path (ADR-003), so those are exercised in the inner loop.

### 2. Full-stack manual smoke — the same graph, extended

A second process-compose profile adds `motifpath-web` (`npm run dev`) and the
`aggregation-worker` + its Redpanda dependency as processes. This is what a
developer runs for PB-8b / PB-8c and future student-slice smoke tests. Web is
served by Vite in dev and as a static build in prod (S3 + CloudFront per
ADR-004) — it is never containerized here.

### 3. Release confidence — a compose file that builds the images, plus a CI job

A committed `compose.images.yaml` in `motifpath-core` builds all three services
from their real `Dockerfile`s and runs them against throwaway dependency
containers. A GitHub Actions job runs `docker compose -f compose.images.yaml up
--wait`, then asserts `GET /healthz` and `GET /readyz` on the HTTP services and
exercises one real authenticated endpoint. The job is gated to run only on pull
requests that touch `services/**` or any `Dockerfile`. This closes the smoke-test
gap ADR-004 accepted. The repository is public, so GitHub Actions minutes are
unmetered; with layer caching the job is ~1–2 minutes.

### 4. Health and readiness endpoints — folded in as a prerequisite

- **`core-domain`** gains `GET /healthz` (liveness) and `GET /readyz`
  (readiness — checks Postgres and MongoDB reachability), specified in its
  OpenAPI document first, mirroring `event-ingestion`'s existing contract.
- **`aggregation-worker`** gains a minimal HTTP server exposing `/healthz` and
  `/readyz` (readiness reflects Kafka consumer-group membership and MongoDB
  reachability), running alongside its Kafka consumer loop.

### 5. Environment-variable contract

The variables below are the single canonical contract, consumed by the local
`.env` files, `compose.images.yaml`, and whatever PB-8a chooses for production
secrets injection. `.env` files are gitignored; a committed `.env.example` per
service carries the keys with placeholder values.

| Variable | core-domain | event-ingestion | aggregation-worker | Notes |
|---|---|---|---|---|
| `PORT` | ✓ (8080) | ✓ (8081) | ✓ (health server) | |
| `DATABASE_URL` | ✓ | — | — | Postgres DSN |
| `MONGO_URI` | ✓ | ✓ | ✓ | |
| `MONGO_DATABASE` | ✓ | ✓ | ✓ | defaults to `motifpath_events` |
| `KAFKA_BROKERS` | — | ✓ | ✓ | comma-separated |
| `CLERK_SECRET_KEY` | ✓ | ✓ | — | same Clerk instance as the SPA |
| `CORE_DOMAIN_BASE_URL` | — | ✓ | — | |
| `CORS_ALLOWED_ORIGINS` | ✓ | ✓ | — | defaults to `http://localhost:5173` |

### 6. What this ADR does not decide

- **A production-grade full-stack `docker-compose.yml`** (services, not just
  deps). It becomes worthwhile *if* PB-8a lands on compose-on-a-VM, Fly, Render,
  or Railway — all of which consume a Dockerfile or compose file — and throwaway
  if PB-8a chooses otherwise. Deferred to PB-8a.
- **k3d, Tilt, Skaffold, or any local Kubernetes.** Reconsidered only if ADR-004's
  EKS path comes off hold and non-trivial K8s manifests exist.

This ADR **refines ADR-004's** one-line local-environment description ("local
(Docker Compose + k3d)") to: *dependencies in Docker Compose; services via
process-compose; k3d deferred together with the EKS deployment path.*

### 7. Forward compatibility — browser end-to-end tests

Browser E2E (Playwright or equivalent) is out of MVP scope per the
`motifpath-web` testing policy (component tests via Vitest only). This ADR does
not add it, and this section records that the door stays open: the pieces an E2E
harness needs are the pieces this ADR introduces.

A future E2E suite plugs into, without changing any decision above:

- the **`full-stack` profile** (§2) for a local run, or **`compose.images.yaml`**
  (§3) for a CI run — the running stack under test, at fixed ports;
- **`/readyz` on every service** (§4) — the readiness gate an E2E runner's
  start-up step (`docker compose up --wait`, a Playwright `webServer` block)
  waits on before the first test;
- the **environment-variable contract** (§5), which already carries
  `CLERK_SECRET_KEY` and `VITE_CLERK_PUBLISHABLE_KEY` — an E2E job supplies a
  Clerk *test-instance* key via a CI secret. The image-smoke job's dummy key
  (§3) is a property of that job, not a platform limit.

What E2E adds when the trigger fires — all additive, none in tension with this
ADR: the Playwright dependency and CI browser; a state-seeding mechanism (API
calls or SQL fixtures for test users and learning-path data); and serving the
SPA for the run via `npm run build && npm run preview` (static, SPA-fallback
aware — matches CloudFront) rather than the `npm run dev` HMR server used for
iteration.

**Trigger to revisit:** the first regression that ships which a component test
could not structurally have caught (guard × store × router × real API), or the
point at which the manual student-journey smoke becomes a per-release time cost.

## Rationale

**process-compose over docker-compose for the services.** The inner loop is the
dominant cost for a solo developer, and a container rebuild per save destroys it.
docker-compose's parity benefit is also weaker than it appears: Compose is not
Kubernetes (no Service selector, no ConfigMap/Secret semantics, no blue/green), so
"parity" would be with a third not-quite-prod shape, not with production. And
running three service containers with `depends_on: service_healthy` chains
reproduces precisely the container-startup race surface that PB-29 has spent two
PRs suppressing (`connection reset by peer` past retry budgets). process-compose
keeps process lifecycle clean — one `Ctrl+C` tears the whole graph down — which a
Makefile chaining background jobs with `&` cannot do reliably.

**Not k3d + Tilt/Skaffold.** This is the local-dev equivalent of the self-hosted
LGTM stack that ADR-003 rejected and the self-hosted Kafka that ADR-006 rejected,
for the same reason: operational and learning burden is the expensive currency at
MVP. It would also mean authoring and maintaining Kubernetes manifests that do
not exist for production and may never exist in that form if PB-8a picks a simpler
host. The parity is real but it is parity with a paused design.

**Image smoke as a separate, occasional CI concern rather than the inner loop.**
"Does the image boot, migrate, and serve" is a release question, answered once per
change, not on every save. Making the inner loop containerized to answer it would
tax every iteration to catch a class of bug that a 2-minute CI job catches
better. This directly converts ADR-004's accepted manual-only gap into an
automated check.

**Health endpoints now, not later.** Every plausible PB-8a outcome needs them:
Fly and Render health checks, an ALB target group for ECS, Kubernetes liveness /
readiness probes, and the image-smoke job here. `event-ingestion` already has the
contract; bringing `core-domain` and `aggregation-worker` in line is small, and
doing it now avoids discovering the gap under deployment pressure.

**`.env` files with a documented contract.** Today the variable names live only
in `main.go` and the README's copy-paste block. A single table, consumed by
local `.env`, the image-smoke compose file, and eventually the production secret
store, is the mechanism that keeps the three in sync — and the image-smoke job
fails loudly if the image needs a variable that is not wired, which catches drift.

## Consequences

### Positive

- One command (`devbox services up`) brings up the stack a developer needs for a
  manual smoke test; the PB-8b and PB-8c smokes are unblocked.
- The inner loop stays process-fast, with a debugger attachable and native logs.
- The three service Docker images gain a boot-and-serve check on every PR that
  can affect them — ADR-004's accepted gap is closed for the image artifact.
- `core-domain` and `aggregation-worker` gain the health endpoints that PB-8a
  will need regardless of which host it picks.
- Zero new cost: process-compose ships with Devbox, the CI job runs on unmetered
  public-repo minutes, no image is pushed to ECR, no new SaaS.
- No new operational surface — nothing to keep healthy that was not already
  running.

### Negative / Trade-offs

- **The inner loop does not exercise the Docker images.** "Works locally" does
  not mean "the image works" — only the CI smoke job establishes that. A
  developer can still be surprised by an image failure on a branch whose changes
  did not trip the path filter.
- **process-compose is a single-maintainer open-source project.** If it is
  abandoned, the `process-compose.yaml` must be replaced (Overmind, Foreman, or a
  hand-rolled supervisor). Low impact — it is dev-only tooling, already a
  transitive Devbox dependency, and the config is ~40 lines.
- **Three places now describe service configuration** (`.env.example`,
  `compose.images.yaml`, future production manifests). The contract table and the
  image-smoke job's loud failure on a missing variable are the mitigations, but
  drift is possible.
- **Local data stores still differ from production** in ways this does not fix:
  local Postgres ≠ RDS, single-node Mongo ≠ Atlas replica set (no transactions /
  change streams locally without `--replSet`), Redpanda ≠ MSK. This is a known,
  accepted boundary, not a regression.
- **A second health-server concern for `aggregation-worker`**, a service that was
  deliberately a pure consumer. Small (~15 lines) and needed for deployment
  anyway, but it is new surface in a service ADR-011 kept minimal.

### Neutral

- The full-stack production-shaped compose file is deferred, not rejected; PB-8a
  decides it.
- ECR image-retention (a lifecycle policy to expire untagged / old images from
  the eventual dev-merge build) is a related but separate concern, noted here and
  tracked with PB-8a / the deployment pipeline work.
- Browser E2E stays out of scope (§7). This ADR is the substrate a later E2E
  effort builds on rather than a step toward it.
- The `motifpath-specs` ADR directory inconsistency (`adr/` held ADR-001–014,
  `adrs/` held ADR-015 and this file) was resolved by PR #29, which moved
  ADR-001–014 into `adrs/` and reconciled `CLAUDE.md`.

## Related ADRs

- **ADR-003: Observability — OpenTelemetry to stdout.** The inner loop's `go run`
  path emits the same stdout JSON; the decision to keep operational/learning
  burden low is applied here identically.
- **ADR-004: Deployment pipeline — blue/green on EKS.** This ADR refines its
  local-environment line and closes its accepted "no automated smoke test" gap
  for the image artifact. The EKS specifics remain on hold with PB-8a.
- **ADR-005: Database migration — Atlas + `ent`, startup lock.** The `atlas
  migrate apply` startup shell-out is exercised by both the inner loop and the
  image-smoke job.
- **ADR-006: Kafka topology — MSK.** Locally, Kafka is the existing Redpanda
  container; `aggregation-worker`'s readiness probe reflects consumer-group
  membership, the same signal ADR-006 relies on.
- **ADR-011: Minimal Aggregation Worker.** This ADR adds a minimal health HTTP
  server to that otherwise pure-consumer service.
- **PB-29: Integration test reliability & speed.** The container-startup race
  this ADR avoids by not containerizing the inner loop is the same race PB-29 is
  suppressing in the testcontainers suite.

---

*This ADR was decided on 2026-09-07. To revise, create a new ADR with Status: Supersedes ADR-016.*
