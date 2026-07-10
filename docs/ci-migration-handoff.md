# CI migration handoff — Macadam Maestro E2E

**Audience:** developer implementing CI for mobile E2E tests  
**Status:** local E2E is working on Android (primary) and iOS (with known flake). CI is the next phase.  
**Repo:** `macadam-e2e-maestro` (tests only — app lives in `Moment-App/macadam-app`)

---

## 1. What this project is

| Piece | Location | Role |
|-------|----------|------|
| **Maestro flows** | `.maestro/` | YAML test definitions (smoke, auth, profile, regression) |
| **Run scripts** | `scripts/run-*.sh` | Single entry points: boot device, health checks, run Maestro |
| **Mock API helpers** | `.maestro/scripts/api/` | JS called from flows (`resetScenario`, feature flags, health) |
| **App + mock server** | `macadam-app` | React Native (Expo CNG) + Express mock server on `:4010` |
| **Credentials** | `.env` (gitignored) | `MAESTRO_EMAIL`, `MAESTRO_PASSWORD` |

Maestro is a **CLI tool** (not an npm dependency in the app). You install it in CI with:

```bash
curl -Ls "https://get.maestro.mobile.dev" | bash
export PATH="$HOME/.maestro/bin:$PATH"
```

**Do not** “reinstall a Maestro framework” in the app. Migrate **this repo’s YAML + scripts** and wire them to CI artifacts.

---

## 2. Architecture (how tests talk to the app)

```
┌─────────────┐   HTTP    ┌──────────────────┐   HTTP    ┌─────────────────┐
│   Maestro   │──────────>│   Mock server    │<──────────│  Macadam app    │
│  (flows)    │  :4010    │  macadam-app/    │  :4010    │  E2E_TESTING=   │
│             │           │  mock-server     │           │  true build     │
└─────────────┘           └──────────────────┘           └─────────────────┘
       │                                                          │
       │ UI automation                                            │
       └──────────────────────────────────────────────────────────┘
```

**Local today (dev build):**

- App built with `E2E_TESTING=true` and `BASE_URL=http://localhost:4010` in `macadam-app/.env.development`
- **Metro** on `:8081` serves JS bundle (dev client)
- **Mock server** on `:4010` serves API responses; Maestro resets scenario before each auth test
- Android: `adb reverse tcp:4010 tcp:4010` and `tcp:8081 tcp:8081` (done in `scripts/lib/run-mock-test.sh`)
- iOS simulator: `localhost` works directly (no adb reverse)

**CI target (recommended):**

- **No Metro** — build an E2E APK/IPA with JS bundle embedded (release-style or dedicated `e2e` flavor)
- **Mock server only** — still required unless you move to a dedicated E2E backend
- Scripts should accept `REQUIRE_METRO=0` (or a `CI=1` mode) to skip Metro health checks

---

## 3. App identifiers & builds

| Platform | Beta (used for E2E) | Production |
|----------|---------------------|------------|
| Android | `com.macadamapp.beta` | `com.macadamapp` |
| iOS | `com.macadam.app.beta` | `com.macadam.app` |

Run scripts pass `-e APP_ID=...` to Maestro. The `config.yaml` default alone is **not** enough in current Maestro version.

### Local build (today)

```bash
# In macadam-app — one-time per machine
# .env.development must include:
#   E2E_TESTING=true
#   BASE_URL=http://localhost:4010

yarn android   # Android emulator
yarn ios       # iOS simulator (iOS needs ENVFILE=.env.development — see run-ios-tests.sh)
```

Versioned regression builds: `scripts/build-app-at-version.sh` in this repo (checks out tag/branch in `macadam-app`, patches `app.json` label, runs `expo prebuild` + `expo run`).

### Team CI build (`build-apps.yml`)

Workflow: [macadam-app — Build iOS/Android Apps](https://github.com/Moment-App/macadam-app/actions/workflows/build-apps.yml)

- **Trigger:** `workflow_dispatch` (manual)
- **Inputs:** `version`, `lane` (e.g. `betaPreprod`, `firebasePreprod`), `platform` (`android` / `ios` / `both`)
- **Runs on:** reusable workflows `build-android-app.yml` / `build-ios-app.yml`
- **Android runner:** self-hosted label `Android` (macOS host with Android SDK)
- **Variant:** lanes containing `Preprod` → `beta` variant
- **Artifacts today:** mainly **AAB** bundles (`app-debug.aab`, `app-release.aab`), Hermes source maps — **not APK**

**Implication for E2E:** the existing release workflow is oriented to Play Console / TestFlight / Firebase distribution, not emulator sideloading. For CI you likely need **one of**:

1. **New job** in `macadam-app` (or this repo) that runs `assembleDebug` / `expo run:android` with E2E env baked in → upload **APK** artifact  
2. **Extend** `build-android-app.yml` to upload a debug APK when `lane` or a new input says `e2e`  
3. **`firebasePreprod` lane** → download APK from Firebase App Distribution in the test job  
4. **Maestro Cloud** — upload APK; Cloud runs emulator + Maestro (handles iOS without your own Mac farm)

For **nightly builds**, chaining is natural: nightly app build workflow → artifact → E2E workflow in `macadam-e2e-maestro` (or a monorepo job). For **on-demand**, `workflow_dispatch` on the E2E workflow with inputs for app version / artifact URL.

---

## 4. Test inventory & run matrix

### Tags (use for CI job selection)

| Tag | When to run | Needs mock? | Needs Metro (today)? | Needs credentials? |
|-----|-------------|-------------|----------------------|-------------------|
| `smoke` | PR / every run | No | No | No |
| `auth` | Nightly / on-demand | Yes | Yes (local) / No (CI bundle) | Yes (password) or future custom token |
| `regression` | Nightly | Yes | Yes (local) / No (CI bundle) | Yes (via login subflow) |

```bash
maestro test --include-tags smoke -e APP_ID=com.macadamapp.beta .maestro/
maestro test --include-tags auth,regression ...
```

### Runnable flows (high level)

| Area | Examples | Android status | iOS status |
|------|----------|----------------|------------|
| Smoke | `app-launches-*.yaml`, `sign-in-screen-*.yaml` | ✅ | ✅ (separate `*-ios.yaml` files) |
| Auth | `login-password-*.yaml`, `signup-onboarding-to-home.yaml` | ✅ | ✅ (HealthKit verified) |
| Profile | `edit-profile-*.yaml` | ✅ | ✅ |
| Regression | `tab-navigation`, `view-profile`, `open-settings`, `convert-steps-wallet-streak`, `deals-tab-exploration`, `spend-coins-charity` | ✅ | Partial / not all batched |

**Batch scripts (Android):**

- `run-phase1-regression-test.sh` — Qase 305, 301, 304
- `run-phase2-regression-test.sh` — Qase 298–300
- `run-all-local.sh` — smoke + auth if mock/Metro/credentials available

**Entry points CI should call** (same as local):

| Purpose | Script |
|---------|--------|
| Smoke only | `HEADLESS=1 ./scripts/run-android-tests.sh` |
| Single flow | `MAESTRO_FLOW=.maestro/regression/view-profile.yaml ./scripts/lib/run-mock-test.sh` |
| iOS | `FLOW=... ./scripts/run-ios-tests.sh` |

---

## 5. Key scripts (implementation detail)

| Script | Responsibility |
|--------|----------------|
| `run-android-tests.sh` | Boot `Pixel_7` AVD (or reuse), verify app installed, run smoke or `FLOW=` |
| `run-ios-tests.sh` | Xcode 26.2, boot simulator, mock/Metro checks, iOS driver retries |
| `scripts/lib/run-mock-test.sh` | Shared Android runner for auth/regression: mock + Metro + adb reverse + credentials |
| `scripts/lib/device-shutdown.sh` | Optional emulator shutdown (`SHUTDOWN_AFTER=1`) |
| `build-app-at-version.sh` | Pin app code to version tag/branch for regression |

**Env vars scripts already support:**

- `MACADAM_APP_ROOT` — path to app repo (default `~/macadam-app`)
- `AVD_NAME` — default `Pixel_7`
- `HEADLESS=1` — emulator without window
- `SHUTDOWN_AFTER=0|1`
- `MOCK_HEALTH_URL`, `METRO_URL`
- `MAESTRO_EMAIL`, `MAESTRO_PASSWORD` (from `.env` or CI secrets)
- `REQUIRE_MOCK_METRO=0` — iOS smoke only today; **add same for Android CI**
- `MAESTRO_IOS_MAX_RETRIES` — default 2 (3 attempts) for iOS flake

---

## 6. Mock server contract

Lives in `macadam-app/mock-server`. Maestro depends on:

| Endpoint | Used by |
|----------|---------|
| `GET /test/health` | All `run-*` scripts before tests |
| `POST /test/reset` | `resetScenario.js` — idempotent test start |
| Feature flag overrides | `update-local-feature-flag.js` — disables magic link, enables onboarding flags |

As flows grow, handlers must exist for APIs the app calls after login (`GET /users`, profile save, wallet, deals, etc.). Missing handlers → login succeeds in Firebase but app logs out or screens hang.

**CI:** start mock server in the same job or a service container:

```bash
cd macadam-app && yarn mock-server:dev   # or production start command
```

Ensure the E2E build’s `BASE_URL` points at wherever the mock listens (`http://localhost:4010` on the runner).

---

## 7. Known limitations (local → CI)

### Must fix or design around for CI

| Topic | Local behavior | CI risk / mitigation |
|-------|----------------|-------------------|
| **Metro** | Required for auth/regression dev builds | **Remove in CI** — ship bundled JS in E2E artifact; gate Metro checks with `CI=1` |
| **Firebase password login** | `MAESTRO_EMAIL` / `MAESTRO_PASSWORD` in secrets | Prefer **custom-token login** (`.maestro/subflows/login-custom-token.yaml` + `fetch-custom-token.js`) when backend endpoint exists |
| **Google Fit (Android onboarding)** | Emulator shows system sign-in; flow dismisses it | May differ on CI emulator image; `signup-onboarding-270-277` blocked locally on some emulators |
| **HealthKit (iOS onboarding)** | Handled in `onboarding-health-ios.shared.yaml` | Needs macOS simulator; Maestro Cloud device choice matters |
| **iOS driver flake** | `kAXErrorInvalidUIElement`, dead XCTest port | Retries in `run-ios-tests.sh`; Maestro Cloud iOS 18.x often more stable than local iOS 26 |
| **Xcode version** | **26.2 required** (Fyber SDK + RN `fmt` compile) | CI Mac runners must pin Xcode 26.2 |
| **iOS ENVFILE** | `ENVFILE=.env.development` at build time | E2E iOS build must bake correct env; empty Config → red screen at launch |
| **AAB vs APK** | Local uses installed debug build | CI must produce **APK** for emulator or use bundletool |
| **Self-hosted Android runners** | Team already uses `labels: Android` | Reuse for emulator + Maestro, or use GitHub-hosted + `android-emulator-runner` |
| **Timing / animations** | Rive, product tour, ATT dialogs | Use `extendedWaitUntil`; iOS warmup subflow `ios-launch-warmup.shared.yaml` |
| **OAuth / magic link / map / physical steps** | Marked manual in Qase | Out of scope for automation |

### Platform-specific test splits

Flows are split where Android ≠ iOS (keyboard, testID naming, health sync):

- `login-password-ios.shared.yaml` / `-android.shared.yaml`
- `login-with-mock-ios.shared.yaml` / `-android.shared.yaml`
- `onboarding-health-ios.shared.yaml` / `-android.shared.yaml`
- Runnable: `*-ios.yaml` / `*-android.yaml` for smoke and login

**CI:** run platform-specific files per job; do not run `maestro test .maestro/smoke/` as a folder on iOS.

---

## 8. Old `macadam-app/maestro/` folder — reuse or not?

| Item | Recommendation |
|------|----------------|
| **YAML flows in `macadam-app/maestro/e2e/`** | **Do not migrate from scratch** — logic already ported/evolved into **this repo** |
| **`maestro/scripts/api/*`** | **Superseded** by `.maestro/scripts/api/` here (same ideas, kept in sync manually) |
| **`google-fit.yaml`, onboarding YAMLs** | Reference only; patterns cited in `onboarding-health-android.shared.yaml` |
| **`maestro/README.md`** | Good architecture doc for mock-server concepts; keep in app repo |
| **Mock server** | **Keep in `macadam-app`** — single source of truth; CI starts it from app repo |
| **This repo (`macadam-e2e-maestro`)** | **Source of truth for E2E** going forward |

After CI is live, consider deprecating `macadam-app/maestro/` run scripts to avoid two test homes.

---

## 9. Recommended CI topology

### Option A — Maestro Cloud (recommended in `docs/ci-future.md`)

**Pros:** iOS without maintaining Mac runners; artifacts, retries, history  
**Cons:** Cost; upload step; Cloud device matrix

```text
Nightly (scheduled)
  macadam-app: build E2E APK/IPA (beta, E2E_TESTING, BASE_URL=mock, no Metro)
  macadam-e2e-maestro:
    start mock-server
    maestro cloud --app-file ... --env MAESTRO_EMAIL=... .maestro/ --include-tags auth,regression

On-demand: workflow_dispatch with version / artifact inputs
PR (optional): smoke only, Android, ~5 min
```

### Option B — Self-hosted (fits existing `build-apps.yml` infra)

```text
Job 1 (macadam-app, label Android): build debug APK + upload artifact
Job 2 (same or test repo): emulator + mock-server + maestro test --include-tags smoke
Job 3 (nightly): install APK, mock-server, maestro auth+regression

iOS: separate macOS runner or defer to Maestro Cloud
```

### Suggested schedule

| Trigger | Suite | Platform |
|---------|-------|----------|
| PR (optional) | `--include-tags smoke` | Android first |
| Nightly (after app nightly) | `auth` + `regression` | Android; iOS when stable |
| `workflow_dispatch` | User picks tags / flow | Both |

---

## 10. Concrete CI improvements (backlog)

### This repo

- [ ] `CI=1` or `REQUIRE_METRO=0` support in `run-mock-test.sh` and all auth wrappers
- [ ] GitHub Actions workflow: checkout app + test repo, download APK artifact, emulator, mock, maestro
- [ ] Secrets: `MAESTRO_EMAIL`, `MAESTRO_PASSWORD` (interim); later `MAESTRO_E2E_SECRET`
- [ ] Document artifact name / path contract with app build job
- [ ] Rename legacy subflows to `*.shared.yaml` (cosmetic)

### App repo (`macadam-app`)

- [ ] **E2E build target**: `E2E_TESTING=true`, `BASE_URL=http://localhost:4010`, bundled JS, output APK
- [ ] CI job uploads **APK** (not only AAB) for emulator tests
- [ ] Optional: `GET /users/e2e/custom-token` for passwordless CI login
- [ ] Expand mock handlers as regression suite grows

### Nice to have

- [ ] Qase / test report upload from Maestro output
- [ ] Parallel shards by tag (smoke vs regression)
- [ ] Pin emulator API level + device profile (match `Pixel_7` locally)

---

## 11. Emulator / device questions (FAQ)

**Can we run an emulator in GitHub Actions?**  
Yes. Options:

1. **Self-hosted runner** with KVM (team already has `labels: Android` on macOS) — closest to local `Pixel_7` setup  
2. **`reactivecircus/android-emulator-runner`** on `ubuntu-latest` — workable for smoke + many regression tests; slower cold boot  
3. **Maestro Cloud** — managed devices, no emulator maintenance

**What device should we use?**  
Local default: **Pixel_7** AVD (`AVD_NAME` env). For CI, pick one profile and pin it (e.g. `pixel_7_api_34`). Avoid changing DPI/size without re-checking flows that use coordinate taps (`point: "50%, 25%"` on iOS signup).

**iOS in CI?**  
Requires **macOS** runner with Xcode **26.2** and compatible iOS simulator runtime, **or** Maestro Cloud. Linux runners cannot run iOS simulators.

---

## 12. Docs map

| File | Content |
|------|---------|
| `README.md` | Quick start, commands, status table |
| `docs/testing-guide.md` | Learnings, selectors, iOS quirks, Qase mapping |
| `docs/ci-future.md` | Short CI sketch (Maestro Cloud leaning) |
| `builds/README.md` | How to obtain/install APK/IPA |
| `.cursor/skills/maestro-e2e-macadam/SKILL.md` | Naming conventions for agents |
| `.cursorrules` | Agent rules for maintaining tests |

---

## 13. Prompt for Claude / Cursor (copy-paste)

Use this when continuing CI work in this repo:

```text
You are implementing CI for Macadam mobile E2E tests (repo: macadam-e2e-maestro).

Context:
- Maestro YAML flows live in .maestro/ (smoke, auth, profile, regression + subflows/).
- The React Native app is in Moment-App/macadam-app (separate repo).
- Tests use a local mock server (macadam-app/mock-server on :4010). Auth/regression flows reset scenario via .maestro/scripts/api/resetScenario.js.
- Local dev builds require Metro (:8081) + E2E_TESTING=true + BASE_URL=http://localhost:4010 in macadam-app/.env.development.
- CI should NOT use Metro: build an E2E APK/IPA with JS bundle embedded and E2E env baked in.
- Android app id: com.macadamapp.beta. iOS: com.macadam.app.beta.
- Entry scripts: scripts/run-android-tests.sh (smoke), scripts/lib/run-mock-test.sh (auth/regression).
- Team app builds: macadam-app .github/workflows/build-apps.yml (workflow_dispatch, fastlane, beta Preprod variant). Currently uploads AAB; E2E needs APK for emulator.
- Old macadam-app/maestro/ is legacy; this repo is the source of truth for flows.
- Nightly: run auth + regression after app nightly build. On-demand: workflow_dispatch. Optional PR: smoke only.
- iOS needs Xcode 26.2; local iOS 26 simulators are flaky (retries in run-ios-tests.sh). Maestro Cloud is an option for iOS.

Your tasks:
1. Read docs/ci-migration-handoff.md, docs/ci-future.md, and docs/testing-guide.md.
2. Propose GitHub Actions workflow(s): build artifact job (or consume existing), mock server, emulator, maestro test.
3. Add CI=1 / REQUIRE_METRO=0 support to scripts without breaking local dev.
4. Wire secrets MAESTRO_EMAIL / MAESTRO_PASSWORD (or custom-token path if available).
5. Start with Android smoke on PR; nightly full regression; document device/API level.

Constraints:
- Do not hardcode credentials or absolute paths.
- Keep scripts as the single entry point CI calls.
- Prefer testID selectors; flows already split per platform where needed.
- Do not duplicate tests back into macadam-app/maestro/.

When unsure about app build flags, inspect macadam-app (E2E_TESTING, react-native-config, fastlane lanes).
```

---

## 14. Open decisions for the team

1. **Maestro Cloud vs self-hosted emulators** (especially for iOS)  
2. **New E2E APK build job** vs reusing `firebasePreprod` artifacts  
3. **Nightly trigger**: same pipeline as app release or separate schedule  
4. **Custom-token login** timeline vs shared Firebase test user in secrets  
5. **PR scope**: smoke-only Android vs full regression cost  
6. **Deprecating** `macadam-app/maestro/` once CI uses this repo  

---

*Generated for CI migration handoff. Update this doc when the first CI workflow lands.*
