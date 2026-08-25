# Finding format

A finding is an **actionable fact**, not an impression. A wrong finding costs more than a missing
one: it burns trust in every other finding in the same review.

## Anatomy (four parts)

1. **Concrete failure scenario** — input → effect. "When the `event-ingestion` consumer receives an
   `exercise.answer_sent` event without `session_id`, the write to Mongo silently drops the record
   and the teacher dashboard shows a gap" beats "this might cause a problem."
2. **Exact location** — file + line present in the diff.
3. **Proposed fix** — ideally as an applicable diff.
4. **Condition** — "if X already guarantees this, it's harmless; if not, it needs handling." Make
   explicit what you couldn't verify.

## Writing the comment

A well-built finding is still useless if it arrives unreadable. The reader is the PR author, in the
middle of their day.

1. **Always inline.** Every finding anchors to `file:line`. **Empty review body** — no summary
   there. The summary exists for the user at the Phase 6 gate, not for whoever receives the review.
   The one exception that goes in the body: a finding that anchors to no line in the diff at all —
   and it goes alone, in one sentence.
2. **One finding per comment**, one question per comment.
3. **Open with the effect**, in business language: what the student, teacher, or system feels if
   this is wrong. **Only then** the technical detail or suggestion — and the technical lead-in is
   **one sentence**, not a paragraph.
4. **Simple and short.** If the comment needs a second read to land, rewrite it.

**Never in the comment:**
- the command you ran to reach the conclusion, or its output (coverage numbers, test logs, snapshot
  diffs);
- narration of your own process ("only caught this reading carefully," "ran X and saw Y");
- the full reasoning chain — the author needs the conclusion and the why, not the path;
- more than one code snippet;
- two implementation details in the same comment (that's two comments, or the second one wasn't
  necessary).

**Bloated** — mixes command, output, personal difficulty, and two implementation details:

> ❌ "This threshold override check has no coverage — the report shows 0% on the lookup function. It
> has two details I only understood reading carefully: the precedence check only fires when an
> override actually exists for the pair, and the fallback to the node default only runs on the
> first branch because of how the early return is structured. Since the function is pure and
> returns the resolved value, we could test it directly. Does that make sense to you?"

**Same finding, written to be read:**

> ✅ "This threshold precedence check has no test — if it regresses, a teacher's override could
> silently stop applying and a student gets the wrong node default. The function is pure, so
> testing it directly with an override present vs. absent should cover it. What do you think?"

The difference isn't length: it's **order** (effect before mechanism) and **cut** (what supported
your conclusion doesn't need to travel with it).

## Tone

**Questioning and humble, always inviting confirmation.** Not decorative politeness — it's honest
confidence calibration: the analysis can be wrong, and the cost of a false positive drops when it
arrives as a question.

- ❌ "This code is wrong because it will cause X."
- ✅ "Could this cause X?"
- ✅ "I wasn't sure this case is covered when Y happens — can you confirm?"
- ✅ "What do you think about Z here? Feels more aligned with the module's pattern, but I could be
  off."

Language: English, per MotifPath convention. Short and concrete — describe the problem, don't write
an essay.

## Severity

| Level | Criterion |
|---|---|
| **Blocking** | causes a failure, data loss, a security gap, or a broken contract |
| **Important** | a real problem that should be fixed, but doesn't block merging |
| **Suggestion** | improvement or style alignment; explicitly optional |

Separate blocking from non-blocking in the presentation. **Product decision → escalate to product**,
never guess the intended behavior.

## Two practices that turn an opinion into a fact

- **Reproduce before asserting.** When the claim depends on runtime behavior, build the real case. A
  reproduced finding doesn't open a debate — but **the evidence doesn't go in the comment**: it
  backs your certainty and is presented to the user at the gate. The comment gets only the observed
  effect, in one sentence.
- **Offer the dual path.** When the change **might** be intentional: "if intentional, confirm and
  record it as a behavior change with operator guidance; if not, the fix is X." Respects authorship
  and forces an explicit decision instead of letting ambiguity pass.

## What NOT to comment on

- What an automatic project gate already catches (the profile lists which ones) — spends the
  author's attention on noise.
- A pattern you didn't confirm in the repo: without evidence, it's your preference, not a project
  norm.
- Something the existing discussion already raised or resolved (item 19) — if it deserves
  reinforcement, it goes as a thread reply.
- Tolerated legacy that the profile marks as a boundary: not this change's finding.
- A refactor of adjacent code the change didn't touch.

## Presentation (Phase 6)

Group by scope; within scope, blocking first. For each: `file:line` + the **exact text** to be
published. Close with: criterion-by-criterion adherence, cross-repo coherence findings, scopes
reviewed in generic mode, findings dropped by dedup (with the reason), and reproduction evidence.

All of this is a conversation **with the user** and stays here — none of it goes into the published
review body.

Before presenting, re-read every comment against the "Writing the comment" bar and cut what's left
over. It's cheaper to cut now than after publishing.
