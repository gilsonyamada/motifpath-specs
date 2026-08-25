# Profile: <repo/scope>

> One profile per scope (repo, or service inside the `motifpath-core` monorepo). **Discovered from
> the repository and confirmed with the user** — never written from memory.
>
> **The rule that keeps a profile honest: every norm ships with evidence.** A norm with no
> `file:line` (or a command that proves it) is the reviewer's preference, not a project norm — so it
> generates no finding.

## Identification

- Repository / path scope:
- Local reference repo (to read the surroundings of files in the diff):
- Comment language:
- Stack in one line (orients reading only, never generates a finding on its own):

## Sources of intent

Where "what should this change resolve" comes from, and how to get there:

- Spec: `motifpath-specs/openapi/`, `motifpath-specs/features/*.feature`, or `motifpath-specs/adr/`
- Ticket / backlog item: <task-code format, where it's tracked>
- Fallback: ask the user for the activity's context.

## Local norms (with evidence)

| Norm | Evidence |
|---|---|
| <e.g. business rule lives in the application layer; the entry adapter only translates protocol> | `<file:line or command>` |
| | |

Cover, where applicable: layering/module organization · naming · how logging/errors are recorded ·
how network calls are made · how config/flags are read · single source of truth for each capability
(logging, routing, network, i18n, styling) · what's explicitly forbidden.

## Boundaries

- **Public contract** (breaking it requires explicit warning and versioning):
- **Tolerated legacy** (not this change's finding):
- **Automatic gates** (CI already catches these — don't spend a comment):

## Tests

- Where they live and at what layer they should be written:
- What this project considers a valuable test (and what it doesn't):
- Coverage gates, if any:
- Naming convention: test name and data describe **behavior**, never the ticket/incident/real
  payload IDs — whoever reads it in 6 months won't have the bug's context.

## Delivery

- Title/description format, required labels, PR template checklist:
- Deploy order / dependency with other scopes:

## Bootstrap (how to discover all of the above)

1. Read the repo's instruction file (`CLAUDE.md`, `CONTRIBUTING.md`, `README.md`, style guide).
2. Read the lint/format/CI config → derives automatic gates and real prohibitions.
3. Read 2–3 representative files per layer → derives the pattern actually practiced (which can
   diverge from what's documented; **the practiced one wins**, and the divergence is a question for
   the user).
4. Read the tests of one mature module → derives layer, style, and what counts as value.
5. Read the recent history of merged changes → derives the delivery convention.
6. Present the profile to the user for confirmation before the first review that uses it.
