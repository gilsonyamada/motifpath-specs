# Guideline capture

Not every review has something worth remembering, and of what's worth remembering, most of it
isn't worth *tracking*. This skill has one filter and one output: if an observation survives the
filter, it's written directly into `HEURISTICS.md` or a profile — nothing is staged as a
"candidate," counted, or promoted through a pipeline first. A specific fix to a specific PR is
not memory; it's just the PR. Only a guideline — something that would change how a *future*,
unrelated review goes — earns a place here.

Run this at Phase 8 of every review (and when a dry-run surfaces a pattern worth keeping).

---

## 1. The filter — guideline, or just this once?

Before writing anything, put the observation through all three questions. All three must pass:

1. **Remove the stack — does it survive?** If the rule doesn't exist without this repo's
   framework/language, it's a **profile norm** (goes to `profiles/<repo>.md`, with evidence), not
   a checklist item. If it doesn't survive at all — it only made sense for this one PR — it isn't
   written anywhere.
2. **Does it become a question?** "Use X" is an instruction, not a guideline. "Does the reused
   routine's ordering still make sense at this caller's scale?" is. If you can't phrase it as a
   question someone would ask on the *next* unrelated PR, it isn't generalized yet.
3. **Is it falsifiable?** A question that always resolves to "yes, fine" doesn't rule anything
   out — it's not worth a reviewer's attention on every future review.

This is a **conceptual** test, not a statistical one — it doesn't matter whether the pattern has
been seen once or ten times. Frequency isn't the signal; generality is. That's also why severity
alone (an `escaped-to-production` defect, or a reviewer catching something the checklist plainly
should have) is enough on its own to write something down immediately, with no waiting period.

## 2. Where it goes

- **Repo-agnostic → `HEURISTICS.md`.** Add it under the right axis, phrased as a question, with a
  one-line "smell." A short illustrative case is fine as a parenthetical, but it's there to make
  the question recognizable — it isn't tracked as its own artifact. Respect the **24-item cap**:
  at the cap, adding a new item requires merging two neighboring items or cutting the weakest one
  first. That's a judgment call made at write time by re-reading the checklist, not a decision
  driven by usage counts.
- **Repo-specific → the profile.** Add a row to `profiles/<repo>.md`'s "Local norms" table, with
  evidence (`file:line`, or a command that proves it). No norm enters a profile without evidence —
  that's what keeps a profile a record of the repo, not the reviewer's taste.

## 3. What NOT to write

- A fix that's already fully described by the PR itself and doesn't generalize beyond it.
- Anything an existing checklist item or profile norm already covers — if the existing wording is
  too narrow to have caught this case, **widen it in place**; don't add a near-duplicate next to
  it.
- An impression ("this feels like it could be a problem sometimes") with no concrete case behind
  it. If you can't point to the PR that prompted the question, it isn't ready to write down.
- A false positive on its own (the author rejected a finding with good reason) doesn't need a new
  entry — it means an *existing* item's trigger condition is too broad. Narrow that item's wording
  or downgrade it to a suggestion; don't add a second item next to it.

## 4. Sharing — staged, never auto-pushed

`HEURISTICS.md` and every `profiles/*.md` file live inside `motifpath-specs`, the repo the whole
team already treats as the shared source of truth for skills. That's the distribution mechanism —
no separate sync step, just the normal `motifpath-specs` pull/update flow every developer already
has.

When Phase 8 changes `HEURISTICS.md` or a profile:

1. Stage exactly the changed file(s) under `plugins/pr-review/skills/pr-review/` (never the rest
   of the working tree).
2. Draft a Conventional Commit message per the `git` skill's rules — type `chore`, scope `skills`,
   e.g. `chore(skills): widen threshold-precedence guideline to cover cache/origin duplication`.
   Bump `plugins/pr-review/.claude-plugin/plugin.json`'s `version` (minor, since this changes
   reviewer behavior) and add the matching `plugins/pr-review/CHANGELOG.md` entry — the
   marketplace's update-check depends on the version moving.
3. **Stop and show the user the exact diff and the drafted commit message.** Never run
   `git commit` or `git push` without explicit confirmation — this follows the same approval
   discipline as Phase 6 for published review comments. If approved, the normal MotifPath git flow
   still applies: a `chore/<TASK-CODE>/...` branch and PR, not a direct commit to a protected
   branch.
4. If the user declines, the change stays uncommitted locally — it doesn't help the team yet, but
   it isn't lost either. Say so plainly rather than silently dropping it.

## 5. Closing

Every review ends with:

1. Ask the user: **"did this review surface a guideline worth keeping?"**
2. Run the observation through the filter in §1. Most reviews produce nothing that passes it —
   that's the expected outcome, not a gap. Don't manufacture something to write down.
3. If it passes: write it directly into `HEURISTICS.md` or the relevant profile (§2), then run the
   sharing step (§4).
4. A project norm discovered along the way that *doesn't* pass the filter as a general guideline
   (e.g. something purely descriptive, not yet evidenced twice) still belongs in the profile if it
   has evidence — profiles record norms, not just guidelines, and don't need the same bar.
