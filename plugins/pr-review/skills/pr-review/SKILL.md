---
name: pr-review
version: 1.0.0
description: >
  Review a proposed pull request against MotifPath conventions and the intent behind the change,
  across any of the four MotifPath repos (motifpath-core, motifpath-web, motifpath-infra,
  motifpath-specs). Detects which repo/scope the PR touches, applies a project-agnostic systemic
  checklist, layers in per-repo norms from profiles/, deduplicates against existing PR discussion,
  and proposes findings anchored to exact lines — publishing only after explicit approval. When a
  review surfaces a genuinely new, reusable lesson, stages it into the shared lessons/ memory in
  motifpath-specs and drafts a commit — but never commits or pushes without confirmation. Trigger
  on "review this PR", "review PR #N", "what do you think of this diff", "/pr-review", or before
  merging any feat/fix/hotfix branch.
argument-hint: "<PR reference> [intent reference: ticket/spec/ADR] [--dry-run]"
---

# PR Review — review the system, not the diff

A weak review asks "is this code correct?" A strong review asks **"what does this change do to the
rest of the system, to real data, and during deploy?"** The difference isn't effort — it's the
**question**.

This core knows nothing about Go, Vue, Terraform, or Gherkin. Everything repo-specific enters
through three extension points: **`profiles/<repo>.md`** (local norms, discovered with evidence),
**`profiles/ROUTING.md`** (which scope uses which profile), and **`PLATFORM.md`** (how to talk to
GitHub). If you had to edit this file to satisfy one repo, something repo-specific leaked into the
wrong place.

Follow the phases IN ORDER. Do NOT skip phases.

---

## Phase 0: Detect scope

Don't ask "which profile" — discover it from the files the PR actually touches.

1. Get the changed-file list (`PLATFORM.md` → `list_files`).
2. Identify the repo (`motifpath-core`, `motifpath-web`, `motifpath-infra`, or `motifpath-specs`).
3. Resolve repo → profile via `profiles/ROUTING.md`.
4. **`motifpath-core` is a monorepo**: sub-scope by first directory under `services/`
   (`core-domain`, `event-ingestion`) or `shared/`. Both services share one profile today
   (`motifpath-core.md`) — Go conventions apply repo-wide — but a change that imports across the
   `services/core-domain` ↔ `services/event-ingestion` boundary is itself a Phase 4a finding (see
   Axis A, item 4, and the profile's Monorepo Boundaries section).
5. Special cases:
   - **No profile resolves** (a brand-new repo, or a path outside all known scopes) → **generic
     mode**: review with `HEURISTICS.md` only, don't assert a project norm you haven't confirmed,
     and flag this in Phase 6. Offer to bootstrap a profile from `profiles/_TEMPLATE.md`.
   - **No scope resolves at all** → stop and ask the user.
   - Generated files count toward scope detection but never generate a finding by themselves — the
     generated-file exclusions live in each profile's Boundaries section (e.g.
     `internal/adapters/http/generated/`, `src/api/generated/`).
6. Report in 1 line: `Scope: motifpath-core/core-domain (14 files) · profile: motifpath-core.md`.

## Phase 1: Collect inputs

Minimum inputs: **PR reference** + **declared intent** (ticket, spec file, ADR, or a plain
description of what problem this solves). Missing either → **stop and ask**. Never guess intent
from the diff alone — MotifPath is spec-first, so the intent almost always already exists in
`motifpath-specs` (an OpenAPI path, a `.feature` file, or an ADR) even when the PR description
doesn't link it.

## Phase 2: Build the activity context

1. Read the intent from the sources the profile declares (usually `motifpath-specs/openapi/`,
   `motifpath-specs/features/`, or `motifpath-specs/adr/`).
2. Read the PR's own description and cross-check it against the diff (see item 21).
3. **No known intent → no adherence review.** Ask the user what the change should resolve and
   proceed with technical analysis only, stating that limitation up front.

## Phase 3: Load context and read the change

1. Read `HEURISTICS.md` and activate items per its trigger table.
2. Read `lessons/INDEX.md` and open **only** the lessons whose trigger matches this change.
3. Read the resolved profile (norms + boundaries + automatic gates already covered by CI).
4. Read the PR metadata and the full diff.
5. For each touched file, read the whole file (or its surroundings) **in its own context** to infer
   the local pattern. Never judge an isolated line; never judge one scope by another scope's norms.
6. Map anchorable hunks (file + line present in the diff).
7. **List ALL existing discussion**, actually paginated: line comments, general comments, prior
   reviews, bot and human, resolved and open. The criterion is "thread without a reply," never
   "recent comment."

## Phase 4: Analysis

### 4a. Systemic heuristics
Apply the activated items from `HEURISTICS.md` over the whole diff, ignoring scope boundaries — the
highest-value finding usually lives at the crossing between core-domain and event-ingestion, or
between an OpenAPI change and its two consumers (motifpath-core, motifpath-web).

### 4b. Intent adherence
Walk each criterion/requirement **one at a time**: implemented? Where? Partial? Flag uncovered
criteria and unscoped extras (a change with no trace in the declared intent) — extra scope is
flagged, not condemned.

### 4c. Local norms, per scope
Run the resolved profile's checklist. Every finding cites the profile and the norm that produced
it. A norm without evidence in the repo doesn't generate a finding — it's the reviewer's
preference, not a project norm. Don't comment on what an automatic project gate already catches
(golangci-lint, `tsc --strict`, `terraform plan`, Redocly/ajv/Gherkin CI — see each profile's
Boundaries section).

### 4d. Cross-repo coherence (only when a change spans 2+ repos)
MotifPath's four repos are separate git repos, not a single monorepo — cross-repo coherence is
common (a spec change in `motifpath-specs` ships alongside a `motifpath-core` handler and a
`motifpath-web` composable) and the reviewer may need to look at sibling PRs, not just this diff:

- **Contract:** did the OpenAPI/event-schema producer (`motifpath-specs`) and its consumers
  (`motifpath-core`, `motifpath-web`) move in the same direction (field name, type, nullability)?
- **Deploy order:** do they ship together? If not, does each intermediate state still work —
  particularly `make generate` / `npm run generate:api` re-run against the *old* spec vs. the new
  one?
- **Duplicated rule:** the same business rule computed in two places (e.g. threshold precedence
  logic) — does it diverge in some scenario?
- **Half the work:** a spec changed with no consuming repo updated, or a consuming repo changed
  ahead of the spec that's supposed to define it (violates Spec-Driven Development)?
- **Public contract:** is this breaking for a consumer not in this PR?

## Phase 5: Deduplicate and draft

1. Discard anything the existing discussion already raised or resolved; if still open and worth
   reinforcing, **reply on the thread**, don't open a new comment. Threads also reveal decisions
   already made that invalidate a finding.
2. Draft each finding per `FINDING.md`'s format (failure scenario + location + fix + condition), in
   English, with explicit severity and blocking separated from non-blocking.
3. Non-negotiable writing rules (detail in `FINDING.md`): **always inline**, one finding per
   comment, **empty review body** (the summary is for the user, not the PR), **open with the
   business effect**, technical detail after in one sentence. Never in the comment: commands, tool
   output, narration of your own process, full reasoning chain, a second code snippet.
4. Re-read every comment against that bar and cut what's left over before presenting.

## Phase 6: Approval gate (mandatory)

Present the user **all** comments (location + exact text, grouped by scope), the criterion-by-
criterion adherence summary, the 4d cross-repo findings, any reproduction evidence, and the
warnings (generic-mode scopes, findings dropped by dedup). This material stays **in chat** — none
of it goes into the review body. Wait for **explicit, formal confirmation**. **Never publish without
it** — present and end the turn.

## Phase 7: Publish

One single review with all findings from all scopes, **all inline, empty body**
(`PLATFORM.md` → `publish_single_review`). A line GitHub rejects → re-anchor to the nearest valid
hunk and say so. Reinforcing an already-discussed point → reply on the thread. Report the review
URL at the end.

## Phase 8: Close the learning loop (mandatory)

Run `LEARNING.md`: log the metrics line, ask **"what did this review teach us?"**, apply the
**capture gate** before writing anything, and promote or prune. A review that ends without a
memory write didn't learn — it just repeated itself. If the capture gate produced a new or updated
lesson file, `LEARNING.md` also covers staging it for the team (`motifpath-specs/skills/pr-review`
is the shared source of truth) and drafting — never sending — the commit.

---

## Dry-run mode (`--dry-run`)

The same discipline applied to a **proposal**, before code exists — pairs naturally with
`plan-writer` output, or with a spec PR in `motifpath-specs` still under review. Run Phases 0–2
(scope from the proposal), 4a–4d over each planned change as a hypothetical hunk, and deliver a
severity-tagged report. No Phases 5–7 (nothing to publish). "Verify, don't presume" (item 17)
matters double here: the proposal has no running code yet to prove anything.

## Invariants

- Never publish anything without explicit approval. Never apply a fix — the skill returns findings.
- One change = one published review, even if it spans multiple repos.
- Norms come from the repository, not the reviewer's taste.
- A finding is an actionable fact, not an impression. A wrong finding costs more than a missing one.
- Inline comment, empty body, business effect before mechanism. What supported the conclusion
  doesn't travel with it.
- Never load `lessons/` in full — only the index and the lessons it activates.
- Never commit or push to `motifpath-specs` without the user's explicit go-ahead — memory writes
  follow the same approval discipline as published review comments.
