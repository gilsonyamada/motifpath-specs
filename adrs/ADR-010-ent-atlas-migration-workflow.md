# ADR-010: Atlas CLI for ent Schema Migration Workflow

**Status:** Proposed
**Date:** 2026-06-12
**Deciders:** Gilson Yamada (product/engineering lead)

---

## Context

ADR-005 decided that the Core Domain Service uses `ent` as its ORM and Atlas for schema
migrations, with a distributed startup lock to prevent concurrent migration runs. ADR-005 did
not specify the exact developer workflow for generating and applying migrations — that is,
how a schema change moves from an `ent` schema definition to a versioned SQL file to a running
database. This ADR fills that gap.

Three options were evaluated:

1. **Atlas CLI with `atlas migrate diff`** — The Atlas CLI inspects the current ent schema and
   the current state of the migrations directory, then generates a new versioned SQL migration
   file for any detected delta. Migration files are committed to the repository alongside the
   schema change. At service startup, `atlas migrate apply` runs all pending files against the
   target database in order.

2. **`ent` auto-migrate (`schema.Create()`)** — `ent` can apply schema changes automatically
   at startup by calling `client.Schema.Create(ctx)`. No migration files are generated; the ORM
   diffs the live schema against the model and issues the necessary DDL statements directly.

3. **Manual SQL migrations** — Developers write SQL migration files by hand, numbered sequentially.
   A lightweight runner (e.g., `goose`) applies them at startup.

## Decision

MotifPath will use the **Atlas CLI** to generate and apply versioned SQL migration files for the
Core Domain Service.

The workflow is:

1. A developer modifies an `ent` schema file under `internal/adapters/repo/ent/schema/`.
2. The developer runs `make migrate:diff name=<short-description>`, which invokes
   `atlas migrate diff` and writes a new timestamped SQL file to
   `internal/adapters/repo/ent/migrate/migrations/`.
3. The migration file is reviewed and committed in the same PR as the schema change.
4. At service startup, the `cmd/main.go` entrypoint calls `atlas migrate apply` before the HTTP
   server starts, guarded by the distributed lock from ADR-005.
5. CI validates that the migrations directory is in sync with the ent schema on every PR
   (`atlas migrate lint`).

The Atlas CLI is added to `devbox.json` as a required tool.

## Rationale

`ent` auto-migrate was rejected for production use despite its convenience in local development.
Auto-migrate applies DDL changes directly without a reviewable artefact. There is no migration
history, no ability to run `EXPLAIN` on a migration before it lands in production, and no way to
detect destructive changes (column drops, type changes) before they execute. ADR-005 explicitly
requires startup-time migration with a distributed lock; auto-migrate satisfies the lock
requirement but fails the reviewability requirement.

Manual SQL migrations were rejected because they duplicate work already done by `ent`. When a
developer adds a field to an `ent` schema, manually writing the corresponding `ALTER TABLE` is
error-prone and adds no value over letting Atlas generate it from the schema diff.

The Atlas CLI was chosen because it bridges both concerns: migration files are generated
automatically (no hand-written SQL for routine changes) and committed explicitly (reviewable,
ordered, versioned). The `atlas migrate lint` CI check prevents a common error — committing a
schema change without its corresponding migration file.

## Consequences

### Positive
- Every schema change has a reviewable SQL artefact in the same PR, before it touches any database.
- Migration history is durable and auditable via git.
- `atlas migrate lint` in CI eliminates the class of "forgot to generate the migration" errors.
- Atlas handles complex DDL (index creation, constraint changes) that `ent` auto-migrate sometimes
  handles incorrectly on Postgres.

### Negative / Trade-offs
- The Atlas CLI must be present in `devbox.json` and in CI. This adds one tool to the
  development environment setup.
- Developers must run `make migrate:diff` after every `ent` schema change. Forgetting blocks CI.
- Atlas versioned migrations are append-only. Correcting a bad migration requires a new migration
  file, not editing the old one — this is the correct behaviour but surprises developers
  unfamiliar with the pattern.

### Neutral
- `ent` auto-migrate remains available and is used in the test environment where testcontainers
  spin up a fresh Postgres instance per test run. In that context, no migration history is needed
  and auto-migrate is the fastest path to a clean schema.
- The `make migrate:diff` target wraps Atlas with the correct ent loader flags so developers
  do not need to remember the full Atlas CLI invocation.

## Related ADRs

- ADR-005: Database migration — Atlas + ent, startup lock — this ADR specifies the developer
  workflow that ADR-005 left open.
- ADR-004: Deployment pipeline — migration files must pass `atlas migrate lint` as a required
  CI check before any PR targeting the Core Domain Service merges.

---

*This ADR was decided on 2026-06-12. To revise, create a new ADR with Status: Supersedes ADR-010.*
