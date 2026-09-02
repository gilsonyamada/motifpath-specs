# Plan: Student Onboarding & Authentication — Sign-in to Registered Student

**Task:** PB-8c
**Date:** 2026-08-31
**Author:** Gilson
**Status:** Draft

---

## Goal

Take a new person from zero to a registered MotifPath student inside the app: they sign in with
Google via Clerk, the SPA registers them as a student through `POST /users`, and they land on an
authenticated screen — even when no learning path has been assigned yet. Implements backlog item
PB-8c (Notion PB-19).

## Product decisions (discovery pass, 2026-08-31)

1. **Onboarding is auth-only.** The product does sign-in + `POST /users {role: student}` and
   nothing else. All personalization intake (goals, current level, repertoire, taste) is captured
   **out-of-band** — a concierge call or external form — and feeds the teacher's manual path
   curation. There is **no in-product questionnaire**. Rationale: the MVP has no adaptive engine;
   the path is teacher-curated, so an intake questionnaire in the product would collect data
   nothing consumes.
2. **"Onboarding complete" = registered + landed in app.** The student authenticates,
   `POST /users` succeeds (or a 409 is reconciled), and they reach an authenticated screen. Not
   coupled to path assignment or first lesson — those are PB-8d/8e.

## Scope

**In scope (all in `motifpath-web`):**
- A branded sign-in screen at `/sign-in` (Clerk `<SignIn />`), honouring `?redirect=`
- A **first-run registration bridge**: after Clerk authentication, resolve the caller's MotifPath
  identity via `GET /users/me`; on 404, self-register via `POST /users {role: student}`; reconcile
  a 409 by re-reading `GET /users/me`
- A **"setting up your account" interstitial** shown while registration is in flight
- A **holding state** for a registered student with no assigned path ("You're all set — your
  teacher is building your path"), replacing the bare `no-path` text in `PathView`
- **Error + retry states** for a failed `GET /users/me` or `POST /users`
- A `useCurrentUser` Pinia store as the single source of the authenticated user's MotifPath
  profile, consumed by the router guard and layouts
- Router guard extension: `meta.requiresAuth` routes wait for registration to resolve, not just
  for the Clerk session
- Component/unit tests (test-first) for the store, the guard extension, the interstitial, and the
  holding state
- README update: the manual end-to-end onboarding smoke (real Clerk key + running `core-domain`)

**Out of scope:**
- Any onboarding questionnaire / goals / skill capture — **deliberately excluded** (see decisions)
- Teacher onboarding / `role: teacher` registration UI — not an alpha student concern
- Learning path rendering, progress, unlock — **PB-8d**
- Lesson consumption and event emission — **PB-8e**
- Email/notification when a path becomes ready — **out of scope**; the holding copy sets the
  expectation but no notification is built here
- Measuring onboarding completion rate — needs the **PB-8h** admin observation view; PB-8c emits
  no new event and adds no metrics surface (see Open Questions)
- Deployment / hosting — **PB-8a** (on hold); "landed in app" is validated locally

## Prerequisites

- [ ] **PB-8j — Student alpha UX foundation** accepted. PB-8c screens (sign-in, `/welcome`
      interstitial, registration error, the no-path holding state) are implemented against the
      screen inventory, page anatomy, and state components defined there
      (`design/PB-8j-student-alpha-ux-foundation.md`)
- [x] ADR-007 (Clerk auth + local JWT validation) accepted
- [x] `POST /users` and `GET /users/me` defined in `openapi/core-domain-service.yaml` and merged
- [x] PB-8b merged: `@clerk/vue`, `useAuth`, `authBridge`, generated core client, app shell,
      `dev` branch, CI
- [x] `features/user-registration/register-user.feature` covers the backend contract
- [ ] Clerk dev instance with Google OAuth enabled and a publishable key (Gilson)
- [ ] `motifpath-core` runs locally with a real Clerk secret key for the end-to-end smoke (Gilson)
- [ ] PB-8b loose end resolved or consciously ignored: `feat/PB-8b/local-dev-wiring` has one
      unmerged `docs:` commit not on `dev`

---

## Implementation Steps

### Phase 1 — Spec check (motifpath-specs)

**Branch:** `feat/PB-8c/plan-student-onboarding`

- [ ] Step 1: Confirm no OpenAPI change is required — `POST /users` (201 / 400 / 401 / 409) and
      `GET /users/me` (200 / 401 / 404) already cover every call the bridge makes
- [ ] Step 2: Confirm no new Gherkin is required in `motifpath-specs` — `register-user.feature`
      already specifies the backend behaviour (new-identity register, duplicate → 409, profile
      before register → 404, unauthenticated → 401). The SPA orchestration of these has no
      backend-observable behaviour of its own and is verified by `motifpath-web` component tests
- [ ] Step 3: Commit this plan to `motifpath-specs/plans/PB-8c-student-onboarding-auth.md`

**Definition of Ready check:**
- [x] API contracts the bridge depends on are defined and merged
- [x] ADR exists for the architectural choice (ADR-007 — auth; ADR-014 — identity resolution)
- [x] No new Gherkin needed — backend behaviour already specified in `register-user.feature`

---

### Phase 2 — Current-user store + registration bridge (motifpath-web)

**Branch:** `feat/PB-8c/student-onboarding` (from `dev`)

- [ ] Step 1: **Test first** — `src/features/auth/stores/__tests__/currentUser.spec.ts`:
  - signed out → store is `idle`, no requests made
  - signed in, `GET /users/me` → 200 → state `registered`, profile exposed
  - signed in, `GET /users/me` → 404 → store calls `POST /users {role: student}` → 201 →
    state `registered` with the returned profile
  - `POST /users` → 409 (identity already exists, race) → store re-reads `GET /users/me` → 200 →
    state `registered`
  - `GET /users/me` → 500, or `POST /users` → 400/401/500 → state `failed`, `retry()` re-runs
- [ ] Step 2: Implement `src/features/auth/stores/currentUser.ts` (Pinia): states
      `idle | registering | registered | failed`, actions `ensure()` and `retry()`, getters
      `profile`, `isRegistered`, `isResolving`. Uses `useApi().coreApi` only — never the raw client
- [ ] Step 3: Trigger `ensure()` from `App.vue` when `useAuth().isSignedIn` becomes true; reset to
      `idle` on sign-out
- [ ] Step 4: Extend the auth bridge (`src/features/auth/authBridge.ts`) with a registration
      readiness signal, mirroring the existing `isReady()` pattern, so the router guard can await
      `registered | failed` without importing Pinia

---

### Phase 3 — Guard, interstitial, and routing (motifpath-web)

**Branch:** `feat/PB-8c/student-onboarding`

- [ ] Step 1: **Test first** — `src/router/__tests__/guards.spec.ts` additions:
  - `requiresAuth` route, signed in, registration still `registering` → guard resolves to the
    `registering` route
  - registration `registered` → guard allows navigation to the target
  - registration `failed` → guard resolves to the `registration-error` route
- [ ] Step 2: Extend `createAuthGuard` to await the registration signal after the Clerk-session
      check and branch on its outcome
- [ ] Step 3: Add routes: `registering` (`/welcome`, public layout, no `requiresAuth` loop) and
      `registration-error` (`/welcome/error`). Both render dedicated views
- [ ] Step 4: **Test first**, then implement `src/features/auth/views/RegisteringView.vue` —
      "Setting up your account…" with the mandated loading pattern; auto-navigates to the stored
      `redirect` target (default: `path`) once the store reaches `registered`
- [ ] Step 5: **Test first**, then implement `RegistrationErrorView.vue` — explains registration
      didn't complete, `Try again` button calling `currentUser.retry()`

---

### Phase 4 — Sign-in screen + holding state (motifpath-web)

**Branch:** `feat/PB-8c/student-onboarding`

- [ ] Step 1: Wrap `SignInView.vue`'s `<SignIn />` in MotifPath chrome (logo, one line of
      context). Pass Clerk's `afterSignInUrl` / `afterSignUpUrl` as `/welcome` so every entry
      goes through the registration bridge
- [ ] Step 2: **Test first** — `PathView` renders a first-class holding state when
      `useStudentPath` reports `no-path`: heading, "Your teacher is building your personalized
      path", and what to expect next. Keep `data-test="no-path"`
- [ ] Step 3: Implement the holding state in `PathView.vue` (or extract
      `features/student/components/PathHoldingState.vue` if the template grows)
- [ ] Step 4: **Test first**, then update `HomeView.vue` so a signed-in, registered student sees a
      "Go to my path" primary action and a signed-in but `registering` student sees a neutral
      loading line (no dead links)

---

### Phase 5 — Local end-to-end smoke & PR (motifpath-web)

**Branch:** `feat/PB-8c/student-onboarding`

- [ ] Step 1: README section: bring up `motifpath-core` (`docker compose up -d` + both services
      with a real Clerk secret key), run `npm run dev`, then walk the flow: Google sign-in → land
      on `/welcome` → `POST /users` fires once → redirected to `/path` → holding state renders
- [ ] Step 2: Manually verify the 409 path: sign out, sign back in with the same Google account →
      `GET /users/me` returns 200 immediately, no second `POST /users`, straight to `/path`
- [ ] Step 3: Manually verify the failure path: stop `core-domain`, sign in → `/welcome/error`
      renders → restart `core-domain` → `Try again` → `/path`
- [ ] Step 4: `npm run lint`, `typecheck`, `test`, `build` green locally and in CI
- [ ] Step 5: Open the PR to `dev`

---

## Rollback Plan

`motifpath-web` is greenfield with nothing deployed (PB-8a on hold). Rollback is reverting the
feature PR on `dev` — no migrations, no data, no running service. If the guard extension causes a
redirect loop in practice, the guard change is the single revert point; the store and views are
inert without it.

## Validation

- [ ] Signed-out visit to `/path` → redirect to `/sign-in` (unchanged from PB-8b)
- [ ] First Google sign-in for an identity → exactly one `POST /users {role: student}` →
      redirect to `/path` → holding state renders
- [ ] Second sign-in for the same identity → zero `POST /users` calls → straight to `/path`
- [ ] `POST /users` returning 409 in a race → reconciled via `GET /users/me`, user still lands
- [ ] `core-domain` unreachable during sign-in → `/welcome/error`, and `Try again` recovers once
      the service is back
- [ ] `npm run lint`, `typecheck`, `test`, `build` pass locally and in CI
- [ ] No component imports `@/api/generated` or the raw client directly (per `CLAUDE.md`)

---

## Open Questions

| Question | Owner | Resolution |
|---|---|---|
| Registration bridge as a dedicated `/welcome` interstitial route vs. a gate component wrapping `<RouterView>` in `App.vue`? | Gilson | Proposed: dedicated `/welcome` route — visible in the URL, independently testable, no guard/layout coupling |
| Where does the student land post-registration — `/` or `/path`? | Gilson | Proposed: `?redirect=` target, default `path`, so the holding state is the first authenticated screen |
| Should the 400 "role invalid" branch be handled distinctly, or folded into the generic failure state? | Gilson | Proposed: fold in — the SPA always sends `role: student`, so a 400 is a bug, not a user condition; generic error + logged |
| How is onboarding completion rate actually measured, given PB-8c emits no event? | Gilson | Deferred to **PB-8h**: `registered_at` on `UserProfile` + Clerk sign-up counts, surfaced in the admin view. Note as a PB-8h input |
| Does `POST /users` need client-side idempotency (e.g. guard against double-fire in React/Vue strict re-renders)? | Gilson | The store's `registering` state gates re-entry; verify no double-fire in the Phase 2 tests |
| Is a `dev`-branch sync of the stray `feat/PB-8b/local-dev-wiring` docs commit a prerequisite, or handled separately? | Gilson | Proposed: separate tiny `docs` PB-8b PR, not a PB-8c blocker |

---

## Related

- **ADRs:** ADR-007 (Clerk auth + local JWT validation), ADR-009 (Clerk Go SDK — backend),
  ADR-014 (Event Ingestion resolves identity from Core Domain — same `GET /users/me` contract)
- **Spec files:** `openapi/core-domain-service.yaml` (`POST /users`, `GET /users/me`),
  `features/user-registration/register-user.feature`
- **Backlog item:** PB-8c — Student onboarding & authentication (Notion `3c99ccc1-102f-81b5-8c00-d98ee7a8eda9`)
- **Precedent:** `plans/PB-8b-web-app-foundation.md` (web foundation this builds on)
- **Repo conventions:** `motifpath-web/CLAUDE.md`, `motifpath-web/README.md`
