# Student Alpha UX Foundation

**Task:** PB-8j
**Date:** 2026-09-01
**Author:** Gilson
**Status:** Draft
**Fidelity:** Wireframe / structural — not visual design

---

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
- Any teacher-facing UI
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
| S4 | My Path — holding | `/path` (no assignment) | PB-8c → PB-8d | "Your teacher is building your path" | *(none; refresh)* | empty (holding) |
| S5 | My Path | `/path` | PB-8d | The spine: nodes in order, status, what's next | Open current node | loading, error, empty (S4) |
| S6 | Node / Lesson | `/path/nodes/:nodeId` | PB-8e | Consume the video or article + inline media | Mark complete → *or* Go to practice | loading, error, locked |
| S7 | Practice | `/path/nodes/:nodeId/practice` | PB-8f | Run the challenge's exercises; show the result | Submit answer → Finish | loading, error, in-progress, result |
| S8 | Not found | `/:pathMatch(.*)*` | PB-8b | 404 | Back to path | — |

Notes:
- **S4 is a state of S5, not a separate route.** `GET /students/me/path` returns not-found when
  there is no assignment; the path screen renders the holding variant. This is the "landed in the
  app" endpoint for PB-8c's success definition.
- **S6 → S7 is conditional.** A content node is `video` or `article`
  (`StudentPathItem.content_type`). A node may also have one or more challenges
  (`GET /content-nodes/{id}/challenges`). If it has a challenge, the node's primary action leads
  to Practice; if not, the primary action is Mark complete.
- **Node completion is event-driven.** There is no "complete node" endpoint. The SPA emits
  `lesson.completed` (and `exercise.*` events for practice); the Aggregation Worker derives node
  status (ADR-011). The path screen reflects status on next load.

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
in the alpha.

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
- **Single column, mobile-first.** No multi-column layouts in the alpha. Content column
  `max-w-3xl`/`max-w-4xl`, horizontal padding on small screens.
- **One primary action per screen.** Secondary actions are text links, visually quieter.
- **The page head owns the h1.** Screens do not render their own top-level heading inside the
  content column.
- **Loading / error / empty replace the content column**, never the header.

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
  "Your teacher is building your personalized path. We'll let you know when it's ready." No
  action, or a quiet "Check again".
- `data-test` hooks stay stable: `loading`, `no-path`, `error`, `retry`, `locked` (already used
  in `PathView.vue`).

### Copy voice

- Second person, present tense, plain. "Open your next lesson", not "Continue your learning
  journey".
- Encouraging, not gamified. No confetti, no streak-shaming, minimal exclamation marks.
- Errors name what failed and offer one recovery. Never blame the user.
- One term per concept across all screens: **path**, **lesson** (a content node the student
  reads/watches), **practice** (a challenge's exercises), **step** (a path position).

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

The companion canvas holds one artboard per screen (S0–S8) at this fidelity — labelled boxes,
real copy, no colour commitment. Rough reference for the two screens that anchor the loop:

**S5 — My Path**

```
  My path
  ────────────────────────────────────
  Week 1 · Getting your hands moving          3 steps

  ①  ✓  Tuning and posture              completed
  ②  ▸  Your first chord: E minor       in progress   [ Open ]
  ③  🔒 Switching between chords         locked
```

**S6 — Node / Lesson**

```
  ‹ Back to path

  Your first chord: E minor                    [ Mark complete ]
  ────────────────────────────────────
  [ ▶  video player  ················· ]

  Notes
  Place your fingers on …
  [ inline chord diagram ]

  ── if this node has a challenge ──
  Ready to try it?                             [ Go to practice ]
```

---

## Open questions

| Question | Owner | Proposed resolution |
|---|---|---|
| Node routes nested under `/path` vs flat `/nodes/:id`? | Gilson | Nested — keeps "back to path" and browser-back consistent |
| Does a node with a challenge require *passing* it to count as complete, or is finishing the lesson enough for the alpha? | Gilson | Defer to PB-8f + the rules engine; affects the S6→S7→S5 status flow |
| Is `/path` the authenticated home, or is there a separate dashboard? | Gilson | `/path` is home; redirect `/` → `/path` when signed in. No separate dashboard in the alpha |
| Practice result — inline in S7 or a distinct screen? | Gilson | Inline in S7 |
| Account / profile screen for the alpha? | Gilson | No — "Sign out" in the header is enough; defer |
| Does the holding state (S4) poll, or is it refresh-only? | Gilson | Refresh-only for the alpha; a "Check again" link, no polling |

---

## Related

- **Backlog item:** PB-8j — Student alpha UX foundation (Notion `3ce9ccc1-102f-8150-ad87-dfac43a21a28`)
- **Consumers:** `plans/PB-8c-student-onboarding-auth.md`; PB-8d–8f (plans TBD)
- **Builds on:** `plans/PB-8b-web-app-foundation.md` (app shell, `AuthenticatedLayout`, state pattern)
- **Contracts:** `openapi/core-domain-service.yaml` (`GET /students/me/path`, `GET /content-nodes/*`,
  `GET /challenges/*`, `GET /exercises/*`), `openapi/event-ingestion-service.yaml` (`POST /events`)
- **Behaviour specs:** `features/learning-paths/student-path-view.feature`,
  `features/content-management/{content-nodes,challenges,exercises}.feature`
- **ADRs:** ADR-007 (auth), ADR-011 (node-completion state derived by the Aggregation Worker)
- **Brand:** `motifpath-brand/BRAND.md`, `motifpath-brand/colors.json` (colour tokens — `TBD`)
