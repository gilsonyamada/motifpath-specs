# Profile: motifpath-infra

## Identification

- Repository / path scope: `motifpath/motifpath-infra` (single repo).
- Local reference repo: `motifpath-infra` checkout.
- Comment language: English.
- Stack in one line: Terraform, AWS (EKS, RDS Postgres, MongoDB Atlas, ECR), state in S3 +
  DynamoDB locking.

## Sources of intent

- ADRs in `motifpath-specs/adr/` for any architectural infra decision.
- Backlog item: task code in the branch name (`feat/MTP-NNN/...` or `infra/MTP-NNN/...`), per the
  `git` skill.
- Fallback: ask the user for the activity's context.

## Local norms (with evidence)

| Norm | Evidence |
|---|---|
| No inline resource configs — always extract to a module under `/modules/` | `motifpath-infra/CLAUDE.md` — Terraform Standards |
| Every provider version-pinned in `required_providers` — no floating versions | `motifpath-infra/CLAUDE.md` — Terraform Standards |
| State lives in S3 with DynamoDB locking — never a local state file | `motifpath-infra/CLAUDE.md` — Terraform Standards |
| Every resource tagged with `environment`, `project = "motifpath"`, `managed-by = "terraform"` | `motifpath-infra/CLAUDE.md` — Tagging Policy |
| No hardcoded secrets/credentials/connection strings — always via AWS Secrets Manager; sensitive outputs use `sensitive = true` | `motifpath-infra/CLAUDE.md` — Secrets |
| `.tfvars` files with sensitive values are gitignored — never committed | `motifpath-infra/CLAUDE.md` — Secrets |
| Staging is tested before production; staging and production use separate state files and separate AWS accounts | `motifpath-infra/CLAUDE.md` — Environment Rules |
| Never `terraform apply -auto-approve`, in any environment | `motifpath-infra/CLAUDE.md` — Key Rules |
| Never destroy a production resource without an explicit ADR | `motifpath-infra/CLAUDE.md` — Key Rules |
| `for_each` over `count` for resource collections | `motifpath-infra/CLAUDE.md` — Key Rules |
| Every module variable has a `description` | `motifpath-infra/CLAUDE.md` — Key Rules |
| MSK (Kafka) is explicitly deferred — do not provision yet | `motifpath-infra/CLAUDE.md` — Purpose |
| A production `terraform apply` requires a reviewed, approved plan **in the PR** — even a hotfix must show the plan first | `motifpath-infra/CLAUDE.md` — Environment Rules, Branching |

## Boundaries

- **Public contract:** module input/output interfaces consumed by environment configs — changing a
  module's inputs without updating both `environments/staging` and `environments/production` is a
  Phase 4a item-12 finding (every entry door for the data).
- **Tolerated legacy:** none documented yet — ask the user before treating anything as
  grandfathered.
- **Automatic gates (don't re-flag):** whatever `terraform validate`/`terraform fmt` enforces in CI
  (exact command not yet confirmed — read on first bootstrap).

## Tests

- No automated test suite documented — the review substitute for tests here is the `terraform plan`
  output attached to the PR. A PR touching `environments/production` with no plan output is itself
  a blocking finding (mirrors `motifpath-infra/CLAUDE.md` — Environment Rules).

## Delivery

- Feature/fix/chore branches target `dev`; only `hotfix/BUG-NNN/...` branches from `main` directly —
  and an infra hotfix still requires a `terraform plan` review before applying; urgency never skips
  the plan step. (`motifpath-infra/CLAUDE.md` — Branching)

## Bootstrap notes

Seeded from `motifpath-infra/CLAUDE.md` on 2026-08-25 — not yet confirmed against a live review.
Exact `terraform fmt`/`validate` CI command and PR template still need to be read from the repo's CI
config and confirmed with the user on first use.
