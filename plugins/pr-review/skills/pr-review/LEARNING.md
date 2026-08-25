# Learning loop

A log that only grows isn't learning — it's a dumping ground. This loop is closed and has a pass
criterion between stages:

```
CAPTURE GATE  ──passes──▶  CAPTURE (lesson)  ──trigger──▶  GENERALIZATION (question)  ──recurrence ≥2──▶  PROMOTION (checklist item)
                                ▲                                                                                  │
                                └──────────────────────── disuse / refuted ◀──────────────────── PRUNING ◀─────────┘
```

Run at **Phase 8** of every review (and when a dry-run surfaces a genuinely new pattern).

---

## 0. Capture gate — the step that keeps this memory small

Before writing anything to `lessons/`, the finding must clear this gate. This is stricter than a
generic checklist: MotifPath is a small team sharing one `motifpath-specs` repo, and a memory that
fills up with one-off noise stops getting read by anyone.

Write a lesson **only if all of these hold**:

1. **It would change a future review's outcome**, not just its wording. If the exact same finding,
   phrased differently, would already surface from an existing `HEURISTICS.md` item or an existing
   profile norm, it doesn't need a new lesson — at most, update that profile with the evidence.
2. **It's reachable again.** Either the same pattern already showed up in a second, distinct change
   (different PR, different scope/repo), or it's severe enough on its own (see trigger table below)
   that waiting for a second occurrence would be irresponsible.
3. **It isn't already covered.** Check `lessons/INDEX.md` and the relevant profile first — a
   near-duplicate lesson is a sign the existing one needs its trigger widened, not a sign a new file
   is needed.
4. **It survives the three-question test** in §2 below.

If a finding fails the gate, it still gets mentioned to the user in the Phase 6 summary as "noted,
not memorized" — visibility without cluttering the shared file.

## 1. Capture — when a finding clears the gate, which trigger applies

| Trigger | What it teaches | Signal |
|---|---|---|
| **review-received** — someone else caught something our checklist wouldn't have | a genuinely new heuristic; the richest source | recall |
| **finding-confirmed** — our finding was accepted and fixed | the question was worth asking; counts a hit | precision ✔ |
| **finding-rejected** — the author disagreed with good reason | false positive: narrow the trigger condition or downgrade the item | precision ✘ |
| **escaped-to-production** — a defect passed review and showed up later | blind spot: no question covered it | recall ✘✘ |
| **process** — a mistake in the method itself (pagination, dedup, anchoring, phase order) | the method itself is reviewable | efficiency |

`finding-confirmed` on its own, without anything surprising about *why* it worked, usually fails the
capture gate (item 1 above) — it confirms an existing item is doing its job; log it in
`METRICS.md`'s `confirmed` count instead of writing a new lesson file.

## 2. Generalization — the three-question test

Before saving, run the case through:

1. **Remove the stack — does the lesson survive?** If it doesn't exist without the framework/repo
   name, it's a project norm (goes to the profile), not a heuristic.
2. **Does it become a question?** If it can only be phrased as an imperative ("use X"), it isn't
   generalized yet.
3. **Is it falsifiable?** A question whose answer is always "yes, fine" rules nothing out — it
   doesn't become an item.

**Two mandatory layers:** the **case is concrete** (with the repo and stack — that's what makes it
recognizable); the **question is agnostic** (that's what travels to another repo or project). Only
the question is promoted to the checklist.

## 3. Lesson format (`lessons/L###.md`, one file per lesson)

```markdown
---
id: L###
date: YYYY-MM-DD
origin: review-received | finding-confirmed | finding-rejected | escaped-to-production | process
axis: A-system | B-data | C-change | D-input | E-method
trigger: <what kind of change should re-read this question>
heuristics: [10, 12]     # items this lesson reinforces — empty if it's a brand-new pattern
scopes: [motifpath-core, motifpath-web]
status: candidate | promoted | archived
hits: 0                  # +1 per confirmed finding this question produced
source: <PR / incident / who reviewed>
---

**Case:** what happened, concrete, with enough detail to recognize it again.

**Question that would have caught it:** … (agnostic — this is the part that travels)

**Smell:** …

**Doesn't apply when:** when this question should NOT fire / generates noise.
```

After creating it, add one line to `lessons/INDEX.md`. **The index is what gets loaded on every
review** — never the whole folder. That's what keeps context cost ~constant as memory grows.

## 4. Promotion — objective criterion

A `candidate` lesson becomes a `HEURISTICS.md` item when:

- **recurrence ≥ 2 in distinct scopes** (different repos/services — motifpath-core vs.
  motifpath-web vs. motifpath-infra vs. motifpath-specs, or core-domain vs. event-ingestion;
  repeating in the same module doesn't count); **or**
- **origin = escaped-to-production** with real impact → immediate promotion; **or**
- **the user promotes it manually.**

When promoting: write **question + smell in ≤3 lines**, mark the lesson `promoted`, and don't repeat
the case in the checklist (keep the link). Register the item in `HEURISTICS.md`'s activation table
— an item no trigger activates never runs.

**24-item cap:** at the cap, promoting requires merging two neighboring items or pruning one.

## 5. Pruning — the stage everyone skips

- An item with **0 hits across 20 reviews that activated it** → demoted to lesson `archived`.
- An item with a **rejection rate > 50%** → rewrite its trigger condition or archive it.
- A `candidate` lesson with no second occurrence in **6 months** → `archived`.

Archiving ≠ deleting: the file stays, drops out of the default load, and comes back if the pattern
reappears. A heuristic costs reviewer attention on **every** review — pruning is what keeps the
checklist sharp instead of long.

## 6. Metrics

One line in `lessons/METRICS.md` per review. They exist to decide promotion and pruning from data,
not impression:

```
YYYY-MM-DD | <PR ref> | scope: <repo/service> | published: N | confirmed: N | rejected: N | escaped: N | heuristics: [n,...]
```

`confirmed`/`rejected` start as `-` and are filled in once the author responds. `escaped` gets
filled if a defect from that change later shows up in production — the only way to measure recall.

## 7. Sharing the memory — staged, never auto-pushed

`lessons/`, `HEURISTICS.md`, and `METRICS.md` all live inside `motifpath-specs`, the repo the whole
team already treats as the shared source of truth for skills. That's the distribution mechanism —
there's no separate sync step, just the normal `motifpath-specs` pull/update flow every developer
already has.

When Phase 8 produces a new or updated lesson, a `HEURISTICS.md` promotion/pruning, or a
`METRICS.md` line:

1. Stage exactly the changed files under `plugins/pr-review/skills/pr-review/` (never the rest of
   the working tree).
2. Draft a Conventional Commit message per the `git` skill's rules — type `chore`, scope `skills`,
   e.g. `chore(skills): promote L004 — threshold precedence duplicated client/server`. Bump
   `plugins/pr-review/.claude-plugin/plugin.json`'s `version` (patch bump for a lesson add,
   minor for a promotion/pruning that changes `HEURISTICS.md`) and add the matching
   `plugins/pr-review/CHANGELOG.md` entry — the marketplace's update-check depends on this version
   moving.
3. **Stop and show the user the exact diff and the drafted commit message.** Never run `git commit`
   or `git push` without explicit confirmation — this follows the exact same approval discipline as
   Phase 6 for published review comments. If approved, the normal MotifPath git flow still applies:
   this is a `chore/<TASK-CODE>/...` branch and PR to `dev` like any other change, not a direct
   commit to a protected branch.
4. If the user declines, the lesson stays as an uncommitted local file — it doesn't help the team
   yet, but it isn't lost either. Say so plainly rather than silently dropping it.

## 8. Closing

Every review ends with **a write to disk**:

1. A line in `METRICS.md`.
2. Ask the user: **"what did this review teach us?"** — capture a lesson per applicable trigger,
   but only what clears the capture gate in §0.
3. Promotion / pruning, if a criterion was met.
4. A project norm discovered along the way → update the **profile** (with evidence), not the
   checklist.
5. If any of the above touched a file, run §7 before ending the turn.

If the review ended with no write here, either there was truly nothing to learn (rare), or the
closing step got skipped (common). A skill that only reads memory doesn't learn; it learns by
writing at the end of every use.
