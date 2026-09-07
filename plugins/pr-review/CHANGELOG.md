# PR Review — Changelog

## [1.2.0] — 2026-09-07

### Changed
- Updated every reference to the ADR directory from `motifpath-specs/adr/` to
  `motifpath-specs/adrs/` (SKILL.md Phase 2, `motifpath-infra` and `_TEMPLATE`
  profiles), and rewrote the `motifpath-specs` profile's ADR-format row to match
  the reconciled `CLAUDE.md` (location `adrs/ADR-NNN-...`, Status line + Context/
  Decision/Consequences/Rationale, `adr-writer` skill as the authoring source of
  truth). `adr/ADR-001`–`014` were physically moved into `adrs/` alongside
  ADR-015; the split directory and the stale `CLAUDE.md` rule were the
  inconsistency.
- Bumped `SKILL.md` `version` to 1.2.0 to match `plugin.json` (it had been left
  at 1.0.0 when the plugin moved to 1.1.0).

## [1.1.0] — 2026-08-25

### Changed
- Widened `PLATFORM.md`'s pagination invariant (#3) to explicitly cover
  `list_files`, not just `list_discussion`. Caught live on motifpath-core#2:
  `mcp__github__get_pull_request_files` silently returned only the first 30
  of 40 changed files (GitHub's API default page size), which omitted the
  new `internal/domain/` and `internal/ports/` packages and nearly produced
  a false "this doesn't compile" blocking finding before a `per_page=100`
  re-fetch showed the full file list was fine.

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
