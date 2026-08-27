# Plan: motifpath-web Foundation — Scaffold, Generated API Client, Clerk Auth Context, App Shell

**Task:** PB-8b
**Date:** 2026-08-27
**Author:** Gilson
**Status:** Ready

---

## Goal

Build `motifpath-web` from an empty repo to a running Vue 3 SPA skeleton that every student
slice (PB-8c–PB-8h) builds on: build tooling, generated TypeScript API client, an authenticated
Clerk session available to components, an app shell with routing, and local-dev wiring against
the already-merged `motifpath-core` services.

## Scope

**In scope:**
- Vite + Vue 3 + TypeScript (strict) project scaffold matching the directory structure and rules
  already documented in `motifpath-web/CLAUDE.md` and `README.md`
- Toolchain: Tailwind CSS + `tailwind.config.ts` design tokens, Pinia, Vue Router, Vitest + Vue
  Test Utils, ESLint + Prettier — with `package.json` scripts that satisfy the existing CI
  (`lint`, `typecheck`, `test`, `test:coverage`, `build`, `dev`, `generate:api`)
- `generate:api` script producing `src/api/generated/` types from **both** specs
  (`core-domain-service.yaml`, `event-ingestion-service.yaml`) via `openapi-typescript`
- A thin typed transport wrapper (`openapi-fetch`) that injects the Clerk bearer token and reads
  base URLs from Vite env vars — one client per service
- Clerk wiring (`@clerk/vue`): plugin registration, `useAuth` composable exposing session state +
  a `getToken()` accessor, a Vue Router navigation guard for authenticated routes
- App shell: a public layout and an authenticated layout, top-level named routes, placeholder
  route views (`/`, `/path`), a 404 view, and the loading/error-state pattern components must follow
- Local-dev wiring: `.env.example`, README run instructions for `npm run dev` alongside
  `docker compose up` + `go run` in `motifpath-core`
- Establish the protected `dev` branch in `motifpath-web` and update CI triggers to include it

**Out of scope:**
- Student registration / `POST /users` / onboarding flow — **PB-8c**
- Learning path view, progress, unlock logic — **PB-8d**
- Lesson consumption and event emission helpers — **PB-8e**
- Practice / fretboard runner / assessment — **PB-8f**
- Any teacher-facing UI
- Deployment, hosting, S3/CloudFront, CDN env config — **PB-8a** (on hold)
- A test-coverage gate — not required for PB-8b (decided 2026-08-27). Test-first is still
  mandatory for the transport wrapper, `useAuth`, and the guard, per the TDD mandate

## Prerequisites

- [x] `openapi/core-domain-service.yaml` merged to `motifpath-specs` main
- [x] `openapi/event-ingestion-service.yaml` merged to `motifpath-specs` main
- [x] ADR-007 (Clerk auth + local JWT validation) accepted
- [x] `motifpath-core` runs locally: `docker compose up -d` + `go run` the two services (ports 8080 / 8081)
- [ ] Clerk development instance created, with Google OAuth enabled and a publishable key available (Gilson)
- [ ] Confirmed: `motifpath-core` HTTP services allow the local Vite origin (`http://localhost:5173`) via CORS — if not, a small `chore` on `motifpath-core` is needed first (see Open Questions)

---

## Implementation Steps

### Phase 1 — Spec check (motifpath-specs)

**Branch:** `feat/PB-8b/plan-web-app-foundation`

- [ ] Step 1: Confirm no spec change is required — the two OpenAPI contracts already cover every
      call the shell makes (`GET /users/me` for the smoke test; no new endpoint)
- [ ] Step 2: Commit this plan to `motifpath-specs/plans/PB-8b-web-app-foundation.md`

**Definition of Ready check:**
- [x] API contract(s) the shell depends on are defined and merged
- [x] ADR exists for the architectural choice this introduces (ADR-007 — auth)
- [ ] No new Gherkin needed: PB-8b is an enabler with no user-facing behaviour of its own

---

### Phase 2 — Scaffold & toolchain (motifpath-web)

**Branch:** `feat/PB-8b/web-app-foundation` (from `dev` once it exists — see Step 6)

- [ ] Step 1: Scaffold Vite + Vue 3 + TS. Set `"strict": true`, path alias `@/` → `src/`
- [ ] Step 2: Create the directory tree from `CLAUDE.md` (`src/features/{student,teacher,auth}`,
      `src/shared/{components,composables,utils,types}`, `src/api/generated`, `src/stores`, `src/router`)
- [ ] Step 3: Add Tailwind + `tailwind.config.ts` with a starter design-token scale (colors, spacing)
      sourced from `motifpath-brand` tokens where available; wire PostCSS
- [ ] Step 4: Add Pinia and Vue Router, register both in `src/main.ts`
- [ ] Step 5: Add Vitest + Vue Test Utils + jsdom; add ESLint (vue + ts) + Prettier configs
- [ ] Step 6: Author `package.json` scripts — `dev`, `build`, `typecheck` (`vue-tsc --noEmit`),
      `lint`, `test`, `test:coverage`, `generate:api` — names must match `.github/workflows/ci.yml`
- [ ] Step 7: Create the `dev` branch, set it as the CI + branch-protection target; update
      `ci.yml` triggers to `[main, dev]` for push and `pull_request` (currently `main` only)
- [ ] Step 8: Commit the raw scaffold and generated lockfile as `chore` before any app code

---

### Phase 3 — Generated API client + typed transport (motifpath-web)

**Branch:** `feat/PB-8b/web-app-foundation`

- [ ] Step 1: Add `openapi-typescript` + `openapi-fetch`. `generate:api` bundles each spec with
      `@redocly/cli` then runs `openapi-typescript` → `src/api/generated/core-domain.ts` and
      `src/api/generated/event-ingestion.ts` (parity with `motifpath-core`'s `make generate`)
- [ ] Step 2: Run `generate:api`, commit the output as `chore(codegen)` — separate commit, no hand edits
- [ ] Step 3: **Test first** — `src/api/__tests__/client.spec.ts`: asserts the transport attaches
      `Authorization: Bearer <token>` from the injected token getter and targets the configured base URL
- [ ] Step 4: Implement `src/api/coreClient.ts` / `src/api/eventsClient.ts` — `openapi-fetch`
      clients typed by the generated paths, base URL from `import.meta.env`, a middleware that calls
      the auth token getter per request. Make the test pass
- [ ] Step 5: Add `src/shared/composables/useApi.ts` (or per-feature composables) as the only
      component-facing entry point — components never import the raw client (per `CLAUDE.md`)

---

### Phase 4 — Clerk auth context (motifpath-web)

**Branch:** `feat/PB-8b/web-app-foundation`

- [ ] Step 1: Add `@clerk/vue`; register the plugin in `src/main.ts` with
      `VITE_CLERK_PUBLISHABLE_KEY`
- [ ] Step 2: **Test first** — `useAuth` composable spec: unauthenticated → `isSignedIn === false`
      and guarded navigation redirects to the sign-in route; authenticated (mocked Clerk) →
      `getToken()` resolves a JWT
- [ ] Step 3: Implement `src/features/auth/composables/useAuth.ts` wrapping Clerk's session,
      exposing `isSignedIn`, `isLoaded`, `getToken()`, `signOut()`
- [ ] Step 4: Wire `getToken()` into the Phase 3 transport middleware (replace the placeholder getter)
- [ ] Step 5: Add `src/router/guards.ts` — a `beforeEach` guard that blocks `meta.requiresAuth`
      routes until Clerk `isLoaded`, then redirects unauthenticated users to `sign-in`
- [ ] Step 6: Add a minimal `sign-in` route rendering Clerk's `<SignIn />` (full onboarding UX is PB-8c)

---

### Phase 5 — App shell + routing (motifpath-web)

**Branch:** `feat/PB-8b/web-app-foundation`

- [ ] Step 1: `src/shared/components/PublicLayout.vue` and `AuthenticatedLayout.vue`
      (nav shell, header, sign-out, `<RouterView />`)
- [ ] Step 2: `src/router/index.ts` — named routes only: `home` (`/`), `path` (`/path`,
      `requiresAuth`), `sign-in` (`/sign-in`), `not-found` (`/:pathMatch(.*)*`)
- [ ] Step 3: Placeholder views `src/features/student/views/HomeView.vue` and `PathView.vue`
      that demonstrate the mandated loading + error-state pattern around a data fetch
- [ ] Step 4: `NotFoundView.vue`
- [ ] Step 5: Component tests — layout renders nav; guard redirects unauthenticated user away
      from `/path`; 404 route renders `NotFoundView`

---

### Phase 6 — Local-dev wiring & end-to-end smoke (motifpath-web)

**Branch:** `feat/PB-8b/web-app-foundation`

- [ ] Step 1: `.env.example` — `VITE_CLERK_PUBLISHABLE_KEY`, `VITE_CORE_API_URL=http://localhost:8080`,
      `VITE_EVENTS_API_URL=http://localhost:8081`
- [ ] Step 2: README section: run `docker compose up -d` + both services (`go run`) in
      `motifpath-core`, then `npm run dev`; note the Clerk key requirement
- [ ] Step 3: Manual smoke: sign in via Clerk in the running app, have `HomeView` call
      `GET /users/me` on the core client, confirm a typed response comes back (200, or a
      well-formed 401/404 — the point is transport + auth header + generated types all work)
- [ ] Step 4: Open the PR to `dev` (see Validation checklist)

---

## Rollback Plan

`motifpath-web` is greenfield with nothing deployed (PB-8a on hold), so rollback is low-risk:
revert the feature PR(s) on `dev`. No migrations, no data, no running service. If the `dev`
branch / CI-trigger change (Phase 2 Step 7) causes problems, revert `ci.yml` and delete `dev`.

## Validation

- [ ] `npm run lint`, `npm run typecheck`, `npm run test`, `npm run build` all pass locally and in CI
- [ ] `npm run build` emits `dist/`; `npm run dev` serves the app
- [ ] `npm run generate:api` produces zero diff when the specs are unchanged
- [ ] Components can obtain an authenticated Clerk session via `useAuth`; `getToken()` returns a JWT
- [ ] Navigating to `/path` while signed out redirects to `/sign-in`
- [ ] A view calls a locally-running `core-domain` (`localhost:8080`) through the generated client
      with the Clerk JWT and receives a typed response
- [ ] `dev` branch exists, is protected, and is the CI + PR target

---

## Open Questions

| Question | Owner | Resolution |
|---|---|---|
| `@clerk/vue` official SDK vs `@clerk/clerk-js` + custom plugin? | Gilson | **Decided: `@clerk/vue`** (2026-08-27) |
| Adopt a coverage gate for this slice? | Gilson | **Decided: no gate for PB-8b** (2026-08-27); test-first still applies to the transport wrapper, `useAuth`, and the guard |
| Who provisions the Clerk dev instance + Google OAuth + test users? | Gilson | Gilson, with Claude's help, when Phase 4/6 needs it |
| Do `motifpath-core` HTTP services allow `http://localhost:5173` via CORS? If not, precede this with a `chore(core)` to add local CORS | Gilson | Confirmed in principle; verify in the `motifpath-core` HTTP adapter before Phase 6, add `chore(core)` if missing |
| Does `generate:api` need the `@redocly/cli` bundle step, or does `openapi-typescript` resolve the `$ref`s itself? | Gilson | Default to bundling for parity with `motifpath-core`'s `make generate` |
| Vite dev proxy for `/api` vs direct cross-origin calls with CORS? | Gilson | Proposed: direct calls + CORS, keeps prod/local parity |

---

## Related

- **ADRs:** ADR-007 (Clerk auth + local JWT validation), ADR-009 (Clerk Go SDK — backend context)
- **Spec files:** `openapi/core-domain-service.yaml`, `openapi/event-ingestion-service.yaml`
- **Backlog item:** PB-8b — Web app foundation (motifpath-web) (Notion `3c99ccc1-102f-8139-9cd4-e95442fce187`)
- **Repo conventions:** `motifpath-web/CLAUDE.md`, `motifpath-web/README.md`
- **Precedent:** `plans/PB-8-motifpath-core-implementation.md` (backend scaffold plan)
