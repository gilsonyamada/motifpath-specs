# ADR-004: Deployment Pipeline — dev → staging → production

## Status

Accepted — 2026-05-17

## Context

MotifPath's deployment surface comprises:

- Two Go services in `motifpath-core` (Core Domain and Event Ingestion), deployed as containers to EKS.
- A Vue 3 SPA in `motifpath-web`, deployed as static assets to S3 + CloudFront.
- Infrastructure in `motifpath-infra` (Terraform managing EKS, RDS, ECR, and Atlas connection metadata).

CI/CD is GitHub Actions. ECR is the container registry. The branching model — established in the methodology session — is:

- `main` (protected, production)
- `dev` (protected, integration target for all feature PRs)
- Feature branches: `feat/MTP-NNN/...` from `dev`
- Hotfix branches: `hotfix/BUG-NNN/...` from `main`, with automated sync back to `dev` via `reusable-sync-main-to-dev.yml`

Three environments exist: local (Docker Compose + k3d), EKS staging, EKS production.

The pipeline must be operable by a solo developer with no second pair of eyes during deploys. It must accommodate the existing hotfix sync workflow, run within the GitHub Actions free tier, and let the frontend, backend, and infrastructure deploy independently — they have different change frequencies and different blast radii.

## Decision

### Trigger model — manual workflow dispatch, automatic execution

All environment deploys are triggered by **manual `workflow_dispatch`** in GitHub Actions. Once triggered, the workflow runs end-to-end without further intervention. "Manual" applies to the trigger, not to the steps.

- `dev` branch merged → developer manually triggers staging deploy.
- `main` branch merged → developer manually triggers production deploy.
- No automatic deploys on push at MVP.

This is a deliberate starting position. The trigger automation evolves over time (see *Evolution path* below); the workflow internals do not.

### Artifact identity — same image, different config

Container images are built once, tagged with the Git SHA, and pushed to ECR on merge to `dev`. The **same image** is promoted from staging to production. Environment differences are expressed exclusively through configuration (Kubernetes ConfigMaps, Secrets via AWS Secrets Manager, environment variables).

"Works in staging" must mean "this exact image works in staging." If a production deploy ever requires a re-build, it is a bug in the pipeline, not a normal path.

### Infrastructure — separate workflow

`motifpath-infra` deploys via its own GitHub Actions workflow, independent of application code:

- `terraform plan` runs automatically on PRs against `motifpath-infra` and posts the plan as a PR comment.
- `terraform apply` is triggered manually via `workflow_dispatch` after PR merge, with the target environment as an input parameter.
- Application pipelines do not invoke Terraform. Terraform pipelines do not deploy application code.

When an infrastructure change must land before an application change can ship, the ordering is enforced by the developer (you), not by the pipeline. The MTP-NNN task description and PR description carry the dependency.

### Deployment strategy — blue/green

Kubernetes deployments use a blue/green strategy:

- The new (green) version is rolled out to a parallel set of pods.
- Smoke checks run against green before traffic shifts.
- Service traffic cuts over from blue to green via Service selector update.
- Blue is kept warm for one deploy cycle to enable instant rollback by reverting the selector.

Rolling updates were considered (Kubernetes default) but rejected for production deploys: blue/green gives a cleaner rollback story and a clearer mental model for solo operation. Rolling updates remain acceptable for staging if the operational cost of maintaining blue/green there proves excessive.

### Migration coordination — startup migrations + backward-compatible discipline

Schema migrations run at **application startup** (the detailed strategy is ADR-005). For this to be safe under blue/green — where blue and green run simultaneously against the same database during cutover — every migration **must be backward-compatible** with the previous application version.

This is the *expand → migrate → contract* pattern enforced by developer discipline:

- Adding columns: safe (new column ignored by old code).
- Adding tables: safe.
- Renaming a column: requires two deploys — add new column populated alongside old, deploy, migrate data, deploy again to drop old column.
- Dropping a column: only after a deploy has shipped where the application no longer reads or writes it.
- Changing a type or adding NOT NULL: requires the expand-migrate-contract dance.

If a migration cannot be made backward-compatible, the deploy strategy for *that specific change* falls back to a maintenance window with explicit downtime — and that is treated as the exception, not the norm.

### Rollback model — redeploy previous image

Rollback is performed by **re-deploying the previous container image** (the previous Git SHA tag in ECR). The schema stays at the new version; the old application code is forward-compatible with it because of the backward-compatible migration discipline above.

Database state is never rolled back via down migrations as part of a deploy rollback. If data correction is needed, it is a deliberate forward migration written for the specific situation.

For the cutover window itself, rollback is even faster: revert the Service selector from green back to blue.

### Per-surface deploy independence

The three deploy surfaces — backend services, frontend SPA, infrastructure — each have their own workflow file and their own dispatch trigger. They share no required ordering at the workflow level. Coordination, when needed, is the developer's responsibility per task.

## Consequences

### Positive

- **No accidental deploys.** Manual trigger is the simplest possible gate; nothing ships unless someone (you) decides it should.
- **Same-image promotion** makes "tested in staging" a real guarantee, not a slogan.
- **Independent surfaces** mean a frontend change cannot break a backend deploy and vice versa.
- **Blue/green + redeploy-previous-image rollback** gives a fast, dependable failure recovery path that does not require database rollback.
- **Separate Terraform workflow** keeps infrastructure changes from accidentally riding along with application deploys, and keeps `terraform apply` as a deliberate act.

### Negative

- **Manual triggers add friction** for high-frequency staging deploys. At MVP this is acceptable — staging traffic is one developer testing. It becomes a problem as soon as continuous integration testing becomes meaningful (see *Evolution path*).
- **Backward-compatible migrations are a discipline tax.** Every schema change requires thinking about the previous version's behavior. There is no automated enforcement; a careless migration that violates the discipline will silently work in dev (one app version running) and break in production at cutover (two app versions running briefly).
- **Blue/green doubles pod count during cutover.** EKS resource headroom must accommodate this. At MVP scale (two services, low replica counts) the marginal cost is negligible.
- **Cross-surface coordination is manual.** Infrastructure changes that must land before application changes are tracked by ticket discipline, not enforced by the pipeline. A solo team can hold this in their head; a multi-person team eventually cannot.

### Neutral

- The pipeline does not include automated production smoke tests at MVP. Manual verification post-deploy is the substitute. This is a known gap, accepted for now.
- Observability of deploys themselves (deploy duration, frequency, failure rate) is not instrumented. Deferred until ADR-003's upgrade trigger fires.

## Evolution path

This ADR's decisions are *starting positions*, not permanent commitments. Documented triggers for revisiting:

| Trigger event | Decision to revisit |
| --- | --- |
| Integration test suite running in CI on every PR to `dev` | Make `dev` → staging trigger automatic on merge |
| First incident caused by skipped or delayed staging deploy | Same as above |
| Second developer joins the team | Cross-surface coordination becomes a pipeline concern; reconsider whether infra and app deploys need explicit ordering primitives |
| Production traffic exceeds single-pod capacity per service | Blue/green stays; staging may need its own evolution review |
| First migration that cannot be made backward-compatible without unacceptable engineering cost | Reconsider whether startup migrations remain the default, or move to dedicated migration Jobs (relates to ADR-005) |

`main` → production stays manual indefinitely. The trigger for revisiting is the establishment of automated rollback (post-ADR-003 backend selection plus deploy health signals), not a date.

## Alternatives Considered

### 1. Push-driven deploys (automatic on merge to `dev` / `main`)

Standard continuous deployment. Faster feedback, less friction, lower cognitive load per deploy.

**Rejected for MVP** because the absence of an integration test suite means a merge to `dev` is not yet a reliable signal that staging should change. Without that signal, automatic deploys would either ship broken builds or generate enough noise to be ignored. Slated for adoption once integration tests exist.

### 2. Promotion-gated (staging success unlocks production)

Build once on `dev`, deploy to staging automatically, then "promote to production" as an explicit action.

**Rejected for MVP** because it requires the `dev` → staging side to already be automatic, which (per above) it is not. Will be reconsidered at the same time as Alternative 1.

### 3. Rolling updates instead of blue/green

Kubernetes default deployment strategy. Lower resource overhead during cutover, simpler manifests, no Service selector flip.

**Rejected for production** because the rollback story is less crisp under rolling — partial rollouts complicate "is this version actually serving traffic?" and blue/green's Service-selector revert is a faster, more atomic recovery primitive. Acceptable for staging if blue/green proves operationally expensive there.

### 4. GitOps (Argo CD or Flux)

Pull-based deploys driven by Git as the source of truth. Strong industry pattern, excellent audit trail, declarative.

**Rejected for MVP** on learning-budget grounds. GitOps is a worthwhile target, but it introduces a new control plane to operate, debug, and understand at exactly the moment when attention should be on Go services, the learning graph, and Vue 3. Push-based GitHub Actions is sufficient for solo scale and keeps the deploy mental model small. Revisited if the team grows or if multi-environment promotion complexity outgrows GitHub Actions.

### 5. Down migrations as the rollback path

Generate and maintain `atlas migrate down` files for every migration.

**Rejected** because running down migrations against production data is almost always more dangerous than rolling forward with a corrective migration. Maintaining down migrations creates the temptation to use them in incidents, when the safer path is the backward-compatible discipline that lets rollback be a simple image redeploy. ADR-005 will reinforce this.

## References

- Platform Architecture — MVP (Notion): `35e9ccc1-102f-8134-8918-d8d853b81f9c`
- ADR-003: OpenTelemetry instrumentation with deferred backend
- ADR-005: Database migration strategy (`ent` in production) — *pending*
- GitHub Actions workflow_dispatch: <https://docs.github.com/en/actions/using-workflows/manually-running-a-workflow>
- Kubernetes deployment strategies: <https://kubernetes.io/docs/concepts/workloads/controllers/deployment/>
