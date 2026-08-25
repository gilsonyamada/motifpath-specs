# Scope → profile routing

Consulted in Phase 0. **Adding a new repo/service = one line here + a new profile.** The core never
changes.

## Single-repo scopes

| Repository | Profile |
|---|---|
| `motifpath/motifpath-web` | `motifpath-web.md` |
| `motifpath/motifpath-infra` | `motifpath-infra.md` |
| `motifpath/motifpath-specs` | `motifpath-specs.md` |

## Monorepo: motifpath-core

Scope = first directory under `services/`. Both services share one profile today (the Go standards
in `motifpath-core/CLAUDE.md` apply repo-wide) — but Phase 4a item 4 (second-order effect / monorepo
boundary) always runs when a change touches both.

| Repository | Path scope | Profile |
|---|---|---|
| `motifpath/motifpath-core` | `services/core-domain/` | `motifpath-core.md` |
| `motifpath/motifpath-core` | `services/event-ingestion/` | `motifpath-core.md` |
| `motifpath/motifpath-core` | `shared/`, root (Makefile, devbox.json, .golangci.yml) | `motifpath-core.md` |

## Rules

1. **Scope name ≠ profile name is fine** — keep the column explicit instead of deriving it by
   convention; silent derivation fails quietly.
2. **A change spanning several scopes:** all of them enter the analysis. Ordering by file count only
   affects presentation, never depth.
3. **Scope with no profile → generic mode:** systemic heuristics still apply to any code. Generic
   mode isn't a reason to skip analysis; it's a reason not to assert a project norm you don't know.
   Tell the user and offer to bootstrap a profile.
4. **A repo not yet in this table:** stop and ask — don't pick a "similar-looking" profile.
5. **Cross-repo change (e.g. `motifpath-specs` + `motifpath-core` in the same review session):**
   route each repo independently, then run Phase 4d once across all of them.
