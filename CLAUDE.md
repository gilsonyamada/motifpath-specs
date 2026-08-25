# MotifPath Specs — Claude Code Instructions

## Purpose
Single source of truth for all contracts in the MotifPath platform.
Changes here propagate to all consuming repositories before any implementation begins.

## Repository Structure
```
/openapi      → REST API specs (OpenAPI 3.1 YAML), event schemas at
                openapi/components/schemas/events.yaml
/features     → Business rule specs (Gherkin .feature files, nested per domain)
/adr          → Architecture Decision Records
/prompts      → Versioned AI task prompts
/evals        → Golden sets for PromptFoo evaluation
/plugins      → Claude Code skills for the whole team (plugin marketplace)
```

## Spec-First Discipline
ALWAYS write or update specs BEFORE any implementation begins in other repos.
A feature is not ready for development until it meets the Definition of Ready below.
NEVER create a spec that references implementation details (SQL, HTTP internals, framework names).

## Definition of Ready
A feature spec is ready when ALL of the following are true:
- OpenAPI endpoint(s) defined (if the feature has an HTTP surface)
- Gherkin scenarios cover: happy path + at least 2 edge cases + at least 1 failure case
- PO has reviewed and approved business rule accuracy (not just Gherkin syntax)
- ADR exists if the feature introduces an architectural change

## Gherkin Standards
ALWAYS use domain language — never HTTP status codes, SQL, or framework names in scenarios.
ALWAYS reference domain events by exact names: lesson.started, lesson.resumed, lesson.completed,
exercise.started, exercise.progress, exercise.answer_sent, exercise.ended.
One scenario = one behavior. Never test multiple behaviors in a single scenario.
Steps must be concrete and specific — avoid vague steps like "the system processes the request".

## OpenAPI Standards
- operationId: camelCase verb + noun (e.g. submitExerciseAnswer, getStudentPath)
- All properties: snake_case with a description field — no exceptions
- Minimum responses per endpoint: 200, 400, 401
- Use enums for status fields — NEVER free strings
- Breaking changes bump major version; new endpoints bump minor; corrections bump patch
- Descriptions must be self-sufficient — NEVER reference ADR document names (e.g. "as per ADR-006") inside schema or property descriptions. The rationale belongs in the ADR; the description must stand alone for any reader without access to internal docs.

## Event Schema Standards
Event schemas live in `openapi/components/schemas/events.yaml`, referenced via `$ref`
from `openapi/event-ingestion-service.yaml` — they're validated as part of OpenAPI lint,
not as standalone JSON Schema files.
Required fields on every event: event_type, student_id, session_id, occurred_at.
NEVER add optional fields without a corresponding Gherkin scenario that exercises them.

## Prompt Files (/prompts/)
ALWAYS bump the version field when modifying a prompt file — treat it like a code change.
NEVER change prompt content without updating CHANGELOG.md.
Run `promptfoo eval` after any prompt change — CI enforces this as a required check.
Model assignments are fixed — do not change models without an ADR.

## ADR Format
File naming: /adr/NNN-short-kebab-title.md
Required sections: ## Context, ## Decision, ## Consequences
NEVER delete an ADR. Superseded decisions get a note: "Superseded by ADR-NNN".

## CI Checks (must pass before merge)
- OpenAPI validation: Redocly CLI (also validates event schemas via `$ref`)
- Gherkin syntax validation
- PromptFoo eval (runs on prompt file changes only)

## Skills (/plugins/)
Skills are Claude Code behavioral guides used by the whole team, distributed as the
`motifpath-skills` plugin marketplace (`.claude-plugin/marketplace.json` at the repo
root). Each skill is its own plugin under `plugins/<name>/`, with its own
`.claude-plugin/plugin.json`, `skills/<name>/SKILL.md`, and `CHANGELOG.md`.
ALWAYS bump the `version` field in both SKILL.md and plugin.json when modifying a skill
— the marketplace's update check depends on the plugin.json version moving.
ALWAYS add a CHANGELOG.md entry for every skill change.
NEVER delete a skill — deprecate it with a note in CHANGELOG.md.
Team members run `/plugin marketplace update motifpath-skills` (or rely on
auto-update, if enabled) then `/reload-plugins` to pick up changes — see the
repo README for first-time setup.

## Reusable Workflows (.github/workflows/)
This repo defines reusable GitHub Actions workflows consumed by all service repos.
`reusable-sync-main-to-dev.yml` — auto-opens a PR from main to dev after any merge to main.
NEVER edit caller workflows in other repos to add logic — keep logic here, callers stay minimal.