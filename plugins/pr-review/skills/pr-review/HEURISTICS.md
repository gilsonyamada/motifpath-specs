# Systemic checklist

Questions, not rules: a question crosses languages and repos; a rule dies with the framework. Each
item carries the **question** that triggers a finding + the **smell** that signals a problem.

**Mindset:** step out of the changed line and hold the change against three axes the diff itself
doesn't show — **the system** (who calls in, where the output lands), **real data** (volume,
cardinality, how hostile the content actually is), and **the lifecycle** (rollout, migration,
reprocessing — not just steady-state).

## Activation

21 items is too many for every review. Classify the change and walk only the activated subset —
plus the four always-on items.

| If the change… | activates |
|---|---|
| alters behavior that already exists | 10, 11, 12, 13, 4 |
| creates a new entry point or a new output | 1, 15, 7, 14 |
| touches ordering, filtering, scoring, or aggregation | 10, 5, 6 |
| touches an identifier, key, name, or path | 8, 9 |
| reuses an existing routine in a new context | 3, 5, 6 |
| adds validation or a constraint | 11, 12, 13 |
| carries external content into render/query/exec | 15, 16, 2 |
| touches configuration, migration, or rollout | 7, 14, 2 |
| is user-facing (motifpath-web) | 12, 18, 14 |
| **always** | **17, 19, 20, 21** |

---

## Axis A — The system around it

1. **Call chain (source → destination).** Who builds the input, and where does the output get
   written/rendered/persisted? — *Smell:* a function reviewed in isolation, without opening its
   caller or where the output lands.
2. **Symmetry and precedent.** One path gained a guard/optimization — did its sibling paths get it
   too (e.g. `core-domain`'s read path vs. its write path; `event-ingestion`'s Kafka consumer vs.
   its HTTP producer)? Does the project already have a solution for this? — *Smell:* a guard
   present in one direction of a pair and absent in the other; a twin module already solved this
   and it was ignored here.
3. **Reuse fit.** Does the reused routine return what I need, or does it carry weight (fields,
   ordering, no limit) my caller doesn't use — and does it change the scale it was built for? —
   *Smell:* reusing something built for dozens of items on a path that sees thousands.
4. **Second-order effect / invariant.** Does the change alter a guarantee other code assumes? —
   *Smell:* "just optimized," "just swapped a parameter," with no map of who depends on it. In
   `motifpath-core` this is explicitly the monorepo boundary: does a change quietly make
   `core-domain` and `event-ingestion` depend on each other?

## Axis B — Real data

5. **Distribution, not example.** What's the real volume and shape of the data in production
   (generic values repeated in nearly every row, the largest collection, the max allowed limit)? —
   *Smell:* reasoning anchored to the spec's clean example payload.
6. **Amplification and cost.** 1 event/request → how many operations? Multiply by fan-out **and**
   by the trigger's frequency (e.g. one `exercise.answer_sent` event fanning out to a threshold
   check per node). — *Smell:* a serial loop calling something with N round trips, no limit.
7. **Absence and transitional state.** What if the input is empty/null/duplicated? And **during**
   rollout (field not yet migrated, event not yet reprocessed, an old client version still in
   flight)? — *Smell:* only the happy path covered; no "doesn't exist yet" case.
8. **Normalization destroys uniqueness and information.** Shortened/normalized/hashed an
   identifier: what guaranteed uniqueness before, and what guarantees it now? Does the destination
   accept a duplicate **silently**? What does whoever operates it lose for debugging? — *Smell:*
   truncation/hash with no dedup at the destination.
9. **Sentinel value inside the deterministic space.** Does the "unknown" fallback share the same
   key space as real values? — *Smell:* a sentinel producing a stable key that never invalidates.

## Axis C — The nature of the change

10. **Additive or mutating?** Does it add a new capability, or **change existing behavior** (order,
    filter, scoring, format — e.g. the threshold-override precedence rule)? Mutating requires a
    test that **locks** the behavior, not just a test of the new case. — *Smell:* a criterion
    change with no before/after comparison test.
11. **New constraint on an existing door.** Are all callers of that entry point already editing the
    field that just became validated? Payloads that resend the whole state carry fields the caller
    never touched — validating X starts rejecting a legitimate edit to Y, and legacy invalid data
    blocks unrelated flows. Validating **only when the field changed** usually fixes it. — *Smell:*
    validation added without enumerating callers and payload shapes.
12. **Every entry door for the data, with a reason.** Does the new rule apply at **every** point
    where the data is edited, and is the new error contract shown at **every** caller? A block with
    no explanation is a dead end: prefer validating in the action with an actionable message over
    silently disabling a control. — *Smell:* protection at 2 of N points; a helper created with
    half the rule while the other half stays duplicated elsewhere.
13. **Same rule, two sides.** A rule computed in two layers (client and server, cache and origin —
    e.g. threshold logic duplicated in `motifpath-web` and `motifpath-core`) diverges in some
    scenario: a config read failure, a different default, a limit applied on one side only? —
    *Smell:* two defaults for the same rule, in different files.
14. **Surface beyond the code.** Do docs, runbooks, migrations, config, and operator communication
    belong to this change? — *Smell:* new behavior with no trace outside the code.

## Axis D — Untrusted input

15. **Trail from input to a sensitive destination.** Does third-party-editable content
    (student/teacher-entered text, exercise answers) reach a destination that interprets it raw
    (render, query, exec, template, file path, header)? Where exactly is it neutralized? Who writes
    that input, and at what scale? Once you find one vector, **generalize to the other producers of
    the same destination.** — *Smell:* interpolating external content with no explicit
    neutralization step on the path.
16. **Tool semantics before copying the fix.** Does the fix that works here apply globally to a
    block/scope and break a legitimate neighboring case? — *Smell:* copying a fix without reading
    what the option actually does.

## Axis E — Reviewer method

17. **Verify, don't presume.** Did you claim "this is sanitized," "this path populates the field,"
    "the API guarantees order"? Open the code and confirm. — *Smell:* a conclusion about unread
    code.
18. **Test the real path.** When the claim depends on runtime behavior, exercise it through the path
    a real caller/user takes — test shortcuts that inject state internally bypass the actual
    mechanism. — *Smell:* a suite that only manipulates internal state and never fires the real
    event (e.g. never actually emits `lesson.completed`).
19. **Existing discussion is context.** List **all** discussion (bot, human, prior rounds, resolved
    and open), actually paginated, and dedupe before drafting. The criterion is "thread without a
    reply," never "recent comment." — *Smell:* a draft proposing something a thread on this same PR
    already resolved.
20. **Concurrent, mutually exclusive changes.** Is another PR under review touching the same design
    decision in the opposite direction? Merging one forces undoing the other — decide the direction
    **first** and look for a synthesis that satisfies both. — *Smell:* "known conflict, we'll sort
    it out later."
21. **Does the description describe the current state?** After a mid-review pivot, does the text
    still describe the earlier version? Is an instruction for reviewers in the description, where
    it's looked for, or lost in a thread? — *Smell:* description contradicting the diff.

---

## Budget

**Cap: 24 items.** Promoting at the cap requires merging two neighboring items or pruning one
(`LEARNING.md` §4–5). The restriction is intentional: a 40-item checklist doesn't get reviewed, it
gets skimmed. Order items within each axis by historical hit rate (`lessons/METRICS.md`).

A new item here **only** enters through lesson promotion. Never write a rule directly into this
file — the lesson is what holds the case, the evidence, and the contraindication.
