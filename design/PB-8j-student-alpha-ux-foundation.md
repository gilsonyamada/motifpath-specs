# Student Alpha UX Foundation

**Task:** PB-8j
**Date:** 2026-09-01
**Author:** Gilson
**Status:** Draft
**Fidelity:** Wireframe / structural — not visual design
**Revised:** 2026-09-03 — incorporates the wireframe-canvas review (see Revision note)

---

## Revision — 2026-09-03

The first wireframe canvas review changed five things. Details are folded into the sections
below; **ADR-015** carries the decisions and their rationale.

1. **The challenge is the node's practice step, not a peer screen.** S6 owns the content
   *and* the challenge; S7 stays a route but is entered from within S6.
2. **The path groups its own steps into competency-named sections.** A path step carries an
   optional teacher-set section label; the path view groups consecutive steps that share
   one. The student path stays self-contained — **no dependency on the knowledge graph.**
3. **All time-box framing is removed.** No "Week N", no schedule, no due dates on any
   student-facing surface.
4. **S6 is a dynamic video layout.** The video fills the frame by default; when a timed cue
   is active the video shrinks and the cue's content takes the freed space — beside the
   video in landscape (the reference case), below it in portrait — then the video reclaims
   the full frame when the cue passes. The content is continuous with the video frame, not
   an overlay and not a chrome'd panel (no "Following along" label). No per-cue focus mode,
   no picture-in-picture. Playback never pauses. (Converged after several revisions.)
5. **S7 is responsive; the "single column, no multi-column" rule no longer applies to it.**
   Portrait is a single column; landscape puts the prompt and input side by side. No forced
   rotation. S7 is visually immersive but stays inside the app shell.

## Purpose

A single shared UX/IA blueprint for the student-facing alpha, so that PB-8c–8f are implemented
against one navigation model, one page skeleton, and one set of state patterns — instead of each
slice inventing its own. This document is the reference; the companion wireframe canvas shows the
same structure visually.

This is **not** a visual design system. It fixes *structure and behaviour*, not colour,
typography, or spacing beyond token roles.

## Scope

**In scope:**
- The complete student-alpha screen inventory (PB-8c–8f)
- Navigation model, the core loop, and the route map
- One page-anatomy skeleton (formalises the existing `AuthenticatedLayout`)
- Loading / empty / error / locked as named shared components + a copy voice
- Semantic token roles, so final brand hex drops in without touching components

**Out of scope:**
- High-fidelity visual comps, iconography, illustration
- The brand colour decision — `motif-blue` / `motif-ink` / `motif-cream` are still `TBD` in
  `motifpath-brand/colors.json` and `motifpath-web/tailwind.config.ts`. This doc defines the
  *roles*; the hex values are a parallel `motifpath-brand` task
- Animation and transitions
- Any teacher-facing UI — including the content-creator / practice-node authoring flow. That
  is **PB-8i** (content & classification concierge tooling), a separate slice with its own
  wireframes; it must not be folded into this canvas.
- The PB-8h admin observation view — different audience; it reuses the shell but not this
  student IA

## The student, in one paragraph

A hand-recruited participant in a closed concierge alpha. Persona B — the informal guitar student
who has tried apps or lessons before and dropped out. Not a future professional; wants to play
real songs and stay motivated. They are onboarded out-of-band (a concierge conversation captures
goals, level, and repertoire — see PB-8c), so the product's job is narrow: **show them what to do
next, let them do it, and show progress.**

---

## Information architecture — screen inventory

| # | Screen | Route | Slice | Purpose | Primary action | Key states |
|---|---|---|---|---|---|---|
| S0 | Landing | `/` (public, signed out) | PB-8c | One line of context + a way in | Sign in | — |
| S1 | Sign in | `/sign-in` | PB-8c | Google auth via Clerk `<SignIn />` | Continue with Google | loading |
| S2 | Registering | `/welcome` | PB-8c | Interstitial while `POST /users` runs | *(auto-advance)* | loading, → S3 on failure |
| S3 | Registration error | `/welcome/error` | PB-8c | Recover a failed registration | Try again | — |
| S4 | My Path — holding | `/path` (no assignment) | PB-8c → PB-8d | "We're building your personalized path" | *(none; refresh)* | empty (holding) |
| S5 | My Path | `/path` | PB-8d | The spine: steps in order grouped into sections, status, what's next | Open current step | loading, error, empty (S4) |
| S6 | Node / Lesson | `/path/nodes/:nodeId` | PB-8e | Dynamic video layout — video fills the frame, shrinks to share it with timed content while a cue is active; practice step appears when the video ends | Mark complete → *or* Go to practice | loading, error, locked |
| S7 | Practice | `/path/nodes/:nodeId/practice` | PB-8f | Run the challenge's exercises; show the result. Immersive, in-shell. Fixed regions: navigator · statement · interaction · help | Submit / interact → Finish | loading, error, in-progress, result |
| S8 | Not found | `/:pathMatch(.*)*` | PB-8b | 404 | Back to path | — |

Notes:
- **S4 is a state of S5, not a separate route.** `GET /students/me/path` returns not-found when
  there is no assignment; the path screen renders the holding variant. This is the "landed in the
  app" endpoint for PB-8c's success definition.
- **The path groups its steps into sections.** A path step carries an optional teacher-set
  section label; S5 groups consecutive steps that share one under a competency-named heading
  (ADR-015). Sections are never named for a time period. A path with no labels renders as one
  ungrouped list. This is path data only — the student path has **no dependency on the
  taxonomy / knowledge graph.**
- **The challenge is the node's practice step (ADR-015), not a peer of the lesson.** A content
  node is `video` or `article` (`StudentPathItem.content_type`) and may also have one or more
  challenges (`GET /content-nodes/{id}/challenges`). If it has a challenge, S6's primary action
  is "Go to practice" and S7 is entered from within S6, returning there on finish; if not, S6's
  primary action is "Mark complete".
- **Node completion is event-driven.** There is no "complete node" endpoint. The SPA emits
  `lesson.completed` (and `exercise.*` events for practice); the Aggregation Worker derives node
  status, and section status derives from its steps' status (ADR-011). The path screen reflects
  status on next load.

---

## Navigation model

### The core loop

```
        ┌──────────────────────────────────────────────┐
        │                                              │
        ▼                                              │
   ┌─────────┐   open current    ┌──────────────┐  has challenge?  ┌────────────┐
   │  PATH   │ ────────────────▶ │ NODE / LESSON │ ──────yes──────▶ │  PRACTICE  │
   │  (S5)   │                   │     (S6)      │                 │    (S7)    │
   └─────────┘ ◀──── back ────── └──────────────┘ ◀──── back ───── └────────────┘
        ▲             │ no challenge: mark complete       │ finish
        └─────────────┴───────────────────────────────────┘
```

One spine (Path), one detail level (Node), one optional sub-level (Practice). No deeper nesting
in the alpha. Practice is the node's own step — S7 is reached only from the node it belongs to,
never directly from the path.

### Chrome

- **Header** (all authenticated screens): logo + wordmark · one nav link "My path" · "Sign out"
  pushed right. No hamburger — the nav is one item.
- **Context bar** (S6, S7 only): a "‹ Back to path" / "‹ Back to lesson" affordance. Browser back
  must do the same thing — routes are real, not modal.
- **No global footer, no breadcrumbs, no sidebar** in the alpha.

### Route map

```
/                       → signed out: Landing (S0)  ·  signed in: redirect → /path
/sign-in                → Sign in (S1)                      [public]
/welcome                → Registering (S2)                  [auth, no requiresAuth loop]
/welcome/error          → Registration error (S3)           [auth]
/path                   → My Path (S5) / holding (S4)        [requiresAuth]
/path/nodes/:nodeId     → Node / Lesson (S6)                 [requiresAuth]
/path/nodes/:nodeId/practice → Practice (S7)                 [requiresAuth]
/:pathMatch(.*)*        → Not found (S8)
```

- Named routes only (`home`, `sign-in`, `registering`, `registration-error`, `path`, `node`,
  `practice`, `not-found`) — components never hardcode paths (per `motifpath-web/CLAUDE.md`).
- `requiresAuth` routes wait for **both** the Clerk session **and** registration to resolve
  (PB-8c extends the guard). An unregistered signed-in user is routed to `/welcome`.
- Nodes are nested under `/path` so "back to path" and browser-back agree.

---

## Page anatomy

One skeleton for every authenticated screen. Formalises `AuthenticatedLayout.vue`.

```
┌───────────────────────────────────────────────────────┐
│  [logo] MotifPath      My path                Sign out │  header — sticky, border-bottom
├───────────────────────────────────────────────────────┤
│                                                       │
│   ‹ Back to path                                      │  context bar — S6/S7 only, optional
│                                                       │
│   Page title                             [ primary ]  │  page head — h1 + at most one action
│                                                       │
│   ───────────────────────────────────────────         │
│                                                       │
│   Content column                                      │  main — single column
│   • max width ~768px, centred                         │
│   • one primary action per screen, in the page head   │
│     or at the natural end of the flow                 │
│                                                       │
└───────────────────────────────────────────────────────┘
```

Rules:
- **Single column, mobile-first — for S0–S5 and S8.** No multi-column layouts on those
  screens. Content column `max-w-3xl`/`max-w-4xl`, horizontal padding on small screens.
  **S6 is a dynamic video layout and S7 is responsive** — see below.
- **One primary action per screen.** Secondary actions are text links, visually quieter.
- **The page head owns the h1.** Screens do not render their own top-level heading inside the
  content column.
- **Loading / error / empty replace the content column**, never the header.

### S6 — lesson screen anatomy (ADR-015)

**S6 is a dynamic video layout.** By default the video fills the frame. When a timed cue is
active the video shrinks and the cue's content takes the freed space; when the cue passes
the video reclaims the full frame. The student's model is "I am watching a lesson, and
things appear next to it exactly when they're relevant."

- **Default state:** the video fills the frame at a usable size. A small or below-the-fold
  player is the top predicted cause of alpha dropout, so when nothing is cued, nothing
  competes with it.
- **Cued state:** the video shrinks; the cue's note / resource occupies the space it gave
  up — **beside the video in landscape (the reference case), below it in portrait.** The
  content is **visually continuous with the video frame** — it reads as part of the lesson,
  not an overlay (never on top of the video) and not a panel with its own chrome (no header
  label like "Following along").
- **Playback never pauses**, in either state.
- **A cue carries a timestamp and its resource.** No per-cue focus mode, no
  picture-in-picture — those were over-built earlier drafts, corrected.
- **The practice step** (if the node has a challenge) is a single affordance that appears
  when the video ends — "Go to practice", or "Mark complete" for a node with no challenge.
  It does not compete with the video while it is playing.
- The cue schema (timestamp, resource reference, render style) is **not yet specified** — a
  content-spec prerequisite for PB-8e, authored against the video timeline (see PB-8i and
  Open questions).

### S7 — practice screen anatomy

S7 keeps the header and context bar; its content region is **responsive** (portrait: a
single column; landscape: exercise prompt and answer input side by side). No forced
rotation.

- **Immersive, but in-shell.** The header stays; S7 does not break out into a chrome-less
  full-screen mode. "Immersive" is visual density and focus — high-contrast, minimal
  secondary UI, one thing to do at a time — not a structural change.
- Entered from within S6; "‹ Back to lesson" and browser-back both return to S6.
- Result is shown **inline** in S7, then "Finish" returns to S6 → S5.

**S7 has structural regions PB-8j fixes now and detail PB-8f owns.** PB-8j locks that S7
contains, in this order: a **progress / navigator bar** (e.g. "2 of 4"), a **question
statement** region, an **answer / interaction** region, and a **help affordance** (a control
that opens instructions for the current exercise in a modal or panel). PB-8f decides
everything below that: exercise-type rendering, whether the navigator lets a student move
back to an answered exercise, ordered vs. randomised exercise sequences, and whether an
exercise type takes an explicit "Submit" or treats a single interaction as the answer. S7's
region layout must stay modular so those variations drop in without a rebuild — this screen
is expected to evolve heavily.

---

## Standard states

Four named components in `src/shared/components/` (S-prefixed to group them). Every screen that
fetches data uses them — this is a rule, not a suggestion (`CLAUDE.md`: "ALWAYS handle loading
and error states").

| Component | When | Content | Action |
|---|---|---|---|
| `StateLoading` | a fetch is in flight | one line: "Loading your path…" (caller supplies the noun) | none |
| `StateEmpty` | fetch succeeded, nothing to show | heading + one explanatory line + optional action | optional, caller-supplied |
| `StateError` | fetch failed (non-404) | "We couldn't load your path." + retry | **Try again** → caller's `retry()` |
| `StateLocked` | node is `locked` | "Complete the previous step to unlock this lesson." | **Back to path** |

- The **holding state (S4)** is `StateEmpty` with fixed copy: heading "You're all set", line
  "We're building your personalized path. We'll let you know when it's ready." No action, or a
  quiet "Check again". (Impersonal "we" — some paths have no formal teacher; see ADR-015.)
- `data-test` hooks stay stable: `loading`, `no-path`, `error`, `retry`, `locked` (already used
  in `PathView.vue`).

### Copy voice

- Second person, present tense, plain. "Open your next lesson", not "Continue your learning
  journey".
- Encouraging, not gamified. No confetti, no streak-shaming, minimal exclamation marks.
- **No time-box language.** Never "week", "day", "on schedule", "behind", or a due date on
  any student-facing surface. Progress reads by competency, not by calendar.
- **Impersonal, not teacher-bound.** The product speaks as "we"; it never assumes the student
  has a named teacher (some paths do not).
- Errors name what failed and offer one recovery. Never blame the user.
- One term per concept across all screens: **path**, **section** (a named group of steps on
  the path), **step** (a path position), **lesson** (a content node the student
  reads/watches), **practice** (a node's challenge exercises).

---

## Semantic token roles

Components reference these role names via Tailwind token classes — never raw hex
(`motifpath-web/CLAUDE.md`). The hex behind each is a `motifpath-brand` decision, still `TBD`.

| Role | Current token | Used for | Status |
|---|---|---|---|
| Page surface | `motif-cream` | page background | placeholder hex |
| Body ink | `motif-ink` (+ `/70`, `/60` opacity ramp) | text, borders | placeholder hex |
| Primary action | `motif-blue`, `motif-blue-fg` | buttons, links, active nav, current step | placeholder hex |
| Locked / disabled | `motif-ink/40` | locked path items, disabled controls | opacity of ink — OK |
| Success / complete | *none yet* | completed step marker on the path | **add `motif-success`** |
| Danger | *none yet* | hard failure emphasis, destructive confirm | **add `motif-danger`** |

Action items this raises (small, not blocking wireframes):
1. `motifpath-brand`: resolve `motif-blue` / `motif-ink` / `motif-cream` hex (already-pending
   brand work).
2. `motifpath-web`: add `motif-success` and `motif-danger` tokens to `tailwind.config.ts`.

---

## Wireframes

The companion canvas holds one artboard per screen (S0–S8) plus a core-loop / route-map
overview, at this fidelity — labelled boxes, real copy, no colour commitment.

**Canvas:** <https://claude.ai/code/artifact/761c7260-e79b-4a1c-af34-89accfedd7f6>
(working files in `design/PB-8j-wireframes/`)

Rough reference for the three screens that anchor the loop:

**S5 — My Path** (sections from step labels; no time-box framing)

```
  My path
  ────────────────────────────────────
  Fretting-hand fundamentals                  3 steps

  ✓   Tuning and posture                completed
  ▸   Your first chord: E minor         in progress   [ Open ]
  🔒  Switching between chords           locked

  Your first songs                            2 steps
  🔒  Two-chord song: "…"               locked
```

**S6 — Node / Lesson** (dynamic video layout — landscape is the reference case)

```
  0:00  no cue active — video fills the frame
  ┌──────────────────────────────────────────────┐
  │                    ▶                          │
  │  ▓▓░░░░░░░░│░░░░░░│░░░░░░░░░░  ← cue marks      │
  └──────────────────────────────────────────────┘

  1:12  cue active — video shrinks, content takes the freed space (beside it
        in landscape, below in portrait); one continuous frame, no label
  ┌───────────────────────────┬──────────────────┐
  │            ▶              │  Thumb behind    │
  │  ▓▓▓▓▓▓░░│░░░░│░░░░░░       │  the neck …      │
  │                           │  [ Em diagram ]  │
  └───────────────────────────┴──────────────────┘
        …cue passes → video reclaims the full frame

  When the video ends…                     [ Go to practice ]
                                    (no challenge → [ Mark complete ])
```

**S7 — Practice** (immersive, in-shell; result inline). PB-8j fixes the regions; PB-8f fills them.

```
  ‹ Back to lesson

  Practice — E minor          ● ● ○ ○   2 of 4        [ ? Help ]
  ────────────────────────────────────
  Question statement
  "Which fret is the low E?"                          ← statement region

  [ answer / interaction region ]                     ← per-type: click-as-answer
  portrait: statement then interaction, stacked          or explicit submit (PB-8f)
  landscape: statement | interaction, side by side

  [ Submit ]  (only for exercise types that need it)
  ── on finish ──
  Result: 3 of 4 correct                       [ Finish ]
```

Regions PB-8j locks: navigator/progress bar · question statement · answer / interaction ·
help affordance. PB-8f owns: exercise-type rendering, move-back-between-exercises, ordered
vs. randomised sequence, submit vs. click-as-answer.

---

## Open questions

### Resolved by the 2026-09-03 review

| Question | Resolution |
|---|---|
| Node routes nested under `/path` vs flat `/nodes/:id`? | Nested — keeps "back to path" and browser-back consistent |
| Is `/path` the authenticated home, or is there a separate dashboard? | `/path` is home; redirect `/` → `/path` when signed in. No separate dashboard in the alpha |
| Practice result — inline in S7 or a distinct screen? | Inline in S7 |
| Account / profile screen for the alpha? | No — "Sign out" in the header is enough; defer |
| Does the holding state (S4) poll, or is it refresh-only? | Refresh-only; a "Check again" link, no polling |
| Is the challenge a peer screen or part of the node? | Part of the node (ADR-015) — S7 entered from S6 only |
| How is the path grouped? | Teacher-set section label per step; no knowledge-graph dependency (ADR-015) |
| Can S6/S7 use multi-column / landscape? | S6 splits video / timed-content while a cue is active (side by side in landscape, stacked in portrait); S7 is responsive, two-region in landscape; no forced rotation (ADR-015) |
| Is S6 a video-plus-panels page, an overlay, or something else? | A dynamic layout — video fills the frame, shrinks to share it with timed content only while a cue is active; content is continuous with the frame, never over the video (ADR-015) |

### Still open

| Question | Owner | Note |
|---|---|---|
| Does a node with a challenge require *passing* it to count as complete, or is finishing the lesson enough for the alpha? | Gilson | Defer to PB-8f + the rules engine; affects the S6→S7→S5 status flow |
| Timed-resource cue schema — timestamp, resource reference, render style | Gilson + content spec | **Blocks PB-8e.** Needs a `content-management` spec before S6 can be built. Authored as part of the video (see PB-8i) |
| Where in the concierge flow does the teacher set section labels, and what guidance keeps them consistent? | Gilson | Authoring-side; feeds the `learning-paths` spec revision (ADR-015 follow-up) |
| Landscape breakpoint and behaviour for S7 (two-region) and the S6 player | Gilson | Needs the hi-fi canvas + a real device/orientation test pass |
| S7: does the navigator let a student move back to an answered exercise? | Gilson | PB-8f + assessment model — affects whether answers are revisable |
| S7: ordered vs. randomised exercise sequence (some exercises have no natural order) | Gilson | PB-8f + `content-management` / challenge model |
| S7: which exercise types take an explicit "Submit" vs. treat one interaction as the answer? | Gilson | PB-8f + exercise-type model; affects `exercise.answer_sent` semantics |
| S7: help content — where authored, per exercise or per challenge? | Gilson | PB-8f + content model |

---

## Related

- **Backlog item:** PB-8j — Student alpha UX foundation (Notion `3ce9ccc1-102f-8150-ad87-dfac43a21a28`)
- **Consumers:** `plans/PB-8c-student-onboarding-auth.md`; PB-8d–8f (plans TBD)
- **Builds on:** `plans/PB-8b-web-app-foundation.md` (app shell, `AuthenticatedLayout`, state pattern)
- **Not this doc:** PB-8i — content & classification concierge tooling (the content-creator flow)
- **Contracts:** `openapi/core-domain-service.yaml` (`GET /students/me/path`, `GET /content-nodes/*`,
  `GET /challenges/*`, `GET /exercises/*`), `openapi/event-ingestion-service.yaml` (`POST /events`)
- **Behaviour specs:** `features/learning-paths/student-path-view.feature`,
  `features/content-management/{content-nodes,challenges,exercises}.feature`
- **ADRs:** ADR-007 (auth), ADR-011 (node-completion state derived by the Aggregation Worker),
  **ADR-015** (challenge belongs to the node; path is a self-contained sectioned sequence; S6/S7
  responsive — carries the 2026-09-03 review decisions)
- **Brand:** `motifpath-brand/BRAND.md`, `motifpath-brand/colors.json` (colour tokens — `TBD`)
