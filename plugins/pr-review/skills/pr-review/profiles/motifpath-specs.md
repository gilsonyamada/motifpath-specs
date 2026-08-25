# Profile: motifpath-specs

## Identification

- Repository / path scope: `motifpath/motifpath-specs` (single repo — this is also the repo the
  `pr-review` skill itself lives in).
- Local reference repo: `motifpath-specs` checkout.
- Comment language: English.
- Stack in one line: OpenAPI 3.1 YAML (event schemas live inside it, at
  `openapi/components/schemas/events.yaml`), Gherkin (`.feature`, nested per domain under
  `features/`), Markdown ADRs, versioned prompt files, PromptFoo evals. No application code —
  this repo IS the intent that other repos' PRs get reviewed against, which makes `--dry-run`
  mode the primary mode here (see `SKILL.md`): most `motifpath-specs` changes precede code, they
  don't follow it.

## Sources of intent

- The backlog item / PO decision behind the spec change — there's no upstream spec-of-the-spec, so
  intent usually comes directly from the user or a linked ADR.
- Fallback: ask the user what business rule or contract this change is meant to capture.

## Local norms (with evidence)

| Norm | Evidence |
|---|---|
| A feature isn't ready for implementation until its spec exists here — no reviewing "implementation-shaped" changes in this repo | `motifpath-specs/CLAUDE.md` — Spec-First Discipline |
| Specs never reference implementation details — no SQL, HTTP internals, or framework names in Gherkin or OpenAPI descriptions | `motifpath-specs/CLAUDE.md` — Spec-First Discipline |
| Gherkin: domain language only; exact event names (`lesson.started`, `lesson.resumed`, `lesson.completed`, `exercise.started`, `exercise.progress`, `exercise.answer_sent`, `exercise.ended`); one scenario = one behavior; concrete steps, never "the system processes the request" | `motifpath-specs/CLAUDE.md` — Gherkin Standards |
| Definition of Ready: OpenAPI endpoint(s) if HTTP-facing + happy path/2 edge cases/1 failure case in Gherkin + PO approval on business-rule accuracy + an ADR if architecturally significant | `motifpath-specs/CLAUDE.md` — Definition of Ready |
| OpenAPI: `operationId` camelCase verb+noun; all properties snake_case with a `description`; min responses 200/400/401; enums for status fields, never free strings; breaking = major, new endpoint = minor, correction = patch | `motifpath-specs/CLAUDE.md` — OpenAPI Standards |
| Schema/property descriptions must be self-sufficient — never reference an ADR by name inside them; the rationale belongs in the ADR | `motifpath-specs/CLAUDE.md` — OpenAPI Standards |
| Every event requires `event_type`, `student_id`, `session_id`, `occurred_at`; no optional field added without a Gherkin scenario exercising it; event schemas are validated as part of OpenAPI lint via `$ref`, not as standalone JSON Schema files | `motifpath-specs/CLAUDE.md` — Event Schema Standards |
| ADR file naming `/adr/NNN-short-kebab-title.md`; required sections `## Context`, `## Decision`, `## Consequences`; never deleted, only superseded with a note | `motifpath-specs/CLAUDE.md` — ADR Format |
| Prompt file changes always bump the version field and update the prompt's own CHANGELOG.md; PromptFoo eval must run | `motifpath-specs/CLAUDE.md` — Prompt Files |
| Skill changes always bump the version field (or `plugin.json` version, post-marketplace-migration) and add a CHANGELOG.md entry; never delete a skill, deprecate it instead | `motifpath-specs/CLAUDE.md` — Skills |

## Boundaries

- **Public contract:** any already-published OpenAPI path or event schema field — this is the
  producer side for `motifpath-core`/`motifpath-web`; check Phase 4d before treating a rename or
  field removal as safe.
- **Tolerated legacy:** none documented yet — ask the user before treating anything as
  grandfathered.
- **Automatic gates (don't re-flag):** Redocly CLI lint on `openapi/*.yaml` (this also validates
  `events.yaml` through its `$ref`), Gherkin syntax parse recursively under `features/`, PromptFoo
  eval on `prompts/` changes — all run in `.github/workflows/ci.yml`. There is no separate
  standalone-JSON-Schema event validation job; a PR proposing one is reintroducing a job this repo
  deliberately dropped (see `plugins/pr-review/CHANGELOG.md` / the PR that fixed `ci.yml`).

## Tests

- "Tests" here are the CI validations above, plus PromptFoo golden-set evals in `/evals/` for prompt
  changes. There's no unit-test layer to check coverage on.

## Delivery

- Feature/spec/chore branches target `dev`; only `hotfix/BUG-NNN/...` branches from `main` directly,
  per the `git` skill.
- A spec change that isn't yet consumed by any other repo's PR is normal, not a finding — Phase 4d
  only applies once a consumer actually exists in the same review session.

## Bootstrap notes

Seeded from `motifpath-specs/CLAUDE.md` on 2026-08-25.
