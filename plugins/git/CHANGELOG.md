# Git Skill — Changelog

All changes to the MotifPath git workflow skill are recorded here.
This skill is distributed as the `git` plugin in the `motifpath-skills` marketplace —
run `/plugin marketplace update motifpath-skills` (or let auto-update run) to pick up
changes, then `/reload-plugins` to activate them in the current session.

---

## [1.1.0] — 2026-08-25

### Changed
- Code Review delegation section now points to the new `pr-review` skill/plugin
  instead of the four placeholder tech-stack review skills (`go-review`,
  `vue-review`, `infra-review`, `spec-review`), which were never built.
  `pr-review` detects repo/scope automatically and covers all four repos with
  per-repo profiles, so the separate skills are no longer planned.
- Migrated from a manually-copied `~/.claude/skills/git/` file to the `git`
  plugin inside the `motifpath-skills` marketplace at
  `motifpath-specs/.claude-plugin/marketplace.json` (see the repo README for
  the new onboarding steps).

## [1.0.0] — 2026-05-17

### Added
- Initial release of the MotifPath git workflow skill
- Conventional Commits enforcement with MotifPath-specific types and scopes
- Branch naming with mandatory task codes: `type/CODE-NNN/short-description`
- Two-level protected branch model: `main` (production) and `dev` (integration)
- Hotfix flow — branches from `main` directly, automated sync back to `dev`
  via the `sync-main-to-dev` GitHub Actions workflow
- Release PR template (dev → main) with rollback plan requirement
- Task code policy — every branch must reference a backlog item
- Atomic commit discipline — flags mixed concerns
- SDD gate check — prompts spec verification before feature branch creation
- PR description template with MotifPath checklist
- Anti-pattern detection (WIP commits, direct commits to protected branches,
  missing task codes, vague messages, ignored dev sync PRs)
- Generated file commit guidance (codegen commits must be separate)
- Code review delegation — directs to tech-stack-specific review skills

