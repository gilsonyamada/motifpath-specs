# PR Review — Changelog

## [1.0.0] — 2026-08-25

### Added
- Initial release of the MotifPath PR review skill, adapted from an external
  generic code-review skill and rebuilt for MotifPath's four-repo layout.
- Phase-based core (SKILL.md): scope detection, intent collection, systemic
  heuristics, per-repo profile norms, cross-repo coherence checks, dedup
  against existing PR discussion, mandatory approval gate before publishing,
  single-review GitHub publishing, and a mandatory learning-loop close.
- 21-item systemic checklist (`HEURISTICS.md`) with a trigger-based activation
  table and a 24-item cap.
- Finding format and tone rules (`FINDING.md`): inline-only, empty review
  body, business-effect-first, severity levels, reproduce-before-asserting.
- Guideline capture (`LEARNING.md`) with a single filter (Section 1): a
  guideline is written down because it generalizes (survives without this
  repo's stack, phrases as a question, is falsifiable), never because it
  recurred. This is a deliberate departure from the reference skill's
  five-trigger, recurrence-tracked capture pipeline (candidate lessons,
  hit counts, promotion after a second occurrence) — for a small team
  sharing one `motifpath-specs` repo, tracking specific use cases waiting
  to "graduate" is ceremony nobody will maintain. Only durable guidelines
  are recorded, straight into `HEURISTICS.md` or a profile, on first sight.
- Git-sharing mechanism: Phase 8 stages `HEURISTICS.md`/profile changes and
  drafts a Conventional Commit, but always stops for explicit user
  confirmation before committing or pushing — never automatic.
- GitHub platform adapter (`PLATFORM.md`) using the `gh` CLI as primary, with
  `mcp__github__*` tools as fallback.
- Profiles for all four MotifPath repos (`motifpath-core`, `motifpath-web`,
  `motifpath-infra`, `motifpath-specs`), seeded with evidence from each
  repo's own `CLAUDE.md`, plus `profiles/ROUTING.md` and `_TEMPLATE.md` for
  bootstrapping new scopes.
- `--dry-run` mode for reviewing a proposal or spec before code exists,
  intended to pair with `plan-writer` output and with `motifpath-specs`
  spec PRs.
