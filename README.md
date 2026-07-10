# macadam-e2e-maestro

End-to-end mobile tests for the **Macadam** app, using [Maestro](https://maestro.mobile.dev).
Runs locally on **Android emulator** and **iOS simulator**. **Beta** builds:
`com.macadamapp.beta` (Android) · `com.macadam.app.beta` (iOS).

The same flows run on both platforms. Android uses `./scripts/run-*.sh`; iOS uses the
generic `./scripts/run-ios-tests.sh` with `FLOW=...` (see [iOS section](#ios-simulator)).

## Status

| Suite | Android command | iOS | Ready? |
|-------|-----------------|-----|--------|
| Smoke (no login) | `./scripts/run-android-tests.sh` | `./scripts/run-ios-tests.sh` | Yes |
| Password login | `./scripts/run-login-test.sh` | `FLOW=.maestro/auth/login-password-ios.yaml ./scripts/run-ios-tests.sh` | Yes (iOS needs build) |
| Profile edit | `./scripts/run-profile-edit-test.sh` | `FLOW=.maestro/profile/edit-profile-ios.yaml ./scripts/run-ios-tests.sh` | Yes (iOS needs build) |
| Fresh sign-up | `./scripts/run-signup-test.sh` | `FLOW=.maestro/auth/signup-fresh-account.yaml ./scripts/run-ios-tests.sh` | Yes (iOS needs build) |
| Sign-up → onboarding → Home | `./scripts/run-signup-onboarding-test.sh` | `FLOW=.maestro/auth/signup-onboarding-to-home.yaml ./scripts/run-ios-tests.sh` | Android yes · iOS health-sync needs verification |
| Sign-up onboarding (fast probe) | `./scripts/run-signup-onboarding-probe-test.sh` | `FLOW=.maestro/auth/signup-onboarding-probe.yaml ./scripts/run-ios-tests.sh` | Yes (iOS needs build) |
| Tab navigation (Qase 305) | `./scripts/run-tab-navigation-test.sh` | `FLOW=.maestro/regression/tab-navigation.yaml ./scripts/run-ios-tests.sh` | Android ✅ |
| View profile (Qase 301) | `./scripts/run-view-profile-test.sh` | `FLOW=.maestro/regression/view-profile.yaml ./scripts/run-ios-tests.sh` | Android ✅ |
| Settings (Qase 304) | `./scripts/run-open-settings-test.sh` | `FLOW=.maestro/regression/open-settings.yaml ./scripts/run-ios-tests.sh` | Android ✅ |
| Phase 1 batch (305→301→304) | `SHUTDOWN_AFTER=0 ./scripts/run-phase1-regression-test.sh` | — | Android ✅ |
| Sign-up onboarding 270/277 | `./scripts/run-signup-onboarding-270-277-test.sh` | `FLOW=.maestro/auth/signup-onboarding-to-home.yaml ./scripts/run-ios-tests.sh` | Emulator blocked (Google Fit) |
| Deals / offers wall (298–299) | `./scripts/run-deals-tab-exploration-test.sh` | `FLOW=.maestro/regression/deals-tab-exploration.yaml ./scripts/run-ios-tests.sh` | Android ✅ (shell; games need API) |
| Charity spend (300) | `./scripts/run-spend-coins-charity-test.sh` | `FLOW=.maestro/regression/spend-coins-charity.yaml ./scripts/run-ios-tests.sh` | Android ✅ (charity cards need API) |
| Phase 2 batch (298→300) | `SHUTDOWN_AFTER=0 ./scripts/run-phase2-regression-test.sh` | — | Android ✅ |
| Convert steps / wallet (Qase 272–275) | `./scripts/run-convert-steps-test.sh` | `FLOW=.maestro/regression/convert-steps-wallet-streak.yaml ./scripts/run-ios-tests.sh` | New — may need step debug on emulator |
| CI (GitHub) | — | — | Planned — see [docs/ci-future.md](docs/ci-future.md) |

**Docs:** [Testing guide & learnings](docs/testing-guide.md) · [CI plan](docs/ci-future.md) · [Agent skill](.cursor/skills/maestro-e2e-macadam/SKILL.md)

---

## Quick start

### Prerequisites

1. [Maestro](https://maestro.mobile.dev) installed (`maestro --version`)
2. Android emulator with Macadam beta installed — see [builds/README.md](builds/README.md)
3. For login tests: `macadam-app` repo, mock server, Metro (below)

### Smoke tests (fastest — no login)

```bash
~/Desktop/macadam-e2e-maestro/scripts/run-android-tests.sh
```

Single flow:

```bash
FLOW=.maestro/smoke/app-launches-android.yaml ~/Desktop/macadam-e2e-maestro/scripts/run-android-tests.sh
```

### Password login test

**One-time app setup** in `~/macadam-app/.env.development`:

```env
E2E_TESTING=true
BASE_URL=http://localhost:4010
```

Rebuild: `cd ~/macadam-app && yarn android`

**Credentials** — copy and fill once:

```bash
cd ~/Desktop/macadam-e2e-maestro
cp .env.example .env   # set MAESTRO_EMAIL and MAESTRO_PASSWORD
```

**Three terminals:**

```bash
# 1 — mock server
cd ~/macadam-app && yarn mock-server:dev

# 2 — Metro
cd ~/macadam-app && yarn start

# 3 — test
cd ~/Desktop/macadam-e2e-maestro && ./scripts/run-login-test.sh
```

### Profile edit test

Logs in, opens **Profile** via the avatar in the bottom navigation bar, checks the default name, edits first name / last name / pseudo / city, saves, and verifies the changes on the profile screen.

```bash
cd ~/Desktop/macadam-e2e-maestro && ./scripts/run-profile-edit-test.sh
```

**Note:** restart the mock server after pulling app changes (`yarn mock-server:dev`) so profile saves persist correctly.

Probe (password field appears, no full login):

```bash
./scripts/run-login-probe.sh
```

### Fresh sign-up (random account)

Creates a **new** `maestro.e2e.<timestamp>.<random>@macadam.app` account each run — use this
before onboarding tests so you do not reuse the same user.

Same three terminals as login (mock + Metro + test):

```bash
cd ~/Desktop/macadam-e2e-maestro && ./scripts/run-signup-test.sh
```

Optional fixed email:

```bash
MAESTRO_EMAIL='maestro.e2e.manual@macadam.app' ./scripts/run-signup-test.sh
```

Default password: `Test123!` (override with `MAESTRO_PASSWORD` in `.env`).

### Sign-up → onboarding → Home (submit steps)

Full new-user path: sign-up, referral screen, health permissions, Google Fit, product tour,
and the **Validate my steps** slider on onboarding Home.

Same three terminals as login (mock + Metro + test):

```bash
cd ~/Desktop/macadam-e2e-maestro && ./scripts/run-signup-onboarding-test.sh
```

On the Android emulator, Google Fit opens a system sign-in screen — the test cancels it
automatically (same idea as `macadam-app/maestro/e2e/HealthIssues/google-fit.yaml`).

**While developing** — faster probe (referral + activity permission only, skips Google Fit and product tour):

```bash
./scripts/run-signup-onboarding-probe-test.sh
```

Run the full `./scripts/run-signup-onboarding-test.sh` before merging onboarding changes.

---

## iOS simulator

The flows are cross-platform. On iOS you use the same YAML files, but you must
build the app for the simulator once and let the script target the iOS bundle id.

### One-time setup (needs your password + a build)

```bash
# 1) Point the command-line tools at Xcode (not the Command Line Tools)
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept        # only if it asks

# 2) In macadam-app/.env.development, make sure you have:
#      E2E_TESTING=true
#      BASE_URL=http://localhost:4010
# 3) Build + install the app on the simulator:
cd ~/macadam-app && yarn ios
```

> The iOS simulator reaches the mock server / Metro on `localhost` directly —
> **no `adb reverse` needed** (that is Android-only).

### Run

Same three terminals as Android for login/onboarding tests (mock + Metro), then:

```bash
cd ~/Desktop/macadam-e2e-maestro

# Smoke (default flow)
./scripts/run-ios-tests.sh

# Any other flow
FLOW=.maestro/profile/edit-profile-ios.yaml ./scripts/run-ios-tests.sh

# Pick a specific simulator
SIM_NAME="iPhone 15 Pro" ./scripts/run-ios-tests.sh
```

**iOS driver flake:** local iOS 26 + Maestro can fail intermittently (`kAXErrorInvalidUIElement`,
`Connection refused`). The script auto-retries up to 3 times per flow (driver refresh between
attempts). Disable retries: `MAESTRO_IOS_MAX_RETRIES=0`. Details:
[testing guide — iOS driver stability](docs/testing-guide.md#ios-driver-stability-known-maestro--xctest-limitations).

The script checks Xcode, boots a simulator, verifies the app is installed and that
mock + Metro are up, then runs Maestro with `APP_ID=com.macadam.app.beta`. If a
prerequisite is missing it prints the exact command to fix it.

**Health-sync note:** onboarding health sync differs per OS (Android = Google Fit,
iOS = Apple Health / HealthKit). The iOS steps live in
`.maestro/subflows/onboarding-health-ios.shared.yaml` and are marked as needing a
first real simulator run to confirm the native HealthKit sheet labels.

---

## Run by tag

```bash
maestro test --include-tags smoke .maestro/
maestro test --include-tags auth .maestro/
```

---

## Environment variables

| Variable | Purpose | Where |
|----------|---------|-------|
| `APP_ID` | Package / bundle id | Android `com.macadamapp.beta` · iOS `com.macadam.app.beta` |
| `MAESTRO_EMAIL` | Test account email | `.env` (gitignored) |
| `MAESTRO_PASSWORD` | Test account password | `.env` (gitignored) |
| `SIM_NAME` | iOS simulator name (optional) | e.g. `iPhone 15 Pro` |

Never commit credentials. Scripts source `.env` automatically when present.

App-side (in `macadam-app/.env.development`, not this repo): `E2E_TESTING`, `BASE_URL`.

> **Important:** the run scripts pass `APP_ID` to Maestro with `-e APP_ID=...` so the
> right platform is targeted. If you run Maestro **by hand**, always add it, e.g.
> `maestro test -e APP_ID=com.macadam.app.beta .maestro/smoke/`. (A bare
> `maestro test .maestro/...` will fail with *"Unable to launch app undefined"* — the
> `config.yaml` default is not enough in this Maestro version.)

---

## Project layout

```
.maestro/
  config.yaml              # workspace defaults (APP_ID)
  smoke/                   # quick checks — no mock, no login
  auth/                    # login tests (mock server required)
  profile/                 # profile edit test
  subflows/                # reusable steps (login-with-mock, health sync per OS, etc.)
  scripts/                 # JS helpers (mock API health, reset, flags)
scripts/
  run-android-tests.sh     # Android emulator + any flow (FLOW=..., default smoke)
  run-ios-tests.sh         # iOS simulator + any flow (FLOW=..., default smoke)
  run-login-test.sh        # mock + Metro + login test (Android)
  run-profile-edit-test.sh # login + profile edit + save (Android)
  run-login-probe.sh       # password-path diagnostic (Android)
  run-signup-test.sh       # mock + Metro + fresh sign-up (Android)
  run-signup-onboarding-test.sh  # sign-up through onboarding Home + submit steps (Android)
  run-signup-onboarding-probe-test.sh  # faster: stops at activity permission (Android)
docs/
  testing-guide.md         # practices, learnings, how to add flows
  ci-future.md             # GitHub CI / Maestro Cloud plan
builds/                    # optional APK (not committed)
.env.example               # copy → .env for secrets
```

---

## Reuse login or sign-up in new flows

**Existing account (login):**

```yaml
- runFlow:
    file: ../subflows/login-with-mock.yaml
    env:
      APP_ID: ${APP_ID}
      MAESTRO_EMAIL: ${MAESTRO_EMAIL}
      MAESTRO_PASSWORD: ${MAESTRO_PASSWORD}
```

**Fresh account (sign-up):**

```yaml
- runFlow:
    file: ../subflows/signup-with-mock.yaml
    env:
      APP_ID: ${APP_ID}
      MAESTRO_PASSWORD: ${MAESTRO_PASSWORD}
```

Full checklist: [docs/testing-guide.md](docs/testing-guide.md)

---

## Discover selectors

With the app open on the emulator:

```bash
maestro studio
```

Prefer **testID** (`id:` in YAML) over visible text.

---

## Custom-token login (future)

Prepared but not required now that password + mock works:

- `.maestro/scripts/fetch-custom-token.js`
- `.maestro/subflows/login-custom-token.yaml`

Enable when the backend ships an E2E token endpoint — better for CI than shared passwords.

---

## New test scenario template

```
Name: (e.g. View wallet balance)

Tag: smoke | auth | regression

Start state: logged in / logged out

Steps:
1. ...
2. ...

Expected result: (what proves success — include testID if known)

Notes: Android first, needs mock server? new testIDs needed?
```

Send this to whoever writes the flow, or use it yourself — see the [testing guide](docs/testing-guide.md).
