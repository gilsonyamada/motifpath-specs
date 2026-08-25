---
name: git-workflow
version: 1.1.0
description: >
  Enforce MotifPath git conventions across all repositories — automatically and proactively.
  Trigger on any git-related task: writing commit messages, naming branches, creating PR
  descriptions, staging changes, reviewing diffs, or planning a feature branch. Apply
  Conventional Commits format, MotifPath branch naming conventions (with mandatory task codes),
  atomic commit discipline, SDD gate checks, dev-branch flow, and PR structure — without
  waiting to be asked. When a developer's input violates a pattern, correct it and briefly
  explain why. This skill applies to all four MotifPath repositories:
  motifpath-specs, motifpath-core, motifpath-web, motifpath-infra.
---

# MotifPath Git Workflow Skill

## Purpose

Enforce consistent, auditable git hygiene across the MotifPath team. Every commit,
branch, and PR should be readable by any team member without context — and traceable
back to a spec, ADR, or backlog item.

This skill activates automatically on any git-related task and corrects patterns silently
inline. One brief explanation per correction — not a lecture.

---

## When to Activate

Trigger on any of the following — even if the user didn't explicitly ask for git guidance:

| Signal | Example |
|---|---|
| Writing a commit message | "commit this with message 'fixes stuff'" |
| Naming a branch | "create a branch for the node unlocking feature" |
| Staging changes | "what should I commit first?" |
| Writing a PR description | "help me write the PR description" |
| Planning a feature | "I'm starting work on threshold overrides" |
| Reviewing a diff | "what changed in this file?" |
| Resolving a conflict | "how do I fix this merge conflict?" |
| Pushing to main | any suggestion to commit directly to main or dev |
| Merging without PR | any suggestion to merge a feature branch without a PR |

When a pattern violation is detected, flag it with:

> 🔀 **Git:** [correction + one-line reason]

Keep the flag inline and brief. Apply the correct pattern in the output.

---

## Conventional Commits

Every commit message follows this format — no exceptions:

```
<type>(<scope>): <short description>

[optional body]

[optional footer]
```

### Types

| Type | Use for |
|---|---|
| `feat` | A new feature or capability |
| `fix` | A bug fix |
| `test` | Adding or updating tests |
| `refactor` | Code change that neither fixes a bug nor adds a feature |
| `chore` | Maintenance tasks, dependency updates, regenerating code |
| `docs` | Documentation only — README, CLAUDE.md, comments |
| `ci` | Changes to GitHub Actions workflows |
| `adr` | Adding or updating an Architecture Decision Record |
| `spec` | Adding or updating specs in motifpath-specs |
| `style` | Formatting only — no logic change |
| `perf` | Performance improvement |

### Scopes (MotifPath-specific)

Scopes map to the service or module being changed:

| Scope | Used in repo |
|---|---|
| `node-unlocking` | motifpath-core |
| `student-path` | motifpath-core |
| `threshold` | motifpath-core |
| `exercise-scoring` | motifpath-core |
| `event-ingestion` | motifpath-core |
| `lesson` | motifpath-core |
| `teacher` | motifpath-web |
| `student` | motifpath-web |
| `auth` | motifpath-web |
| `codegen` | motifpath-core, motifpath-web |
| `bdd` | motifpath-core |
| `openapi` | motifpath-specs |
| `events` | motifpath-specs |
| `features` | motifpath-specs |
| `prompts` | motifpath-specs |
| `skills` | motifpath-specs |
| `eks` | motifpath-infra |
| `rds` | motifpath-infra |
| `atlas` | motifpath-infra |

Scope is required for `feat` and `fix`. Optional for other types.

### Short Description Rules

- Lowercase, no period at the end
- Imperative mood: "add", "fix", "update" — not "added", "fixes", "updating"
- 72 characters max on the first line
- Describes what the commit does, not what you did

### Good vs Bad Examples

```
✅ feat(threshold): apply teacher override before default threshold
✅ fix(exercise-scoring): correct boundary comparison at exactly 80%
✅ test(student-path): add table-driven cases for locked node access
✅ chore(codegen): regenerate oapi-codegen stubs after spec update
✅ spec(features): add node-unlocking scenarios for teacher override
✅ adr: add ADR-003 for Go monorepo decision
✅ ci: add coverage gate to core service workflow

❌ fix: fixed the bug          → vague, past tense
❌ feat: node unlocking stuff  → vague description
❌ WIP: working on this        → never commit WIP
❌ update files                → no type, no description
❌ feat: Add node unlocking.   → uppercase, period at end
```

### Commit Body (when to include)

Include a body when:
- The "why" is not obvious from the description
- The change has a non-trivial consequence that reviewers should know
- The commit references a spec, ADR, or Gherkin scenario

```
feat(threshold): apply teacher override before default threshold

Teacher overrides must take precedence over node defaults to support
differentiated instruction. The override check now runs first in the
application layer before falling back to the node's default value.

Implements: motifpath-specs/features/threshold-override.feature (GG-003)
```

### Breaking Changes

Add a `BREAKING CHANGE:` footer for any change that breaks an existing API contract:

```
feat(openapi): rename student_accuracy to accuracy_percentage

BREAKING CHANGE: The field student_accuracy has been renamed to
accuracy_percentage across all exercise endpoints. Consumers must
update their request and response handling.
```

---

## Branch Naming

All branches include three parts: **type**, **task code**, and **short description**.
The task code is mandatory — every task (feature, bug, technical debt, ADR) must have
a code before work begins. This makes every branch traceable to a backlog item.

```
type/CODE-NNN/short-description
```

### Format Rules

- Lowercase only — no camelCase, no underscores
- Task code: uppercase prefix + zero-padded number (e.g. `MTP-001`, `BUG-042`)
- Description: 3 to 6 words, kebab-case
- Always branch FROM `dev` — never from `main` directly

### Type Prefixes

| Prefix | Use for |
|---|---|
| `feat` | New feature |
| `fix` | Bug fix |
| `chore` | Maintenance, codegen, dependency updates |
| `docs` | Documentation only |
| `test` | Test additions or corrections |
| `refactor` | Refactoring with no behavior change |
| `spec` | Spec-only changes in motifpath-specs |
| `adr` | Architecture Decision Record |
| `infra` | Infrastructure changes |
| `hotfix` | Critical production fix — branches from `main` directly |

### Examples

```
✅ feat/MTP-001/node-unlocking-teacher-override
✅ fix/BUG-042/exercise-score-boundary-comparison
✅ chore/MTP-015/regenerate-api-stubs
✅ spec/MTP-001/threshold-override-gherkin
✅ adr/MTP-008/003-go-monorepo-decision
✅ fix/BUG-007/student-path-null-prerequisite
✅ hotfix/BUG-099/student-path-crash-on-empty-graph

❌ feat/node-unlocking               → missing task code
❌ feature/MTP-001/nodeUnlocking     → "feature" not "feat", camelCase
❌ MTP-001-node-unlocking            → missing type prefix
❌ gilson/MTP-001/my-branch          → personal prefix
❌ fix/BUG-042                       → missing description
```

### Task Code Policy

NEVER create a branch without a task code. If the developer doesn't have one, flag it:

> 🔀 **Git:** Every branch requires a task code (e.g. `MTP-001`). Create a backlog
> item for this work before creating the branch — even for bugs and technical debt.
> This keeps every line of code traceable to a decision.

---

## Protected Branches and Dev Flow

MotifPath uses a two-level protected branch model:

```
main  ← production-ready, protected, receives PRs from dev only
dev   ← integration branch, protected, receives PRs from feature branches
```

### Rules

- `main` is NEVER a direct PR target from a feature branch
- `dev` receives all feature, fix, chore, and spec PRs
- `main` only receives PRs from `dev` (release PRs)
- Both `main` and `dev` require at least one approved PR review before merge
- Direct commits to either `main` or `dev` are blocked by branch protection

### Full Branch Lifecycle

```
main (production)
  └── dev (integration)
        └── feat/MTP-001/node-unlocking-teacher-override
              ├── spec(features): add teacher override scenarios
              ├── feat(threshold): add override lookup to application layer
              ├── test(threshold): add table-driven cases for override precedence
              └── [PR → review → merge to dev]

        └── fix/BUG-042/exercise-score-boundary
              ├── fix(exercise-scoring): correct boundary comparison at 80%
              └── [PR → review → merge to dev]

        [multiple features accumulated in dev]
        └── [release PR: dev → main, tagged v1.1.0]
```

### Release PR (dev → main)

When `dev` is stable and ready for release, a PR from `dev` to `main` is opened.
This is the only time `main` receives a PR from `dev`. The release PR must include:

```markdown
## Release vX.Y.Z

### Included tasks
- MTP-001: Node unlocking teacher override
- BUG-042: Exercise score boundary fix
- MTP-015: API stub regeneration

### Testing
- [ ] All CI checks pass on dev
- [ ] BDD scenarios pass
- [ ] Staging deployed and verified

### Rollback plan
[How to revert if production breaks]
```

### Hotfix Flow (production-critical bugs only)

A hotfix bypasses `dev` entirely and branches directly from `main`.
Use hotfix ONLY when a bug is actively breaking production and cannot wait
for the next regular release cycle.

```
main (production)
  └── hotfix/BUG-099/student-path-crash-on-empty-graph
        ├── fix(student-path): guard against empty graph on path initialisation
        └── [PR → review → merge to main, tagged vX.Y.Z-patch]
        └── [sync-main-to-dev workflow opens PR automatically]
```

**Hotfix rules:**
- Branch FROM `main` — never from `dev`
- PR targets `main` first — gets an expedited but still mandatory review
- After merging to `main`: the `sync-main-to-dev` GitHub Actions workflow
  automatically opens a PR from `main` to `dev` — no manual step required
- Review and merge the automated sync PR promptly — never leave `dev` behind `main`
- Tag `main` with a patch version after the hotfix merges: `v1.2.1`
- Hotfix branches are deleted after the hotfix PR merges

**When NOT to use hotfix:**
> 🔀 **Git:** Hotfix is reserved for production-critical breaks. For bugs that
> can wait for the next release cycle, use `fix/BUG-NNN/description` branching
> from `dev` instead.

If a developer reaches for `hotfix` for a non-urgent bug, redirect them to the
standard `fix` flow.

---

## Atomic Commit Discipline

One commit = one logical change. NEVER mix:

- Logic changes with formatting changes
- Feature code with generated code (run `make generate` as a separate commit)
- Multiple unrelated bug fixes
- Spec changes with implementation changes

When a diff contains mixed concerns, suggest splitting:

> 🔀 **Git:** This diff mixes generated stubs with business logic. Split into two commits:
> `chore(codegen): regenerate oapi-codegen stubs` and `feat(threshold): add override lookup`.

### Generated File Commits

Generated files (`internal/adapters/http/generated/`, `src/api/generated/`) must always
be committed separately from business logic:

```
chore(codegen): regenerate oapi-codegen stubs after threshold endpoint spec update
chore(codegen): regenerate openapi-typescript types after spec update
```

---

## SDD Gate Check

Before creating a feature branch, always verify the spec exists.

When a developer starts a new feature, ask:

> 🔀 **Git:** Does a spec exist in motifpath-specs for this feature?
> Check `features/` for a Gherkin file and `openapi/` for the endpoint definition.
> A feature branch without a spec violates the Definition of Ready.

If the spec doesn't exist: suggest opening the spec PR first, before creating
the feature branch.

If the spec exists: reference it in the first commit body.

---

## PR Description Structure

Every PR description follows this template. Generate it automatically when asked to
write a PR description:

```markdown
## What

[1–3 sentences: what this PR changes]

## Why

[1–3 sentences: the reason for the change — link to backlog item if available]

## Spec

[Link to the relevant Gherkin feature file or ADR in motifpath-specs]
[Link to the OpenAPI endpoint if applicable]

## How to Test

[Steps a reviewer can take to verify the change works]
[Which Gherkin scenarios cover this]

## Checklist

- [ ] Spec exists and is referenced above
- [ ] Service-layer tests added or updated
- [ ] BDD scenarios pass locally (`make test:bdd`)
- [ ] Linter passes (`make lint`)
- [ ] Generated files committed separately (if applicable)
- [ ] No direct changes to generated files
```

### PR Size

Flag PRs with more than 400 lines changed (excluding generated files):

> 🔀 **Git:** This PR is large (N lines changed). Consider splitting: one PR for the
> spec update, one for the implementation. Smaller PRs get faster, better reviews.

---

## Anti-Patterns — Flag These Proactively

| Anti-Pattern | Flag |
|---|---|
| `WIP:` or `wip` in commit message | Never commit WIP — use a draft PR instead |
| Direct commit to `main` or `dev` | Both branches are protected — always use a PR |
| PR targeting `main` from a feature branch | Feature branches merge to `dev` only |
| Branch without a task code | Every branch requires a backlog item code |
| `fix: fix` or `update: update` | No information — rewrite with specifics |
| Mixed logic + formatting in one commit | Split into two commits |
| Generated files mixed with business logic | Split into separate commits |
| Commit message in past tense | Use imperative: "add" not "added" |
| No spec reference on a feature commit body | Add `Implements:` footer pointing to spec |
| PR with no description | Generate description from the commit history |
| TODO comment without a linked issue | Replace with a GitHub issue reference |
| `//nolint` without explanation | Add inline comment explaining the specific reason |
| Release PR missing rollback plan | Every dev → main PR must define a rollback strategy |
| Hotfix branch targeting `dev` | Hotfixes target `main` first — automation syncs to `dev` |
| Hotfix for non-critical bugs | Only production-breaking issues justify a hotfix |
| Ignoring the automated sync PR | Review and merge the sync PR promptly — never leave `dev` behind `main` |

---

## Flow Summary

```
main (protected — production only)
  │
  ├── dev (protected — integration)
  │     └── feat/MTP-001/node-unlocking-teacher-override  →  PR to dev
  │     └── fix/BUG-042/exercise-score-boundary           →  PR to dev
  │     └── spec/MTP-001/threshold-override-gherkin       →  PR to dev
  │     └── [release PR: dev → main, tagged vX.Y.Z]
  │
  └── hotfix/BUG-099/student-path-crash  →  PR to main (urgent)
                                         →  sync-main-to-dev workflow
                                            opens PR to dev automatically
```

Rules:
- `main` and `dev` are always protected — no direct commits, ever
- All feature work branches from `dev` and targets `dev`
- `main` only receives PRs from `dev` (releases) or `hotfix/*` (critical fixes)
- After any hotfix merges to `main`, it must also merge to `dev` immediately
- Feature branches are short-lived — days, not weeks
- Draft PRs for work-in-progress needing early feedback
- Squash merge for noisy intermediate commits
- Merge commit for branches where history matters

## Code Review

The git skill handles PR workflow and structure only.
For code quality review, delegate to the `pr-review` skill/plugin — it detects which
of the four MotifPath repos (or which service inside the `motifpath-core` monorepo)
a PR touches and applies the matching profile automatically, so one skill covers
all four repos instead of a separate review skill per stack.

When a developer asks for a code review and `pr-review` isn't active, apply general
review principles as a fallback: correctness, test coverage, spec conformance, naming
clarity — and suggest activating `pr-review` for a deeper, repo-aware review.

---

## Tone

Be direct and brief. One correction, one reason. Then apply the correct pattern
in the output — don't make the developer do it themselves.

Never block the developer's flow with long explanations. If they want to understand
the "why" more deeply, they'll ask.
