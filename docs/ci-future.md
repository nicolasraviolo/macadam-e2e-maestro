# CI integration (future phase)

This repo is set up for **local** E2E first. CI is the next step — this document
records the recommended approach so we do not paint ourselves into a corner while
writing flows today.

## Recommended: Maestro Cloud

[Maestro Cloud](https://maestro.mobile.dev/cloud) is the best fit for Macadam because:

| Challenge | Why Maestro Cloud helps |
|-----------|-------------------------|
| iOS tests need macOS | Cloud runs iOS simulators — no self-hosted Mac runners |
| Emulator flakiness | Managed devices, retries, artifacts (screenshots, logs) |
| Team visibility | PR checks, shared test history |

**Alternative (Android-only CI):** GitHub Actions + `reactivecircus/android-emulator-runner`
+ local Maestro CLI. Cheaper, but no iOS and more maintenance.

## What to design for now (local → CI)

Flows and scripts should already follow these rules — they map directly to CI:

1. **No hardcoded secrets** — `MAESTRO_EMAIL`, `MAESTRO_PASSWORD` from CI secrets
2. **No absolute paths** — use repo-relative paths in YAML and scripts
3. **Health checks before tests** — mock server (`/test/health`), Metro (`8081/status`)
4. **Idempotent flows** — `clearState: true` + mock `resetScenario` per run
5. **Tags** — `smoke` vs `auth` so CI can run fast checks on every PR
6. **One app build artifact** — E2E build with `E2E_TESTING=true` and `BASE_URL` pointing at mock

## Likely CI pipeline (sketch)

```text
PR opened
  │
  ├─ Job: build-android-e2e (macadam-app)
  │     E2E_TESTING=true, BASE_URL=http://localhost:4010
  │     → upload APK artifact
  │
  ├─ Job: maestro-smoke (this repo)
  │     start mock-server (from macadam-app or npm package)
  │     install APK on emulator / Maestro Cloud device
  │     maestro test --include-tags smoke .maestro/
  │
  └─ Job: maestro-auth (optional / nightly)
        requires mock + Metro OR release build with embedded bundle
        maestro test --include-tags auth .maestro/
```

Exact wiring depends on whether tests run against:

- **Dev build + Metro** (current local setup) — harder in CI; needs Metro job + `adb reverse`
- **Release-style E2E APK** (bundled JS, mock server only) — **preferred for CI**

## Open items before turning CI on

### App repo (`macadam-app`)

- [ ] E2E build flavor or workflow that bakes `E2E_TESTING=true` + mock `BASE_URL`
- [ ] Mock server `GET /users` and other endpoints tests hit (extend as flows grow)
- [ ] Optional: E2E custom-token endpoint (removes Firebase password dependency in CI)
- [ ] More `testID`s on onboarding welcome CTA (locale-independent selectors)

### Backend

- [ ] Dedicated E2E test users or token minting for CI (no shared personal passwords)

### This repo

- [ ] GitHub Actions workflow calling `run-android-tests.sh` / Maestro Cloud upload
- [ ] Document which tag set runs on PR vs nightly
- [ ] Store `MAESTRO_*` in GitHub Actions secrets

## Maestro Cloud upload (when ready)

```bash
# Example — exact flags depend on your Cloud project
maestro cloud \
  --app-file path/to/app.apk \
  --env MAESTRO_EMAIL=... \
  --env MAESTRO_PASSWORD=... \
  .maestro/
```

## Local commands that should match CI

```bash
# Fast PR gate (no login, no mock)
./scripts/run-android-tests.sh
# FLOW=.maestro/smoke/

# Auth suite (mock + Metro + credentials)
./scripts/run-login-test.sh
```

Keep these scripts working locally; CI should call the same entry points.
