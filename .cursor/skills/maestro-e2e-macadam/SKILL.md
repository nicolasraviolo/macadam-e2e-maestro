---
name: maestro-e2e-macadam
description: >-
  Create and maintain Maestro E2E tests for the Macadam mobile app in
  macadam-e2e-maestro. Use when writing YAML flows, subflows, run scripts,
  naming tests, mapping Qase cases, or debugging Android/iOS Maestro runs.
---

# Maestro E2E — Macadam

Read `docs/testing-guide.md` for platform quirks and learnings. This skill
covers **structure and naming** only.

## Repo layout

```
.maestro/
  smoke/        # runnable — no login
  auth/         # runnable — login / sign-up / onboarding
  profile/      # runnable — profile features
  regression/   # runnable — logged-in features (wallet, settings, …)
  subflows/     # reusable only — *.shared.yaml
  scripts/      # JS helpers (mock API)
scripts/        # run-*-test.sh entry points
```

## Naming rules

### Runnable flows (`smoke/`, `auth/`, `profile/`, `regression/`)

- **Format:** `kebab-case.yaml`
- **Prefer:** `{verb}-{noun}` — e.g. `view-profile.yaml`, `open-settings.yaml`, `convert-steps.yaml`
- **Long journeys:** `{journey}-to-{outcome}` — e.g. `signup-onboarding-to-home.yaml`
- **Probes:** `{name}-probe.yaml` — stops early for debugging
- **Never** use `.shared.yaml` in runnable folders

### Subflows (`subflows/`)

- **Always** `*.shared.yaml` — signals "import only, do not run alone"
- **UI steps only:** `{feature}-{action}.shared.yaml` — e.g. `login-password.shared.yaml`
- **Full setup (mock + launch):** `{feature}-with-mock.shared.yaml` — e.g. `login-with-mock.shared.yaml`
- **Platform split:** `{feature}-{platform}.shared.yaml` — e.g. `onboarding-health-ios.shared.yaml`

### Tags (top-of-file comment)

```yaml
# tags: smoke
# tags: auth, regression
# tags: auth, signup, onboarding, probe
# qase: MACADAM-269
```

| Tag | Meaning |
|-----|---------|
| `smoke` | Fast, no mock, no login — run on every PR |
| `auth` | Needs mock + credentials or creates account |
| `regression` | Logged-in feature test |
| `probe` | Diagnostic — not a full user story |
| `signup`, `onboarding`, `profile`, `wallet` | Optional area tags |

**Folder ≠ tag.** `auth/signup-onboarding-to-home.yaml` lives in `auth/` but is tagged `regression`.

### Run scripts

- New scripts: `scripts/run-{yaml-basename}-test.sh`
- Example: `regression/view-profile.yaml` → `run-view-profile-test.sh`

## Flow header template

```yaml
# tags: regression, profile
# qase: MACADAM-301
#
# What: View completed profile — fields, stickers, achievements load.
# Why:  Regression guard for profile overview (not edit).
#
# Prerequisites: mock server, MAESTRO_EMAIL / MAESTRO_PASSWORD in .env
# Run: ./scripts/run-view-profile-test.sh

appId: ${APP_ID}
---
```

## Composition pattern

```yaml
- runFlow:
    file: ../subflows/login-with-mock.shared.yaml
    env:
      APP_ID: ${APP_ID}
      MAESTRO_EMAIL: ${MAESTRO_EMAIL}
      MAESTRO_PASSWORD: ${MAESTRO_PASSWORD}

# feature steps…
- assertVisible:
    id: some.testID
```

**Do not** put `env: APP_ID:` at flow level — pass via `-e` from scripts.

## When to unify flows

Merge Qase cases into **one YAML** when they share the same start state and
one user session:

| Unified flow | Qase cases | Reason |
|--------------|------------|--------|
| `signup-onboarding-to-home.yaml` (+ extends) | 269, 270, 274, 277 | One new-user cold start |
| `regression/convert-steps-wallet-streak.yaml` | 272, 273, 275 | One conversion checks coins + streak + wallet |
| `smoke/tab-navigation.yaml` | 305 | Shell for tab tests |
| `regression/deals-tab-exploration.yaml` | 298, 299 | Same Deals tab |

Keep **separate** when auth mechanism or precondition differs (password vs Google OAuth).

## Qase smoke suite — automation status

| Qase | Title | Status | Maestro flow |
|------|-------|--------|--------------|
| 269 | Complete onboarding | ✅ Covered | `auth/signup-onboarding-to-home.yaml` |
| 302 | Profile — new user | ✅ Partial | `profile/edit-profile.yaml` |
| — | App launches | ✅ Covered | `smoke/app-launches.yaml` |
| — | Sign-in screen | ✅ Covered | `smoke/sign-in-screen.yaml` |
| — | Password login | ✅ Covered | `auth/login-password.yaml` |
| 305 | Tab navigation | 📋 Phase 1 | `smoke/tab-navigation.yaml` |
| 301 | Profile — existing user | 📋 Phase 1 | `regression/view-profile.yaml` |
| 304 | Settings | 📋 Phase 1 | `regression/open-settings.yaml` |
| 270 | Product tour (new users) | 📋 Phase 1 | extend `signup-onboarding-to-home.yaml` |
| 277 | Slomo gate (new users) | 📋 Phase 1 | extend `signup-onboarding-to-home.yaml` |
| 272–275 | Convert / streak / wallet | 📋 Phase 1 | `regression/convert-steps-wallet-streak.yaml` |
| 274 | Streak during product tour | 📋 Phase 2 | extend onboarding subflow |
| 276 | XP after conversion | 📋 Phase 2 | `regression/xp-after-conversion.yaml` |
| 298–299 | Offers wall / games | 📋 Phase 2 | `regression/deals-tab-exploration.yaml` |
| 300 | Spend coins (charity) | 📋 Phase 2 | `regression/spend-coins-donation.yaml` |
| 265, 266, 267, 268, 271, 278, 520, 521 | Various | 🖐 Manual | OAuth, email, physical steps, map |

## Legacy exceptions (rename when touched)

These subflows predate the `.shared.yaml` rule — rename on next edit:

- `login-with-mock.yaml` → `login-with-mock.shared.yaml`
- `signup-with-mock.yaml` → `signup-with-mock.shared.yaml`
- `signup-onboarding-with-mock.yaml` → `signup-onboarding-with-mock.shared.yaml`
- `dismiss-notifications-if-needed.yaml` → `dismiss-notifications-if-needed.shared.yaml`
- `dismiss-google-fit-auth-if-needed.yaml` → `dismiss-google-fit-auth-if-needed.shared.yaml`
- `login-custom-token.yaml` → `login-custom-token.shared.yaml`
- Remove `subflows/login-password.yaml` (duplicate of `auth/login-password.yaml`)

## Checklist for new tests

1. Pick folder (`smoke` / `auth` / `profile` / `regression`)
2. Name file `{verb}-{noun}.yaml` or `{journey}-to-{outcome}.yaml`
3. Add `# tags:`, `# qase:` (if applicable), What/Why comment
4. Reuse subflows — never copy-paste login
5. Prefer `id:` selectors; `TODO (app team)` for missing testIDs
6. Add `scripts/run-*-test.sh` if the flow needs mock + Metro
7. Update `docs/testing-guide.md` coverage table and Notion overview
