# ADR-005: Database Migration Strategy — `ent` + Atlas

## Status

Accepted — 2026-05-17

## Context

The Core Domain Service uses `ent` as its ORM against Postgres on RDS. `ent` defines the schema as Go code; at runtime, it expects the database schema to match. The question is how schema changes are authored, versioned, validated, applied, and recovered from.

The constraints inherited from ADR-004 are explicit and binding:

- Migrations **run at application startup**.
- Every migration **must be backward-compatible** with the previous application version (expand → migrate → contract).
- Blue/green deployments mean two application versions run against the database simultaneously during cutover.
- Rollback is **redeploy the previous container image** — never a database rollback.

Migrations apply only to the **Postgres** store. The MongoDB event log is schemaless by design; per-event schema evolution is handled by consumer code, not by a migration tool.

At MVP, the schema surface is small — a handful of entities in the learning graph (`User`, `ConceptNode`, `Threshold`, `PathState`, plus relationships). But migration discipline has to be right from day one: there is no second pair of eyes to catch a bad migration in review, and retrofitting a strategy after the first production schema mistake is expensive.

## Decision

### Migration tooling — Atlas, via `ent`'s native integration

[Atlas](https://atlasgo.io/) (developed by Ariga, the same team behind `ent`) is the migration engine. It is the canonical migration story for `ent` projects and is the only credible option that does not require leaving the `ent` ecosystem.

Workflow:

1. Modify the `ent` schema definitions in `motifpath-core`.
2. Run `atlas migrate diff <name>` — Atlas inspects the `ent` schema, computes the delta against the current migration history, and emits a versioned SQL file.
3. Review the generated SQL by hand. Edit if necessary (e.g. to split a destructive change into the expand-migrate-contract dance).
4. Commit the migration file alongside the `ent` schema change in the same PR.

The developer never writes `ent` schema changes without also writing the migration in the same PR. The two are atomic.

### Migration file location — in `motifpath-core`

Migration files live in `motifpath-core/internal/domain/migrations/` alongside the `ent` schema definitions, **not** in `motifpath-specs`.

Rationale: SDD applies to contracts between systems — OpenAPI, Gherkin scenarios, event schemas. The Postgres schema is implementation detail of one service. Keeping migrations next to the `ent` schema means `atlas migrate diff` operates on a single working tree, and the migration ships in the same PR as the code that depends on it.

### Migration application — at service startup, guarded by Atlas's Postgres advisory lock

When a Core Domain pod starts, the binary runs `atlas migrate apply` against the configured database before opening the HTTP listener. If migrations fail, the pod exits non-zero and Kubernetes restarts it; the deploy fails loudly.

Concurrency safety: **Atlas acquires a Postgres advisory lock** before checking the migration state. When N pods start simultaneously (the normal case during a blue/green cutover with multiple replicas), exactly one acquires the lock and applies pending migrations; the others block, then see "nothing to apply" once the lock releases. This is Atlas's documented behavior and is the mechanism that makes startup migrations safe for multi-replica services.

This is the only concurrency control. No init containers, no separate migration Jobs, no Kubernetes Leases. The application binary owns its schema.

### Migration naming convention

Atlas's default timestamp-prefixed format, with the MTP task ID and a short description:

```
20260517143022_MTP-014_add_user_email_verified.sql
```

This makes every migration traceable to a ticket and consistent with the branch-naming rule from the methodology session.

### CI lint — `atlas migrate lint` on every PR

`atlas migrate lint` runs in CI on every PR that touches `motifpath-core`. It catches a meaningful subset of the dangerous patterns automatically:

- Destructive changes (drops without prior deprecation).
- Non-backward-compatible operations (adding `NOT NULL` without a default, type changes that lose data).
- Missing `IF NOT EXISTS` guards where they would matter.

Lint failures block the PR. It does not replace the developer discipline this ADR depends on — it catches the careless mistakes before they reach review, and it makes the discipline easier to maintain because the obvious traps are flagged automatically.

Atlas lint is configured to compare each PR's migrations against the `main` branch's migration history.

### Local development — same Atlas, different connection string

Atlas applies migrations against the local k3d Postgres exactly the same way it does in production. Same `atlas migrate apply` command, same migration files, different `DATABASE_URL`. There is no separate "dev migrations" path that could diverge from production.

Local schema reset is `atlas schema clean` followed by `atlas migrate apply` — a single make target.

### Rollback model — inherited from ADR-004

This ADR adds nothing to rollback. ADR-004 already established that:

- Rollback = redeploy the previous container image.
- The schema stays at the new version.
- The old application code works because of the backward-compatible migration discipline.
- Data correction, if needed, is a deliberate forward migration written for the specific situation.

Down migrations are **not generated, not maintained, not used**. `atlas migrate down` is treated as a footgun, not a feature. The temptation to use it in incidents is precisely why it should not be available.

### Drift detection — deferred

Atlas can detect drift between the declared schema and the actual production database via `atlas migrate status`. This catches the case where someone (you) hotfixes the database directly during an incident and forgets to write a follow-up migration.

This is **deferred** at MVP because:

- Setup requires running scheduled checks against production credentials — meaningful pipeline work for a low-probability event.
- On a solo team with no direct DB access in normal workflow, the probability of *unauthorized* drift is low.
- The probability of *authorized but forgotten* drift exists but is bounded.

Trigger for revisiting: **the first time drift actually occurs**, whether caught manually or only realized later. At that point the setup cost has been paid for in incident time and drift detection becomes obviously worth it.

## Consequences

### Positive

- **Atlas's advisory lock makes startup migrations safe** under blue/green without any custom locking, leader election, or Job orchestration.
- **One PR, one schema change.** The `ent` definition and the migration file live in the same commit, eliminating the "schema and migration out of sync" failure mode.
- **CI lint provides automated safety net** for the most common backward-compatibility mistakes, reducing what the developer discipline alone has to catch.
- **Local and production migration paths are identical** — no environment-specific migration code or workflow.
- **No down migrations** means there is no operational temptation to run dangerous rollback paths during incidents.
- **Migration tooling stays inside the `ent` ecosystem.** No custom glue between an unrelated migration tool and the ORM.

### Negative

- **Atlas is a single-vendor dependency.** If Ariga changes direction or licensing, the project is coupled to that change. Mitigation: migration files are plain SQL — the *files* outlast Atlas if migration to another tool becomes necessary; only the workflow tooling is replaced.
- **No automated enforcement of expand-migrate-contract semantics.** `atlas migrate lint` catches *some* violations, not all. A subtly non-backward-compatible migration can pass lint and still break blue/green cutover. The developer (you) remains the final line of defense.
- **Drift detection deferral is a known risk.** A manually applied DB change that is later forgotten will cause confusion the next time `atlas migrate diff` runs against a divergent schema. Acceptable at MVP, not acceptable forever.
- **Atlas advisory lock holds during long migrations.** A slow migration delays all replica startups. At MVP scale (small schema, small data) this is negligible; at scale, long migrations would need to be split (relates back to expand-migrate-contract — long migrations are usually backfills that should not run at startup at all).

### Neutral

- **Migration files in `motifpath-core` are not visible to consumers of the contracts repo.** This is intentional. If a contract-level concept (e.g. an event schema) needs schema-level representation in `motifpath-core`, the contract change lives in `motifpath-specs` and the schema change that implements it lives in `motifpath-core`. The two are reviewed together but versioned separately.

## Evolution path

| Trigger event | Decision to revisit |
| --- | --- |
| First migration that requires hours of runtime against production data | Move long-running migrations out of startup; introduce a one-shot Job pattern for backfills while keeping schema changes at startup |
| First manual DB hotfix that is later forgotten | Enable Atlas drift detection in CI as a scheduled check against production |
| First migration that cannot be made backward-compatible without unacceptable engineering cost | Reconsider whether `ent` is the right ORM at scale, or whether a maintenance-window deploy pattern needs to be formalized |
| Schema grows to dozens of tables and migrations | Reconsider whether `atlas migrate lint` rules need to be tightened, or whether team-level migration review needs explicit checklists |

## Alternatives Considered

### 1. Init container or dedicated Job for migrations

Pull migration execution out of the service binary into a separate init container, or run a one-shot Job before the application rollout.

**Rejected** because it adds operational complexity (more pod state to reason about, separate failure modes for "migration container OK but app container fails to start") without buying meaningful safety beyond what Atlas's advisory lock already provides. The Job pattern would also contradict ADR-004's "startup migrations" commitment.

### 2. Application-startup auto-migrate via `ent`'s built-in `Schema.Create`

`ent` ships a built-in `client.Schema.Create(ctx)` that introspects the live database and applies the changes needed to match the schema definition. No versioned files, no migration history.

**Rejected** because it is non-deterministic ("what changes will it make?"), unreviewable (no SQL artifact to inspect), and unsafe for production (destructive changes are applied without warning). Acceptable for prototyping, dangerous for anything else.

### 3. golang-migrate or goose with hand-written SQL

Tool-agnostic SQL migrations, no `ent` integration.

**Rejected** because it requires hand-authoring SQL that mirrors `ent` schema changes — a duplication that drifts. Atlas's `migrate diff` against the `ent` schema definition is precisely the integration that makes this duplication go away.

### 4. Atlas declarative schema (HCL) instead of `ent` schema-as-code

Atlas supports declarative schema files in HCL as the source of truth, with `ent` as a consumer.

**Rejected** because it inverts the normal `ent` workflow. The `ent` schema is already the source of truth for the application code that uses it; adding a parallel HCL definition is redundant and creates a synchronization problem.

### 5. Generating and maintaining down migrations

`atlas migrate diff` can emit down migrations alongside up migrations.

**Rejected** for the reasons in ADR-004 — running down migrations against production data is more dangerous than rolling forward, and maintaining them creates the temptation to use them in incidents. The backward-compatible migration discipline plus image-redeploy rollback is the safer path.

## References

- Platform Architecture — MVP (Notion): `35e9ccc1-102f-8134-8918-d8d853b81f9c`
- ADR-003: OpenTelemetry instrumentation with deferred backend
- ADR-004: Deployment pipeline — dev → staging → production
- `ent` migrations documentation: <https://entgo.io/docs/migrate>
- Atlas documentation: <https://atlasgo.io/>
- Atlas migrate lint: <https://atlasgo.io/versioned/lint>
