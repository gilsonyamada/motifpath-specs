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
- Learning loop (`LEARNING.md`) with an explicit **capture gate** (Section 0)
  that filters findings before they become shared lessons — tighter than the
  reference skill's five-trigger capture model, by design: this is a small
  team sharing one `motifpath-specs` repo, and unfiltered capture would make
  the shared memory noisy for everyone, not just for one reviewer.
- Git-sharing mechanism for lessons: Phase 8 stages lesson/heuristics/metrics
  changes and drafts a Conventional Commit, but always stops for explicit
  user confirmation before committing or pushing — never automatic.
- GitHub platform adapter (`PLATFORM.md`) using the `gh` CLI as primary, with
  `mcp__github__*` tools as fallback.
- Profiles for all four MotifPath repos (`motifpath-core`, `motifpath-web`,
  `motifpath-infra`, `motifpath-specs`), seeded with evidence from each
  repo's own `CLAUDE.md`, plus `profiles/ROUTING.md` and `_TEMPLATE.md` for
  bootstrapping new scopes.
- `--dry-run` mode for reviewing a proposal or spec before code exists,
  intended to pair with `plan-writer` output and with `motifpath-specs`
  spec PRs.
