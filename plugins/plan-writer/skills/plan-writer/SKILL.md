---
name: plan-writer
version: 1.0.0
description: >
  Write structured technical implementation plans for MotifPath features, services, and
  infrastructure changes. Trigger whenever a task requires planning before implementation —
  especially when a backlog item moves from spec to code, when a new service or significant
  module is being designed, or when the implementation path for a spec is unclear. Signals
  include: "how do we implement X?", "what's the plan for Y?", "before we write the code...",
  or any task that crosses multiple files, services, or repos. Plans produced by this skill
  link directly to OpenAPI specs, ADRs, and Gherkin scenarios in motifpath-specs. Never let
  a multi-service or cross-repo change proceed without a written plan.
---

# Plan Writer — MotifPath

## Purpose

Produce clear, actionable technical plans that bridge the gap between a spec (what the system
should do) and an implementation (how to build it). A plan answers: what do we build, in what
order, across which repos, and how do we know it's done?

---

## When to Write a Plan

Write a plan when:
- A backlog item involves more than one service or repo
- A feature requires a new OpenAPI endpoint + Gherkin scenarios + Go implementation
- An infrastructure change touches Terraform + CI/CD pipelines
- The implementation order matters (e.g., schema migration before service deployment)
- A task has dependencies that need to be resolved sequentially

Do NOT write a plan for:
- Single-file changes with obvious implementation
- Bug fixes with a clear, isolated root cause
- Documentation-only changes

---

## Repository Context

MotifPath uses four repos. Plans must specify which repos are touched and in what order:

| Repo | Stack | Purpose |
|---|---|---|
| `motifpath-specs` | YAML, Gherkin, Markdown | Specs, ADRs, OpenAPI, events, skills |
| `motifpath-core` | Go monorepo | Core Domain Service + Event Ingestion Service + Aggregation Worker |
| `motifpath-web` | Vue 3 + TypeScript | Frontend SPA |
| `motifpath-infra` | Terraform | EKS, RDS, Atlas, MSK, ECR |

**SDD Rule:** `motifpath-specs` is always updated first. No implementation before spec.

---

## Plan Template

```markdown
# Plan: [Feature or Task Name]

**Task:** MTP-XXX
**Date:** YYYY-MM-DD
**Author:** [Name or role]
**Status:** Draft | Ready | In Progress | Done

---

## Goal

[1–2 sentences. What does this plan deliver? What user or system need does it address?
Be specific — reference the backlog item or ADR this plan implements.]

## Scope

**In scope:**
- [Concrete deliverable 1]
- [Concrete deliverable 2]

**Out of scope:**
- [What is explicitly NOT included, and why]

## Prerequisites

- [ ] [ADR-NNN accepted / spec file committed / infra change deployed]
- [ ] [List anything that must be true before this plan can start]

---

## Implementation Steps

### Phase 1 — Spec (motifpath-specs)

**Branch:** `feat/MTP-XXX/short-description`

- [ ] Step 1: [e.g., Add OpenAPI schema for EventEnvelope to openapi/components/schemas/events.yaml]
- [ ] Step 2: [e.g., Define POST /events endpoint in openapi/services/event-ingestion/openapi.yaml]
- [ ] Step 3: [e.g., Write Gherkin scenarios in features/event-ingestion/ingest-event.feature]

**Definition of Ready check:**
- [ ] OpenAPI endpoint(s) defined
- [ ] Gherkin: happy path + 2 edge cases + 1 failure case
- [ ] ADR exists if this introduces an architectural change

---

### Phase 2 — Backend (motifpath-core)

**Branch:** `feat/MTP-XXX/short-description`

- [ ] Step 1: [e.g., Run oapi-codegen to generate Go types from updated spec]
- [ ] Step 2: [e.g., Implement handler in internal/application/]
- [ ] Step 3: [e.g., Write table-driven tests with testify]
- [ ] Step 4: [e.g., Write godog step definitions for Gherkin scenarios]
- [ ] Step 5: [e.g., Run testcontainers integration tests]

**Coverage gate:** 80% on `internal/application/` — CI fails below this.

---

### Phase 3 — Frontend (motifpath-web) [if applicable]

**Branch:** `feat/MTP-XXX/short-description`

- [ ] Step 1: [e.g., Run openapi-typescript to generate types from spec]
- [ ] Step 2: [e.g., Implement Vue component]
- [ ] Step 3: [e.g., Wire API calls]

---

### Phase 4 — Infrastructure (motifpath-infra) [if applicable]

**Branch:** `feat/MTP-XXX/short-description`

- [ ] Step 1: [e.g., Add MSK topic to Terraform module]
- [ ] Step 2: [e.g., Update EKS task definition for new service]
- [ ] Step 3: [e.g., Apply to dev environment first]

---

## Rollback Plan

[What to do if this change needs to be reverted. Reference ADR-004 (blue/green deployment)
for service rollbacks. Note any migration steps that cannot be rolled back automatically.]

## Validation

[How do we know this plan succeeded?]
- [ ] [e.g., POST /events returns 202 for all 7 event types]
- [ ] [e.g., Kafka consumer group lag is 0 after load test]
- [ ] [e.g., MongoDB events collection contains correctly structured documents]

---

## Open Questions

| Question | Owner | Resolution |
|---|---|---|
| [Question that blocks implementation] | [Who answers it] | [Answer, once known] |

---

## Related

- **ADR:** [ADR-NNN link]
- **Spec files:** [list of spec files this plan implements]
- **Backlog item:** MTP-XXX
```

---

## File Location

Plans live in:

```
motifpath-specs/
  plans/
    MTP-XXX-short-description.md
```

**Naming:** `MTP-XXX-short-description.md` — always prefixed with the task code.

---

## Git Workflow

Plans are committed to `motifpath-specs` on a feature branch:

```bash
git checkout dev
git pull origin dev
git checkout -b feat/MTP-XXX/plan-short-description

touch motifpath-specs/plans/MTP-XXX-short-description.md
# Write the plan

git add motifpath-specs/plans/MTP-XXX-short-description.md
git commit -m "feat(plans): add implementation plan for MTP-XXX [MTP-XXX]"
git push origin feat/MTP-XXX/plan-short-description
```

---

## Quality Criteria

A plan is ready to act on when:

- [ ] Goal is stated in one or two sentences — not a paragraph
- [ ] Scope is explicit — "out of scope" prevents scope creep during implementation
- [ ] Prerequisites are checkable — no vague dependencies
- [ ] Each phase has concrete, actionable steps — no steps like "implement the feature"
- [ ] Definition of Ready is checked before Phase 2 starts
- [ ] Open questions are listed, not embedded in prose
- [ ] Validation criteria are observable, not subjective

---

## Anti-Patterns to Avoid

- **Spec-free plans:** Never write Phase 2 steps before Phase 1 is committed. Spec first.
- **Missing rollback:** Every service change needs a rollback path — even if it's just "redeploy previous image per ADR-004."
- **Vague validation:** "It works" is not a validation criterion. Name the observable outcome.
- **Cross-service steps in one phase:** If a step touches two services, split it into two steps in separate phases to make dependencies explicit.
