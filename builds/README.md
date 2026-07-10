# Macadam app builds (for local Maestro tests)

This folder is where you **optionally** place installable app files when you are **not**
building directly from source. The files here are **not committed to git** (they are large
binaries).

> **Recommended approach:** build and install from the `macadam-app` repo (see below).
> You usually do **not** need to copy files here — Maestro launches the app by its ID once
> it is installed on the emulator or simulator.

---

## Where the Macadam mobile app lives

The mobile app is **not** in `macadam-core` (that repo is the backend). It is here:

| What | Where |
|------|--------|
| GitHub repo | [Moment-App/macadam-app](https://github.com/Moment-App/macadam-app) |
| Tech stack | React Native + Expo (CNG — native folders generated from config) |
| Existing Maestro tests | `maestro/` folder inside `macadam-app` (with mock server) |

This repo (`macadam-e2e-maestro`) is a **separate, independent** test project.

---

## App identifiers (for Maestro `appId:`)

Use the **beta** variant for local / preprod testing:

| Platform | Beta (recommended for tests) | Production |
|----------|------------------------------|------------|
| Android  | `com.macadamapp.beta`        | `com.macadamapp` |
| iOS      | `com.macadam.app.beta`       | `com.macadam.app` |

---

## How to get a build — four options

### Option 1 — Local dev build (recommended, simplest)

Build and install directly on your emulator or simulator. **No file needed in `builds/`.**

**Prerequisites (one-time setup in `macadam-app`):**

- Node 20, Yarn, Xcode (iOS), Android Studio (Android)
- Access to team secrets (1Password via `yarn env:fetch`, NPM token, etc.)
- See the [macadam-app README](https://github.com/Moment-App/macadam-app)

**Commands (beta / preprod variant):**

```bash
# Clone once (if you don't have it yet)
git clone git@github.com:Moment-App/macadam-app.git
cd macadam-app

# First-time setup (follow README in that repo)
yarn install
yarn env:fetch          # downloads .env files from 1Password — ask your team for access
yarn expo:prebuild      # generates android/ and ios/ folders

# Start emulator/simulator, then:
yarn android            # builds + installs on Android emulator/device
# OR
yarn ios                # builds + installs on iOS simulator/device
```

After this, the app is installed. Maestro finds it by `appId` (see table above).

#### Build a specific version (for Maestro regression)

Use `scripts/build-app-at-version.sh` from **this** repo. It does two things:

1. **Checks out the code** at tag `vX.Y.Z` or branch `release/X.Y.Z` in `macadam-app`
2. **Temporarily patches** `app.json` so the installed app shows that version number

The `app.json` change is **never committed** — the script restores it when it finishes.

```bash
# Released version (tag exists)
~/Desktop/macadam-e2e-maestro/scripts/build-app-at-version.sh 8.3.1 android

# 8.4.0 — no git tag yet; team builds from dev via CI (VERSION=8.4.0)
ALLOW_DEV_FALLBACK=1 ~/Desktop/macadam-e2e-maestro/scripts/build-app-at-version.sh 8.4.0 android

# iOS (needs Xcode 26.2 + simulator)
SIM_NAME="iPhone 15" ALLOW_DEV_FALLBACK=1 ~/Desktop/macadam-e2e-maestro/scripts/build-app-at-version.sh 8.4.0 ios
```

**Prerequisites:** Android emulator running (Pixel_7). The script auto-detects it.

**Important:** changing `app.json` only sets the version *label*. The actual app code
(features, fixes, UI) comes from the git checkout. Versions like **8.4.0** that exist
only as CI builds (no `v8.4.0` tag) use `ALLOW_DEV_FALLBACK=1` → code from `origin/dev`.

---

### Option 2 — Copy a debug APK here (Android only)

Useful if someone sends you an APK or you build without keeping the repo open.

**Build the APK locally (in `macadam-app`):**

```bash
cd macadam-app
yarn expo:prebuild -p android
cd android
./gradlew assembleDebug
```

**Output file:**

```
macadam-app/android/app/build/outputs/apk/debug/app-debug.apk
```

**Copy it here:**

```bash
cp /path/to/macadam-app/android/app/build/outputs/apk/debug/app-debug.apk \
   builds/android-beta-debug.apk
```

**Install on a running emulator:**

```bash
adb install -r builds/android-beta-debug.apk
```

---

### Option 3 — Download from CI (team members with access)

The app team builds via **GitHub Actions + Fastlane**:

| Trigger | Result |
|---------|--------|
| Comment `/qa android` on a PR | Android AAB → Google Play **internal** track (beta preprod) |
| Comment `/qa ios` on a PR | iOS build → **TestFlight** (beta preprod) |
| Release workflows | Production builds → App Store / Play Store |

**Pros:** Official signed builds, same as QA.  
**Cons:** Needs GitHub/Play Console/TestFlight access; AAB/IPA are not ideal for quick
local emulator testing (Play internal and TestFlight require extra install steps).

Ask a teammate for Play Console internal testing or TestFlight access if you go this route.

---

### Option 4 — Firebase App Distribution (if your team uses it)

Fastlane lanes `firebasePreprod` and `firebaseProd` exist in `macadam-app/fastlane/`.
If your team distributes builds via Firebase, download the APK from the Firebase console
and place it in `builds/` (same as Option 2).

---

## What to put in this folder (if you use it)

| File name (suggested) | Platform | Format | When to use |
|-----------------------|----------|--------|-------------|
| `android-beta-debug.apk` | Android | APK | Local emulator testing (debug build) |
| `android-beta-release.aab` | Android | AAB | Play Store–style build (harder to sideload) |
| `ios-beta-simulator.app` | iOS | .app bundle | iOS **simulator** only (not for physical device) |

> **iOS note:** Maestro on the simulator uses an app already installed via Xcode/`yarn ios`,
> or a `.app` built for the simulator. You cannot install a TestFlight `.ipa` on the simulator.

---

## TODO — things you need from your team

- [ ] **Git access** to `Moment-App/macadam-app`
- [ ] **1Password / env files** — run `yarn env:fetch` in macadam-app (or ask for `.env` setup)
- [ ] **NPM token** — for private `@macadam.app/*` packages (if building from source)
- [ ] **Confirm variant** — use **beta** for preprod backend during E2E tests
- [ ] **Test user credentials** — for login flows (never commit these; use `MAESTRO_*` env vars)

---

## Quick check: is the app installed?

**Android:**

```bash
adb shell pm list packages | grep macadam
# Expect: package:com.macadamapp.beta
```

**iOS (simulator):**

```bash
xcrun simctl listapps booted | grep -i macadam
```

If you see the package/bundle, you are ready to run Maestro flows.
