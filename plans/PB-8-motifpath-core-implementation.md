# Plan: motifpath-core Implementation — Monorepo Scaffold + Event Ingestion Service + Core Domain Service

**Task:** PB-8
**Date:** 2026-06-12
**Last revised:** 2026-08-25 — Phase 4 reconciled against merged PB-12a/b/c specs; added Phase 4.0
  (minimal Aggregation Worker, pending ADR-011)
**Author:** Gilson
**Status:** Ready (Phases 2–3 done; Phase 4.0 blocked on ADR-011; Phase 4 blocked on Phase 4.0)

---

## Goal

Build the `motifpath-core` Go monorepo from an empty scaffold to a fully functional backend
with three services: the Event Ingestion Service (student tracking events → MongoDB + Kafka),
a minimal Aggregation Worker (Kafka → per-node completion status in MongoDB), and the Core
Domain Service (learning graph, path assignments, content management). All specs are already
merged except ADR-011, which this plan requires before Phase 4.0.

## Scope

**In scope:**
- Go monorepo root tooling (Makefile, devbox.json, docker-compose.yml, go.work, golangci.yml)
- Event Ingestion Service — full hexagonal implementation: domain, application, ports, adapters, HTTP handler
- Core Domain Service — full hexagonal implementation: all 15 endpoints from OpenAPI spec
- **Aggregation Worker — minimal slice only:** a single Kafka consumer that derives per-student,
  per-content-node completion status (`not_started` / `in_progress` / `completed`) from the three
  lesson-family events, and writes it to MongoDB `aggregates`. This is the smallest slice that
  satisfies `student-path-view.feature`. See Phase 4.0 and the Open Questions below — full
  aggregation (exercise scoring summaries, analytics) is still out of scope.
- BDD test integration with godog (all feature files from motifpath-specs)
- testcontainers integration tests for all three services
- 80% coverage gate on `internal/application/` packages (all services)

**Out of scope:**
- Full Aggregation Worker scope: exercise-answer scoring summaries, analytics rollups, anything
  beyond the single `content_node` completion status needed by `GET /students/me/path`
- motifpath-web (Vue 3 frontend — separate backlog item)
- motifpath-infra (Terraform — separate backlog item)
- PB-11 standalone /events/ JSON Schemas (P1, non-blocking)
- PB-12d expansion settings spec (still in Discovery)

## Prerequisites

- [x] OpenAPI spec: `openapi/event-ingestion-service.yaml` merged (PR #2)
- [x] OpenAPI spec: `openapi/core-domain-service.yaml` merged (PRs #4, #5, #6)
- [x] Gherkin scenarios: all feature files merged (PRs #2–#6)
- [x] ADR-005 — ent migration strategy (Postgres)
- [x] ADR-006 — Kafka topology (single topic, student_id partition, MSK)
- [x] ADR-007 — Clerk authentication and JWT local validation
- [x] ADR-008 — MongoDB Atlas (event log + aggregates)
- [x] ADR-009 — Clerk Go SDK for JWT local validation (resolves Phase 3 Open Question)
- [x] ADR-010 — Atlas CLI migration workflow (resolves Phase 4 Open Question)
- [ ] **ADR-011 (new, not yet written)** — amends ADR-006's consumer-group table to add the
  minimal Aggregation Worker described above. Must be decided before Phase 4.0 starts; see
  Open Questions.

---

## Implementation Steps

### Phase 1 — Specs (motifpath-specs)

**Status: Done.** All spec PRs merged. No new spec work required for this plan.

---

### Phase 2 — Monorepo Root Scaffold (motifpath-core)

**Branch:** `feat/PB-8/monorepo-scaffold`

- [ ] Create `go.work` declaring both service modules
- [ ] Create `services/event-ingestion/go.mod` (`module github.com/motifpath/event-ingestion`)
- [ ] Create `services/core-domain/go.mod` (`module github.com/motifpath/core-domain`)
- [ ] Create `Makefile` with targets: `generate`, `test`, `test:bdd`, `test:int`, `lint`, `dev`
- [ ] Create `devbox.json` (Go 1.23, oapi-codegen, golangci-lint, godog, goose or atlas CLI)
- [ ] Create `.golangci.yml` (errcheck, govet, staticcheck, unused, gocognit — match CLAUDE.md rules)
- [ ] Create `docker-compose.yml` (Postgres, MongoDB, Kafka + Zookeeper for local dev)
- [ ] Create `shared/` placeholder (`shared/errors/errors.go` — domain error types only)

**Validation:**
- [ ] `make dev` starts all local dependencies without errors
- [ ] `go work sync` resolves with no module conflicts

---

### Phase 3 — Event Ingestion Service (motifpath-core)

**Branch:** `feat/PB-8/event-ingestion-service`

#### 3.1 — Code generation
- [ ] Run `oapi-codegen` against `openapi/event-ingestion-service.yaml` → `internal/adapters/http/generated/`
- [ ] Commit generated stubs — do not edit generated files

#### 3.2 — Domain layer (`internal/domain/`)
- [ ] Define `TrackingEvent` base struct + 7 typed event structs (one per `event_type`)
- [ ] Define domain error types: `ErrInvalidEventType`, `ErrMissingRequiredField`

#### 3.3 — Ports (`internal/ports/`)
- [ ] Define `EventRepository` interface: `Save(ctx, TrackingEvent) error`
- [ ] Define `EventPublisher` interface: `Publish(ctx, TrackingEvent) error`

#### 3.4 — Application layer (`internal/application/`)
- [ ] Implement `IngestEventService.Ingest(ctx, TrackingEvent) error`
  - Validate event_type is in the allowed set
  - Call `EventRepository.Save`
  - Call `EventPublisher.Publish` (async — fire and forget; log publish failures)
- [ ] Write table-driven unit tests (testify) — one test function per Gherkin scenario group
  - Happy path: all 7 event types accepted
  - Idempotency: duplicate event_id accepted without error
  - Auth mismatch: student_id in event ≠ token subject → error
  - Validation failures: missing event_type, unrecognised event_type, missing required fields

#### 3.5 — Adapters
- [ ] Implement `MongoEventRepository` (`internal/adapters/repo/mongo_event_repo.go`)
  - Upsert by `event_id` (idempotency)
  - Store raw payload as BSON document
- [ ] Implement `KafkaEventPublisher` (`internal/adapters/kafka/kafka_publisher.go`)
  - Produce to `motifpath.events` topic, partition key = `student_id`
  - Fire-and-forget with error logging (ADR-006)
- [ ] Implement HTTP handler (`internal/adapters/http/handler.go`)
  - Parse and validate request body against generated types
  - Map `student_id` mismatch (token vs payload) → 401
  - Call `IngestEventService.Ingest`
  - Return 202 on success; 400 on validation error; 401 on auth error

#### 3.6 — BDD (godog)
- [ ] Write step definitions for `features/event-ingestion/ingest-tracking-event.feature`
- [ ] Write step definitions for `features/event-ingestion/service-health.feature`
- [ ] Run `make test:bdd` — all scenarios green

#### 3.7 — Integration tests (testcontainers)
- [ ] MongoDB container: verify event document written with correct fields
- [ ] Kafka container: verify message produced to correct topic with correct partition key
- [ ] Run `make test:int` — all tests green

#### 3.8 — Wiring
- [ ] Implement `cmd/main.go` — dependency injection, Clerk JWT middleware, graceful shutdown
- [ ] Add `Dockerfile` (multi-stage, distroless final image)

**Validation:**
- [ ] `POST /events` returns 202 for all 7 event types (happy path)
- [ ] `POST /events` with duplicate `event_id` returns 202 (no error)
- [ ] `POST /events` with `event_type: "node.unlocked"` returns 400 (rejected)
- [ ] `POST /events` without auth token returns 401
- [ ] `POST /events` with mismatched `student_id` returns 401
- [ ] Coverage ≥ 80% on `services/event-ingestion/internal/application/`
- [ ] `make lint` passes with zero warnings

---

### Phase 4.0 — Minimal Aggregation Worker (motifpath-specs + motifpath-core)

**Why this phase exists:** `student-path-view.feature` requires the Core Domain Service to know,
per student and per content node, whether that node is `completed` / `in_progress` / `not_started`.
That state is derived from `lesson.started` / `lesson.resumed` / `lesson.completed` events, which
only reach MongoDB and Kafka — never Postgres. ADR-006 already named the Aggregation Worker as the
sole Kafka consumer at MVP (`aggregation-worker` consumer group → MongoDB `aggregates`), but the
original PB-8 scope deferred building it post-MVP. That gap must close before Phase 4.1+ can be
implemented against real data instead of a mocked port.

**Status:** Blocked until ADR-011 is written and decided.

**Branch:** `adr/PB-8/011-minimal-aggregation-worker` (spec), then `feat/PB-8/aggregation-worker` (code)

#### 4.0.1 — Spec (motifpath-specs)
- [ ] Write `adr/ADR-011-minimal-aggregation-worker.md`, amending ADR-006's consumer-group table
  with the `aggregation-worker` row's concrete write shape:
  - MongoDB `aggregates` document shape: `{ student_id, content_node_id, status, updated_at }`
  - Status transition rule: `lesson.started`/`lesson.resumed` → `in_progress` unless already
    `completed`; `lesson.completed` → `completed` (terminal, never downgraded)
  - Idempotency: upsert keyed on `(student_id, content_node_id)`; duplicate delivery of the same
    event is a no-op transition, consistent with ADR-006's at-least-once consequence
  - Explicitly scope out exercise-event aggregation and analytics rollups — those remain the
    full Aggregation Worker's job, still post-MVP
- [ ] Confirm no Gherkin changes needed — `student-path-view.feature` already specifies the
  externally observable behavior this worker must produce; the worker itself has no HTTP surface

**Definition of Ready check:**
- [ ] ADR-011 decided (not just proposed)
- [ ] ADR-006's consumer-group table updated to reference ADR-011 for the write-shape detail

#### 4.0.2 — Code generation
- N/A — this service has no OpenAPI surface (Kafka consumer only)

#### 4.0.3 — Domain layer (`services/aggregation-worker/internal/domain/`)
- [ ] Define `NodeCompletionStatus` enum: `not_started`, `in_progress`, `completed`
- [ ] Define the transition rule as a pure function: `(current, eventType) -> next`, `completed`
  is terminal and never regresses

#### 4.0.4 — Ports (`internal/ports/`)
- [ ] `CompletionStateRepository` — `Upsert(ctx, studentID, contentNodeID, status) error`
- [ ] `EventConsumer` — wraps the Kafka client's subscribe/commit loop

#### 4.0.5 — Application layer (`internal/application/`)
- [ ] `ProcessEventService.Handle(ctx, TrackingEvent) error` — filters for lesson-family events,
  applies the transition rule, calls `CompletionStateRepository.Upsert`
- [ ] Table-driven unit tests: started→in_progress, resumed→in_progress, completed→completed,
  completed→resumed does not downgrade, duplicate event is a no-op, non-lesson events are ignored

#### 4.0.6 — Adapters
- [ ] `KafkaEventConsumer` — subscribes to `motifpath.events`, consumer group `aggregation-worker`
  (per ADR-006), commits offsets after successful upsert
- [ ] `MongoCompletionStateRepository` — upserts into `aggregates`

#### 4.0.7 — Integration tests (testcontainers)
- [ ] Kafka + MongoDB containers: publish a `lesson.completed` event, verify the `aggregates`
  document reaches `status: completed`
- [ ] Verify duplicate delivery of the same event does not error and leaves status unchanged

#### 4.0.8 — Wiring
- [ ] Implement `cmd/main.go` — consumer group startup, graceful shutdown on SIGTERM (must commit
  in-flight offsets before exit)
- [ ] Add `Dockerfile`

**Validation:**
- [ ] A `lesson.completed` event for a known student/node results in an `aggregates` document with
  `status: completed` within one poll interval
- [ ] Restarting the worker mid-stream resumes from the last committed offset, not from the start
- [ ] Coverage ≥ 80% on `services/aggregation-worker/internal/application/`
- [ ] `make lint` passes with zero warnings

---

### Phase 4 — Core Domain Service (motifpath-core)

**Branch:** `feat/PB-8/core-domain-service`

**Depends on:** Phase 4.0 (the Core Domain Service reads completion state this worker produces —
do not start 4.4/4.5/4.6 against a real adapter until 4.0 is merged; a mocked port is fine for
earlier steps).

#### 4.1 — Code generation
- [x] `oapi-codegen` already run against `openapi/core-domain-service.yaml` during Phase 2 scaffold
  — `internal/adapters/http/generated/api.gen.go` exists. Re-run and re-commit only if the spec
  changed since.

#### 4.2 — ent schema + migrations
- [ ] Initialize `ent` schema in `internal/adapters/repo/ent/schema/` (directory currently empty)
- [ ] Define ent schemas matching the actual OpenAPI components — **not** the entities listed in
  an earlier draft of this plan (`ThresholdOverride` and `StudentNodeState` do not exist in the
  merged spec):
  - `User` (`user_id`, `role` enum: student/teacher/admin, `registered_at`)
  - `ContentNode` (`content_node_id`, `teacher_id`, `title`, `content_type`, embedded
    `Classification`: `skill`, `concept`, `difficulty_level`, `review_state`)
  - `Challenge` (`challenge_id`, `content_node_id`, `subject_tag`, `pass_threshold`,
    `remediation_target_content_node_id` nullable)
  - `Exercise` (`exercise_id`, `challenge_id`, `exercise_type`, `prompt`)
  - `ExpandedContent` (`expanded_content_id`, `content_node_id`, `content_type`, `media_url`,
    video fields `trigger_at_seconds`/`hide_at_seconds` XOR article fields
    `trigger_at_paragraph`/`duration_ms`, `caption`)
  - `LearningPath` (`learning_path_id`, `teacher_id`, `title`) + `LearningPathItem`
    (`position`, `content_node_id`) as an edge/join table
  - `PathAssignment` (`assignment_id`, `student_id`, `learning_path_id`, `assigned_by`,
    `assigned_at`) — one active assignment per student for MVP; assigning a new path replaces
    the existing row rather than appending
- [ ] Generate ent code (`go generate`)
- [ ] Write initial migration via `make migrate:diff name=core-domain-initial-schema`
  (Atlas CLI workflow — ADR-010)

#### 4.3 — Domain layer (`internal/domain/`)
- [ ] Define entities and value objects: `User`, `ContentNode` + `Classification`, `Challenge`,
  `Exercise`, `ExpandedContent` (with the video/article field-group invariant enforced in the
  constructor, not just at the HTTP boundary), `LearningPath` + `LearningPathItem`, `PathAssignment`
- [ ] Define `StudentPathItem` as a read-model value object combining `LearningPathItem` with a
  `NodeCompletionStatus` looked up from the Phase 4.0 worker's output — position 1 is `locked`
  only if a prior item isn't `completed`; `current_position` is the first non-`completed` item
- [ ] Define domain errors: `ErrNotFound`, `ErrForbidden`, `ErrAlreadyExists`, `ErrValidation`

#### 4.4 — Ports (`internal/ports/`)
- [ ] One repository interface per aggregate: `UserRepository`, `ContentNodeRepository`,
  `ChallengeRepository`, `ExerciseRepository`, `ExpandedContentRepository`,
  `LearningPathRepository`, `PathAssignmentRepository`
- [ ] `CompletionStateReader` — `GetStatuses(ctx, studentID, []contentNodeID) (map[contentNodeID]NodeCompletionStatus, error)`,
  backed by the Phase 4.0 worker's MongoDB `aggregates` collection (read-only from this service's
  perspective)

#### 4.5 — Application layer (`internal/application/`)
- [ ] `IdentityService` — `RegisterUser`, `GetMyProfile`
- [ ] `ContentService` — `CreateContentNode`, `GetContentNode`, `CreateExpandedContent`, `ListExpandedContent`, `GetExpandedContent`
- [ ] `ChallengeService` — `CreateChallenge`, `GetChallenge`, `CreateExercise`, `GetExercise`
- [ ] `LearningPathService` — `CreateLearningPath`, `GetLearningPath`
- [ ] `PathAssignmentService` — `AssignLearningPath`, `GetMyPath` (composes `PathAssignmentRepository`
  + `LearningPathRepository` + `CompletionStateReader`)
- [ ] Write table-driven unit tests for each service, covering all Gherkin scenarios:
  - Happy paths (teacher/admin/student roles as appropriate)
  - Authorisation failures (wrong role, no token)
  - Not-found cases
  - Validation failures
  - `GetMyPath`: all five `student-path-view.feature` progress-state scenarios, using a fake
    `CompletionStateReader`

#### 4.6 — Adapters
- [ ] Implement `EntUserRepository`, `EntContentNodeRepository`, etc. (one file per aggregate)
- [ ] Implement `MongoCompletionStateReader` (reads the same `aggregates` collection Phase 4.0 writes)
- [ ] Implement HTTP handlers — one handler struct, one method per operation
  - RBAC enforcement: teacher/admin/student gates as per Gherkin scenarios
  - Map domain errors → HTTP status codes (404 → not found, 403 → forbidden, 400 → bad request,
    409 → conflict on duplicate registration)

#### 4.7 — BDD (godog)
- [ ] Write step definitions for all feature files in `features/`:
  - `user-registration/register-user.feature`
  - `content-management/content-nodes.feature`
  - `content-management/challenges.feature`
  - `content-management/exercises.feature`
  - `content-management/expanded-content.feature`
  - `learning-paths/learning-paths.feature`
  - `learning-paths/path-assignments.feature`
  - `learning-paths/student-path-view.feature`
- [ ] Run `make test:bdd` — all scenarios green

#### 4.8 — Integration tests (testcontainers)
- [ ] Postgres container: verify migrations apply cleanly on startup
- [ ] MongoDB container: verify `GetMyPath` reflects completion state written by a simulated
  Phase 4.0 worker document
- [ ] Verify end-to-end: create node → create challenge → create learning path → assign to
  student → get student path
- [ ] Verify replacing an active path assignment resets progress (new assignment, no carryover)
- [ ] Run `make test:int` — all tests green

#### 4.9 — Wiring
- [ ] Implement `cmd/main.go` — ent client + Atlas migration-on-startup guarded by the
  distributed lock (ADR-005), Mongo client for `CompletionStateReader`, Clerk JWT middleware
  (ADR-009), graceful shutdown
- [ ] Add `Dockerfile`

**Validation:**
- [ ] All 15 endpoints return expected responses per Gherkin scenarios
- [ ] `GET /students/me/path` returns correct `completed`/`in_progress`/`not_started`/`locked`
  state for all five scenarios in `student-path-view.feature`
- [ ] Coverage ≥ 80% on `services/core-domain/internal/application/`
- [ ] `make lint` passes with zero warnings

---

## Rollback Plan

Both services are stateless HTTP services deployed as containers (ADR-004 blue/green). Rolling
back either service means redeploying the previous container image via EKS — no data migration
is required for the Event Ingestion Service. For the Core Domain Service, ent migrations are
forward-only at MVP; in the event of a bad migration, restore the Postgres snapshot from RDS
automated backup before redeploying the previous image.

## Open Questions

| Question | Owner | Resolution |
|---|---|---|
| Clerk JWT validation: use official Go SDK or raw `jwks` fetch? | Gilson | **Resolved** — ADR-009: `clerkinc/clerk-sdk-go/v2` |
| Kafka local dev: use Redpanda (lighter) or full Confluent image? | Gilson | **Resolved** — Redpanda v24.2.7 in `docker-compose.yml` |
| ent migration tooling: Atlas CLI or `ent migrate diff`? | Gilson | **Resolved** — ADR-010: Atlas CLI (`atlas migrate diff` + `atlas migrate lint`) |
| Who computes per-student node completion state for `GET /students/me/path`, given ADR-006 names the Aggregation Worker as sole Kafka consumer but PB-8 scoped it out post-MVP? | Gilson | **Resolved 2026-08-25** — pull a minimal Aggregation Worker into Phase 4.0, scoped to node-completion status only. Formalize as ADR-011 before Phase 4.0 starts. |
| ADR-011 exact `aggregates` document shape and idempotency rule | Gilson | Draft in Phase 4.0.1 — see that section for the proposed shape |

---

## Related

- **Spec files:** `openapi/event-ingestion-service.yaml`, `openapi/core-domain-service.yaml`, `openapi/components/schemas/`
- **Feature files:** `features/event-ingestion/`, `features/content-management/`, `features/learning-paths/`, `features/user-registration/`
- **ADRs:** ADR-005, ADR-006, ADR-007, ADR-008, ADR-009, ADR-010, ADR-011 (to be written, Phase 4.0.1)
- **Backlog item:** PB-8
