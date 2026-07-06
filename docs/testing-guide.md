# Testing guide — practices, learnings, and how to add flows

## Naming conventions (cheatsheet)

Full rules also live in `.cursorrules` and `.cursor/skills/maestro-e2e-macadam/SKILL.md`.

### Folders = app area

| Folder | Use for |
|--------|---------|
| `smoke/` | Fast checks — no login, no mock server |
| `auth/` | Login, sign-up, onboarding |
| `profile/` | Profile screens |
| `regression/` | Logged-in features (wallet, settings, home, deals…) |

### Runnable vs reusable

| Type | Where | Filename | Run with `maestro test`? |
|------|-------|----------|--------------------------|
| **Flow** | `smoke/`, `auth/`, `profile/`, `regression/` | `{verb}-{noun}.yaml` or `{journey}-to-{outcome}.yaml` | Yes |
| **Subflow** | `subflows/` | `{name}.shared.yaml` | No — `runFlow` only |

**Suffixes (flows only):** `-probe` (diagnostic) · `-android` / `-ios` (subflows when steps differ)

**Subflow entry points** that reset mock + launch: `{feature}-with-mock.shared.yaml`

### Tags vs folders

- **Folder** = where in the app (one per flow).
- **Tags** = when to run (`smoke`, `auth`, `regression`, `probe`).
- **Qase link:** `# qase: MACADAM-269` in the header when mapped to a manual case.

### Examples

| Good | Why |
|------|-----|
| `regression/view-profile.yaml` | verb-noun, correct folder |
| `regression/convert-steps-wallet-streak.yaml` | merges related Qase cases |
| `subflows/login-with-mock.shared.yaml` | clearly a subflow |
| `auth/signup-onboarding-probe.yaml` | probe suffix on runnable flow |

| Avoid | Why |
|-------|-----|
| `subflows/login-password.yaml` (no `.shared`) | ambiguous — runnable or not? |
| Same name in `auth/` and `subflows/` | confusing (legacy duplicate) |
| `regression/smoke-navigation.yaml` | folder and tag disagree |

### Legacy subflows (rename when you touch them)

These work today but predate the `.shared.yaml` rule:

`login-with-mock.yaml`, `signup-with-mock.yaml`, `signup-onboarding-with-mock.yaml`,
`dismiss-notifications-if-needed.yaml`, `dismiss-google-fit-auth-if-needed.yaml`,
`login-custom-token.yaml` — rename to `*.shared.yaml` on next edit.

---

## What we have today

| Tag | Flow | Qase | Needs mock? | Needs login? |
|-----|------|------|-------------|--------------|
| `smoke` | `smoke/app-launches.yaml` | — | No | No |
| `smoke` | `smoke/sign-in-screen.yaml` | — | No | No |
| `auth` | `auth/login-password.yaml` | — | Yes | Yes (password) |
| `auth`, `probe` | `auth/login-password-probe.yaml` | — | Yes | No (stops at password field) |
| `profile`, `auth` | `profile/edit-profile.yaml` | 302 (partial) | Yes | Yes (password) |
| `auth`, `signup` | `auth/signup-fresh-account.yaml` | — | Yes | Creates new account |
| `auth`, `signup`, `onboarding`, `regression` | `auth/signup-onboarding-to-home.yaml` | 269 | Yes | Sign-up through submit-steps slider |
| `auth`, `signup`, `onboarding`, `probe` | `auth/signup-onboarding-probe.yaml` | — | Yes | Sign-up through activity permission only |

**Working login account (local):** stored in `.env` as `MAESTRO_EMAIL` / `MAESTRO_PASSWORD`.

---

## Qase smoke suite — automation plan

Source: Qase export `MACADAM-2026-07-06.csv` (suite: Smoke test).

| Qase | Title | Automation | Target flow | Phase |
|------|-------|------------|-------------|-------|
| 269 | Complete onboarding (new user) | ✅ Covered | `auth/signup-onboarding-to-home.yaml` | — |
| 302 | Profile — new user | ✅ Partial | `profile/edit-profile.yaml` | — |
| 270 | Product tour (new users only) | 📋 Planned | extend `signup-onboarding-to-home.yaml` | 1 |
| 277 | Slomo not active until XP tap | 📋 Planned | extend `signup-onboarding-to-home.yaml` | 1 |
| 305 | Tab navigation | 📋 Planned | `smoke/tab-navigation.yaml` | 1 |
| 301 | Profile — existing user | 📋 Planned | `regression/view-profile.yaml` | 1 |
| 304 | Settings | 📋 Planned | `regression/open-settings.yaml` | 1 |
| 272 | Convert steps to coins | 📋 Planned | `regression/convert-steps-wallet-streak.yaml` | 1 |
| 273 | Streak after conversion | 📋 Planned | ↑ same flow | 1 |
| 275 | Coin balance after earning | 📋 Planned | ↑ same flow | 1 |
| 274 | Streak during product tour | 📋 Planned | extend onboarding subflow | 2 |
| 276 | XP after conversion (Slomo) | 📋 Planned | `regression/xp-after-conversion.yaml` | 2 |
| 298 | Open offers wall | 📋 Planned | `regression/deals-tab-exploration.yaml` | 2 |
| 299 | Games and surveys | 📋 Planned | ↑ same flow | 2 |
| 300 | Spend coins (charity) | 📋 Planned | `regression/spend-coins-donation.yaml` | 2 |
| 265 | Open app after update | 🖐 Manual | iOS update simulation | — |
| 266 | Google authentication | 🖐 Manual | OAuth / account picker | — |
| 267 | Apple authentication | 🖐 Manual | Face ID / system sheet | — |
| 268 | Magic link | 🖐 Manual | Email inbox + deep link (flaky) | — |
| 271 | Steps detected on Home | 🖐 Manual | Requires walking / health injection | — |
| 278 | Daily challenge completable | 🖐 Manual | Flaky; needs real step progress | — |
| 520 | Collect a coin on map | 🖐 Manual | Map / GPS state | — |
| 521 | Play slot machine | 🖐 Manual | Map spot + game mechanics | — |

**Unification notes:** 272+273+275 share one logged-in session; 298+299 share the Deals tab;
269+270+277 share the new-user onboarding path.

---

## Key learnings (from building login)

These cost us time — document them so we do not repeat:

### 1. App must talk to the mock server

In `~/macadam-app/.env.development`:

```env
E2E_TESTING=true
BASE_URL=http://localhost:4010
```

Then **rebuild** (`yarn android`). `E2E_TESTING` alone is not enough if `BASE_URL` still
points at preprod — the app will call the real API.

### 2. Launch flags need `config.test.ts`

`E2E_TESTING: true` in `src/config/env/config.test.ts` ensures Maestro launch arguments
(like `magic_link_enabled: false`) apply immediately. Without it, magic link can win
before `/config` loads.

### 3. Mock server must implement endpoints the app calls

After Firebase login, the app calls `GET /users`. That handler was missing → login
succeeded in Firebase but the app logged out. Add handlers in
`macadam-app/mock-server` as new flows need more APIs.

### 4. `hideKeyboard` before tapping Sign In

On Android, an open keyboard can swallow the Sign In tap. Always hide the keyboard
after typing the password.

### 5. Never hardcode credentials or env in YAML

A `env: MAESTRO_PASSWORD: ""` or old email in a flow **overrides** `.env` and CLI `-e`.
Pass secrets only via `.env` (gitignored) or `-e`, and forward them into nested
`runFlow` blocks explicitly.

### 6. Port forwarding on the emulator (Android only)

```bash
adb reverse tcp:8081 tcp:8081   # Metro
adb reverse tcp:4010 tcp:4010   # mock server
```

`run-login-test.sh` does this automatically. **iOS simulators do not need this** —
they reach `localhost` directly.

### 7. Each auth test starts fresh

`clearState: true` + mock `resetScenario` means every run logs in from scratch —
tests must not assume a previous session.

---

## Maestro best practices (for this project)

### Flow design

- **One flow = one user story** — short YAML, clear name (`kebab-case.yaml`)
- **Comment at the top** — what it validates and why (`# tags:`, prerequisites)
- **Assert state, do not only tap** — `assertVisible` / `extendedWaitUntil` after navigation
- **Idempotent** — safe to run alone or in any order (within the same tag group)

### Selectors (priority order)

1. `id:` — React Native `testID` (best: survives language/copy changes)
2. `text:` — only when no testID exists; mark `TODO (app team)` in the flow
3. Avoid coordinates and fragile partial text

**Known good IDs (auth):**

| Screen | testID |
|--------|--------|
| Email field | `common.label.email` |
| Password field | `common.label.password` |
| Next | `button.common.button.next` |
| Sign In | `button.signin.button` |
| Home avatar | `button_user_picture` |
| Welcome CTA | `onboarding.presignup.welcome.getStarted` (prefer over `"Get started"`) |
| Referral title | `referral.onboarding.submit.title` (not `"Did a friend invite you?"` — UI shows UPPERCASE) |
| Activity permission | `healthSync.activityPermission.title` |
| Google Fit connect | `healthSync.providerPermission.title` — Continue is plain text (broken testID) |
| Product tour home steps | `onboarding-home-step-1`, `onboarding-home-step-2` |
| Tab bar Home label | `home.tabBar.home` |
| Profile fields (edit) | `textfield.firstname`, `textfield.lastname`, `textfield.pseudo`, `textfield.city` |
| Profile edit (pen) button | **No testID yet** — tap point `84%, 7%` (TODO: app team) |

### Reuse with `runFlow`

| Subflow | Use when |
|---------|----------|
| `login-with-mock.yaml` | Full login from cold start (reset, flags, launch, login) |
| `login-password.shared.yaml` | UI steps only — already on welcome / mock already configured |
| `signup-with-mock.yaml` | **Fresh account** — random `maestro.e2e.*@macadam.app` + password sign-up |
| `signup-presignup.shared.yaml` | Welcome → personalization → sign-up email screen only |
| `signup-credentials.shared.yaml` | Enter email + password on Signup / ChoosePassword screens |
| `signup-onboarding-with-mock.yaml` | Sign-up with `referral_onboarding_enabled: true` |
| `onboarding-after-signup.shared.yaml` | Referral → health sync (per OS) → product tour → submit steps |
| `onboarding-after-signup-probe.shared.yaml` | Referral → first health screen only (fast) |
| `onboarding-health-android.shared.yaml` | Android health sync: activity recognition + Google Fit |
| `onboarding-health-ios.shared.yaml` | iOS health sync: HealthKit provider (needs verification) |
| `open-profile-from-tab.shared.yaml` | Tap tab-bar avatar → profile Overview |
| `profile-edit-fields.shared.yaml` | Open edit form, change fields, save, assert |
| `dismiss-google-fit-auth-if-needed.yaml` | Cancel Google OAuth WebView on emulator (SKIP → back) |
| `dismiss-notifications-if-needed.yaml` | After launch, before welcome assertions |

Example feature test (logged in):

```yaml
# tags: regression
appId: ${APP_ID}
---
- runFlow:
    file: ../subflows/login-with-mock.yaml
    env:
      APP_ID: ${APP_ID}
      MAESTRO_EMAIL: ${MAESTRO_EMAIL}
      MAESTRO_PASSWORD: ${MAESTRO_PASSWORD}

# … your feature steps …
- assertVisible:
    id: some.feature.element
```

Example onboarding test (fresh account):

Use the full flow instead of copying YAML:

```bash
./scripts/run-signup-onboarding-test.sh
```

Or compose subflows:

```yaml
# tags: regression, onboarding
appId: ${APP_ID}
---
- runFlow:
    file: ../subflows/signup-onboarding-with-mock.yaml
    env:
      APP_ID: ${APP_ID}
      MAESTRO_PASSWORD: ${MAESTRO_PASSWORD}

- runFlow:
    file: ../subflows/onboarding-after-signup.shared.yaml
    env:
      APP_ID: ${APP_ID}
```

### 8. Post sign-up onboarding quirks (Android)

- Enable **`referral_onboarding_enabled: true`** in launch flags and mock feature flags
  (`signup-onboarding-with-mock.yaml`) or the referral screen is skipped.
- **Accent headings are UPPERCASE on screen** — use `testID` (e.g. `referral.onboarding.submit.title`)
  instead of English copy for asserts.
- **Google Fit on emulator** opens a system WebView (`SKIP` button). Press **back** to return
  to Macadam and continue to the product tour — see `dismiss-google-fit-auth-if-needed.yaml`.
  Reuses patterns from `macadam-app/maestro/e2e/HealthIssues/google-fit.yaml`
  (`permission_allow_button`, `account_name`).
- **`HSHealthProviderPermission`** uses `title=` on SubmitButton → testID is `button.undefined`;
  tap visible **Continue** text there.

### 9. Cross-platform (Android + iOS)

The flows run on both platforms. Keep these in mind when writing new ones:

- **`APP_ID` must come from `-e`, not `config.yaml`.** In this Maestro version the
  `config.yaml` `env` block does **not** populate `${APP_ID}` (you get *"Unable to launch
  app undefined"*), and a flow-level `env: APP_ID:` **overrides** the CLI `-e`. So:
  - Do **not** put `env: APP_ID:` inside flows.
  - The run scripts pass `-e APP_ID=...` (Android → `com.macadamapp.beta`,
    iOS → `com.macadam.app.beta`). Running by hand, always add `-e APP_ID=...`.
- **Bundle ids:** Android `com.macadamapp.beta` · iOS `com.macadam.app.beta`.
- **Platform-specific steps** use Maestro's `when: platform: Android|iOS`. Health sync is
  split into `onboarding-health-android.shared.yaml` (Google Fit) and
  `onboarding-health-ios.shared.yaml` (HealthKit).
- **No `adb reverse` on iOS.** The simulator reaches `localhost:4010` / `:8081` directly.
  Android needs the reverse tunnels (`run-*.sh` do it).

#### iOS — hard-won build & run learnings (READ THIS before touching iOS)

Getting the app to even *run* on the iOS simulator took real effort. The facts:

- **Xcode 26.2 is required** (the app team's version). Not 16.x, not 26.6:
  - Xcode 16.x fails to *link* — the Fyber/InMobi ad SDK (`IASDKCore`) is a prebuilt
    binary that needs the **Swift 6.2 runtime** (`_swift_coroFrameAlloc`).
  - Xcode 26.6 fails to *compile* — its newer clang breaks React Native's bundled
    `fmt` (`consteval`).
  - Xcode **26.2** (Swift 6.2.3 + clang-1700) is the only one that both compiles and links.
  - The build points at it via `DEVELOPER_DIR=/Applications/Xcode-26.2.0.app/Contents/Developer`
    — `run-ios-tests.sh` sets this automatically, so no `sudo xcode-select` needed.
  - Needs an iOS runtime Xcode 26.2 accepts (e.g. iOS 26.3.x). Install once:
    `DEVELOPER_DIR=…/Xcode-26.2.0… xcodebuild -downloadPlatform iOS`.
- **Build with `ENVFILE=.env.development`** (REQUIRED):
  `ENVFILE=.env.development APP_VARIANT=beta npx expo run:ios --device "<sim>"`.
  `react-native-config` bakes env values from the file named by `$ENVFILE` (default
  `.env`, which does not exist here). Without it, `Config.*` is empty and the app
  red-screens at launch (*"token is not a valid string"* in `mixpanel.ts`, cascading to
  a bogus *"Cannot read property 'REMOTE_CONFIG' of undefined"*). Android gets this via
  the `withReactNativeConfig` gradle plugin; **iOS has no equivalent**.
- **Firebase plist:** the iOS project must contain `GoogleService-Info.plist`
  (from `config/firebase/GoogleService-Beta.plist`). If a build fails with
  *"Could not get GOOGLE_APP_ID"*, regenerate the native project cleanly:
  `APP_VARIANT=beta npx expo prebuild --clean -p ios` (the `@react-native-firebase/app`
  plugin copies it in). A non-clean prebuild-over-existing can also cause a
  *"Cycle inside MacadamBeta"* build error — `--clean` fixes that too.

#### iOS — Maestro flow differences vs Android

- **Onboarding ENTRY screen differs (confirmed on a pristine device):**
  - Android → welcome (`"WALK MORE EVERY DAY"` + `"Get started"`).
  - iOS → notifications intro (`"MACADAM WORKS WITH NOTIFICATIONS"` + `Continue`/`Later`).
  So first-screen asserts must be branched with `when: platform:` (see
  `smoke/app-launches.yaml`). Deeper flows need their iOS entry path mapped before they pass.
- **iOS collapses a screen into ONE `accessibilityText` blob** and Maestro does a
  **full (anchored) regex match**, so partial text needs wildcards:
  `visible: "(?i).*works with notifications.*"` (NOT `"(?i)works with notifications"`).
  On Android the same phrase is its own text node, so no wildcards are needed — this is
  why the same assertion can behave differently per platform.
- **Force English locale.** The iOS simulator can default to the Mac's language (e.g.
  Spanish), which breaks text asserts, and Maestro's `clearState` does **not** reset
  device language. `run-ios-tests.sh` sets `en-US` on the device (persists across
  `clearState`); set `FORCE_EN=0` to skip.
- **`clearState` does not clear the iOS keychain.** Firebase keeps its auth token in the
  Keychain, so `clearState` alone relaunches the app **already logged in**. Add
  `clearKeychain: true` to `launchApp` (iOS-only, ignored on Android). All flows that start
  from a logged-out state already do this.
- **`hideKeyboard` doesn't work on iOS** ("Couldn't hide the keyboard"). To dismiss it,
  tap a non-input element instead: a static text (e.g. `id: signIn.title`) or an empty gap
  between form fields (`point: "50%, 17%"` in profile edit). Android keeps `hideKeyboard`.
  These are branched with `when: platform:` in `login-password.shared.yaml` and
  `profile-edit-fields.shared.yaml`.
- **iOS keyboard covers bottom buttons.** After typing, the on-screen keyboard hides the
  "Next"/"Save"/sign-in CTAs, so you must dismiss it (see above) before tapping them.
- **iOS shows a system "Save Password?" prompt** after submitting login credentials, which
  covers the app. Dismiss it with an optional `tapOn: {text: "Not Now"}` (see the iOS block
  at the end of `login-password.shared.yaml`).
- **iOS bilingual keyboard popup.** A first-run "Type English and Spanish / Continue" system
  popup can steal input/cover CTAs. `run-ios-tests.sh` disables it via the simulator's
  `AppleKeyboardBilingualEnabled=false` + English-only keyboard in `.GlobalPreferences`.
- **Text field testIDs differ per platform.** The shared `TextInput` wraps its input in a
  container with `testID="textfield.<inner>"`. Android exposes the **inner** id
  (`common.label.email`); iOS exposes the **container** id (`textfield.common.label.email`).
  Branch the selector with `when: platform:` (see `login-password.shared.yaml`,
  `sign-in-screen.yaml`).
- **Driver flakiness:** Maestro 2.6.1 + Xcode 26.2 + iOS 26.3 is very new. Symptoms seen:
  `viewHierarchy` 500 `kAXErrorInvalidUIElement` (often around the Rive animation) and,
  after killing a stuck run, `Failed to connect to 127.0.0.1:<port>`. Fix: reboot the
  simulator clean (`xcrun simctl shutdown <udid> && … boot`) and re-run.

#### iOS status (what's actually validated)

- ✅ App **builds, installs, launches and runs** on the iOS 26.3 simulator.
- ✅ `smoke/app-launches.yaml` **passes on iOS** (platform-branched first-screen assert).
- ✅ `smoke/sign-in-screen.yaml` **passes on iOS** (dismiss notifications → welcome → sign-in).
- ✅ `auth/login-password.yaml` **passes on iOS** (clearKeychain + per-platform field ids +
  keyboard dismissal + "Save Password?" prompt handling).
- ✅ `profile/edit-profile.yaml` **passes on iOS** (login + edit fields + save).
- ✅ `auth/signup-onboarding-to-home.yaml` **passes on iOS** (full signup → personalization
  → ATT dialog → credentials → referral → HealthKit sync → product-tour coach marks →
  submit-steps slider).
- ✅ `auth/signup-fresh-account.yaml` **passes on iOS**.
- ✅ **iOS HealthKit sync verified** (`onboarding-health-ios.shared.yaml` runs green as part
  of the signup onboarding flow).

##### App-side accessibility fixes that unblocked iOS signup (IMPORTANT)

Two screens in `macadam-app` were flattening their whole subtree into a **single
accessibility element** on iOS, so Maestro/XCUITest saw one big text blob with no
addressable children (worked on Android, broke on iOS). Root cause in both: a
`Pressable` wrapping the content is `accessible={true}` by default on iOS, which makes
VoiceOver/XCUITest treat it (and all descendants) as one element. Fix = `accessible={false}`
on that wrapper (touch/keyboard-dismiss still works; children become individually
addressable — this also *improves* VoiceOver behaviour):

- `src/features/onboarding/screens/ONBPersonalizationScreen.tsx` — the outer
  `<Pressable onPress={Keyboard.dismiss}>` around the personalization `PageSliderView`.
- `src/components/Common/Highlight/HighlightTooltip.tsx` — the `TooltipContainer`
  (`PressableBox.Animated`) used by the product-tour coach marks.

If either regresses (wrapper made accessible again), iOS signup/tour flows will fail with
"element not found" on inner testIDs. Keep `accessible={false}` on Pressable/Touchable
wrappers whose only job is background tap handling.

##### Other iOS-only quirks handled in the signup flow

- **App Tracking Transparency:** after the permissions slide + the "Macadam respects your
  privacy" screen, iOS shows a custom dialog whose dismiss button is **"Cancel" or "Later"**
  (never tap "Open settings"), with a **variable, sometimes long delay**. `signup-presignup`
  polls (dismiss + advance) until the signup email field appears (iOS-only).
- **Animated elements crash the driver:** tapping/reading an *animated* element (the logo
  `sprite-animation`, Rive, etc.) throws `kAXErrorInvalidUIElement` ("Error getting element
  frame"). To dismiss the keyboard on signup screens we use a raw **coordinate** tap
  (`point: "50%, 25%"`), which needs no hierarchy/frame lookup, instead of tapping the logo.

---

### Scripts (`runScript`)

Keep HTTP calls to the mock server in `.maestro/scripts/api/` — not inline in YAML.
Existing helpers: `healthCheck.js`, `resetScenario.js`, `update-local-feature-flag.js`.

### Waits

- Prefer `extendedWaitUntil` with a timeout over fixed `sleep`
- `wait-for-config.js` (4s after launch, 2s after permissions) — only when the app needs time to fetch flags; prefer fixing init over adding more sleeps

### Tags

Add `# tags: smoke` or `# tags: auth, regression` at the top of each flow.

Run subsets:

```bash
maestro test --include-tags smoke .maestro/
maestro test --include-tags auth .maestro/
```

---

## How to add a new test (checklist)

1. **Describe the scenario** — start state, steps, success criteria; link Qase ID if any
2. **Pick the folder** — `smoke/`, `auth/`, `profile/`, or `regression/` (see naming cheatsheet)
3. **Name the file** — `{verb}-{noun}.yaml`; subflows always `subflows/{name}.shared.yaml`
4. **Pick tags** — `smoke` (fast) · `auth` (needs login) · `regression` (logged-in feature)
5. **Check selectors** — `maestro studio` on emulator; ask app team for missing testIDs
6. **Check mock server** — if the flow hits new APIs, add handlers in `macadam-app/mock-server`
7. **Reuse subflows** — `login-with-mock`, `signup-onboarding-with-mock`, etc.
8. **Run locally** and confirm pass (not assumed)
9. **Document** — update this guide's coverage table + Notion project overview

---

## Suggested improvements (next)

### Short term (this repo)

- [ ] Use `id: onboarding.presignup.welcome.getStarted` in smoke/auth flows (locale-safe)
- [ ] Add Phase 1 regression flows (`tab-navigation`, `view-profile`, `open-settings`, `convert-steps-wallet-streak`)
- [ ] Rename legacy subflows to `*.shared.yaml` when touched (see naming cheatsheet)
- [ ] Remove duplicate `subflows/login-password.yaml`
- [ ] `scripts/run-all-local.sh` — smoke first, then auth if mock+Metro up

### Medium term (with app team)

- [ ] E2E custom-token login (no Firebase password in CI secrets)
- [ ] CI-friendly **release E2E APK** (bundled JS, no Metro in pipeline)
- [ ] Expand mock server handlers (`/banking/accounts`, `/streaks`, …) as home features get tests
- [ ] testIDs on welcome screen and other text-only selectors

### CI-ready habits

- Keep scripts as the **single entry point** CI will call
- Never commit `.env` — use GitHub Secrets later
- Prefer **testID** selectors before CI multi-locale becomes a problem
- Tag flows so PRs run `smoke` only (~2 min) and nightly runs `auth` + `regression`

See [ci-future.md](./ci-future.md) for the GitHub Actions / Maestro Cloud plan.
