# Global Claude Code Instructions
# Lives at: ~/.claude/CLAUDE.md
# Applies to all projects on this machine.

## Active Skills
Installed via the `motifpath-skills` Claude Code plugin marketplace (see
`motifpath-specs/README.md` for onboarding) — no manual file import needed here.
Installed plugins load automatically: git, adr-writer, ai-consultant, plan-writer,
product-discovery, project-index-maintenance, pr-review.

## Communication
Always respond in English.
Be concise and direct — prefer short explanations with code examples over long prose.
When something is ambiguous, ask one focused clarifying question before proceeding.

## Spec-Driven Development (all MotifPath repos)
The spec exists before the implementation — always.
If the spec doesn't exist yet, the feature is not ready to implement.
Check motifpath-specs before writing any handler, component, or business logic.

## Code Quality Principles
Explicit over implicit — prefer clear, readable code over clever code.
Small functions with a single responsibility.
NEVER leave TODO comments without a linked issue.
NEVER suppress linter warnings without an inline explanation.

## Testing Principles
TDD is mandatory across all MotifPath repos: write the failing test BEFORE any implementation
code, then implement to make it pass. NEVER write tests after implementation — a test written
against code you've already seen pass is biased toward that code's behavior, not the intended
behavior, and silently rubber-stamps bugs baked into the first draft.
Tests describe behavior, not implementation.
A test that only passes because of mocks isn't testing anything real.
If a test is hard to write, the code design is probably the problem.

## MotifPath Project Map
Four repositories under the motifpath org:
  motifpath-specs   → contracts (OpenAPI, Gherkin, events, prompts, evals, ADRs)
  motifpath-core    → Go monorepo (core-domain + event-ingestion services)
  motifpath-web     → Vue 3 frontend (students and teachers)
  motifpath-infra   → Terraform (EKS, RDS, MongoDB Atlas, ECR)

Specs always change before code. Code always references specs.
When in doubt about a business rule, check motifpath-specs/features/.
