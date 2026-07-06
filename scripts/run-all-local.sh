#!/usr/bin/env bash
# Run the local E2E suite on Android and iOS (in parallel where safe).
#
# Always runs smoke on each selected platform.
# If mock server + Metro are up and credentials are in .env, also runs login + profile.
#
# Usage:
#   ./scripts/run-all-local.sh
#
# Platform selection (default: both in parallel):
#   PLATFORM=android ./scripts/run-all-local.sh
#   PLATFORM=ios     ./scripts/run-all-local.sh
#   PLATFORM=both    ./scripts/run-all-local.sh
#
# Optional — also run fresh sign-up (~3–5 min extra per platform):
#   INCLUDE_SIGNUP=1 ./scripts/run-all-local.sh
#
# Child scripts shut down emulator/simulator when each phase finishes (pass or
# fail). To keep devices open while debugging: SHUTDOWN_AFTER=0 ./scripts/run-all-local.sh
#
# For auth tests, start these first (two separate terminals):
#   cd ~/macadam-app && yarn mock-server:dev
#   cd ~/macadam-app && yarn start

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

MOCK_HEALTH_URL="${MOCK_HEALTH_URL:-http://localhost:4010/test/health}"
METRO_URL="${METRO_URL:-http://localhost:8081/status}"
INCLUDE_SIGNUP="${INCLUDE_SIGNUP:-0}"
PLATFORM="${PLATFORM:-both}"
export SHUTDOWN_AFTER="${SHUTDOWN_AFTER:-1}"

PASSED=()
FAILED=()
SKIPPED=()
LOG_DIR=""

if [ -f "$REPO_ROOT/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  source "$REPO_ROOT/.env"
  set +a
fi

setup_logs() {
  LOG_DIR="$(mktemp -d /tmp/macadam-e2e-all.XXXXXX)"
}

cleanup_logs() {
  if [ -n "$LOG_DIR" ] && [ -d "$LOG_DIR" ]; then
    rm -rf "$LOG_DIR"
  fi
}

print_header() {
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  $1"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
}

skip_step() {
  local name="$1"
  local reason="$2"
  SKIPPED+=("$name — $reason")
  echo "⏭️  Skipping $name: $reason"
}

mock_server_up() {
  curl -sf "$MOCK_HEALTH_URL" >/dev/null 2>&1
}

metro_up() {
  curl -sf "$METRO_URL" >/dev/null 2>&1 || curl -sf "http://localhost:8081" >/dev/null 2>&1
}

credentials_ready() {
  [ -n "${MAESTRO_EMAIL:-}" ] && [ -n "${MAESTRO_PASSWORD:-}" ]
}

ios_available() {
  if [ -n "${DEVELOPER_DIR:-}" ]; then
    return 0
  fi
  for _xc in \
    /Applications/Xcode-26.2.0.app \
    /Applications/Xcode-26.2.app \
    /Applications/Xcode.app; do
    if [ -d "$_xc/Contents/Developer" ]; then
      return 0
    fi
  done
  command -v xcrun >/dev/null 2>&1 && xcrun simctl help >/dev/null 2>&1
}

# Run one step in the background; writes a log file and exit code marker.
run_parallel_step() {
  local slug="$1"
  shift
  local log_file="$LOG_DIR/$slug.log"
  local status_file="$LOG_DIR/$slug.status"
  (
    set +e
    "$@" >"$log_file" 2>&1
    echo $? >"$status_file"
  ) &
  echo $! >"$LOG_DIR/$slug.pid"
}

wait_parallel_step() {
  local slug="$1"
  local display_name="$2"
  wait "$(cat "$LOG_DIR/$slug.pid")" 2>/dev/null || true
  local exit_code
  exit_code="$(cat "$LOG_DIR/$slug.status" 2>/dev/null || echo 1)"
  print_header "$display_name"
  cat "$LOG_DIR/$slug.log"
  echo ""
  if [ "$exit_code" = "0" ]; then
    PASSED+=("$display_name")
    echo "✅ $display_name passed"
    return 0
  fi
  FAILED+=("$display_name")
  echo "❌ $display_name failed"
  return 1
}

run_sequential_step() {
  local name="$1"
  shift
  print_header "$name"
  if "$@"; then
    PASSED+=("$name")
    echo ""
    echo "✅ $name passed"
    return 0
  fi
  FAILED+=("$name")
  echo ""
  echo "❌ $name failed"
  return 1
}

print_summary() {
  print_header "Summary"
  if [ "${#PASSED[@]}" -gt 0 ]; then
    echo "Passed (${#PASSED[@]}):"
    for item in "${PASSED[@]}"; do
      echo "  ✅ $item"
    done
    echo ""
  fi
  if [ "${#SKIPPED[@]}" -gt 0 ]; then
    echo "Skipped (${#SKIPPED[@]}):"
    for item in "${SKIPPED[@]}"; do
      echo "  ⏭️  $item"
    done
    echo ""
  fi
  if [ "${#FAILED[@]}" -gt 0 ]; then
    echo "Failed (${#FAILED[@]}):"
    for item in "${FAILED[@]}"; do
      echo "  ❌ $item"
    done
    echo ""
    echo "Suite finished with failures."
    exit 1
  fi
  echo "All ran tests passed."
}

want_android() {
  [ "$PLATFORM" = "android" ] || [ "$PLATFORM" = "both" ]
}

want_ios() {
  [ "$PLATFORM" = "ios" ] || [ "$PLATFORM" = "both" ]
}

trap cleanup_logs EXIT
setup_logs

echo "Macadam E2E — local suite (Android + iOS)"
echo "Repo: $REPO_ROOT"
echo "Platform: $PLATFORM"

# ── 1. Smoke (parallel per platform) ─────────────────────────────────────────
print_header "Phase 1 — Smoke (parallel)"
smoke_parallel=0

if want_android; then
  echo "▶ Queuing Android smoke..."
  run_parallel_step "smoke-android" "$SCRIPT_DIR/run-android-tests.sh"
  smoke_parallel=1
fi

if want_ios; then
  if ios_available; then
    echo "▶ Queuing iOS smoke..."
    run_parallel_step "smoke-ios" \
      env FLOW=.maestro/smoke/ "$SCRIPT_DIR/run-ios-tests.sh"
    smoke_parallel=1
  else
    skip_step "iOS smoke" "Xcode / iOS simulator not available"
  fi
fi

smoke_failed=0
if want_android; then
  wait_parallel_step "smoke-android" "Smoke (Android)" || smoke_failed=1
fi
if want_ios && ios_available; then
  wait_parallel_step "smoke-ios" "Smoke (iOS)" || smoke_failed=1
fi

if [ "$smoke_parallel" = "0" ]; then
  echo "❌ No platform selected. Use PLATFORM=android|ios|both"
  exit 1
fi

if [ "$smoke_failed" = "1" ]; then
  print_summary
  exit 1
fi

# ── 2. Auth prerequisites ────────────────────────────────────────────────────
if ! mock_server_up; then
  skip_step "Login (Android)" "mock server not running on :4010"
  skip_step "Login (iOS)" "mock server not running on :4010"
  skip_step "Profile edit (Android)" "mock server not running on :4010"
  skip_step "Profile edit (iOS)" "mock server not running on :4010"
  if [ "$INCLUDE_SIGNUP" = "1" ]; then
    skip_step "Fresh sign-up (Android)" "mock server not running on :4010"
    skip_step "Fresh sign-up (iOS)" "mock server not running on :4010"
  fi
  echo ""
  echo "💡 To run auth tests next time, start in two terminals:"
  echo "   cd ~/macadam-app && yarn mock-server:dev"
  echo "   cd ~/macadam-app && yarn start"
  print_summary
  exit 0
fi

if ! metro_up; then
  skip_step "Login (Android)" "Metro not running on :8081"
  skip_step "Login (iOS)" "Metro not running on :8081"
  skip_step "Profile edit (Android)" "Metro not running on :8081"
  skip_step "Profile edit (iOS)" "Metro not running on :8081"
  if [ "$INCLUDE_SIGNUP" = "1" ]; then
    skip_step "Fresh sign-up (Android)" "Metro not running on :8081"
    skip_step "Fresh sign-up (iOS)" "Metro not running on :8081"
  fi
  echo ""
  echo "💡 Mock server is up, but Metro is not. Start it:"
  echo "   cd ~/macadam-app && yarn start"
  print_summary
  exit 0
fi

echo ""
echo "✅ Mock server is up (:4010)"
echo "✅ Metro is up (:8081)"

if ! credentials_ready; then
  skip_step "Login (Android)" "MAESTRO_EMAIL / MAESTRO_PASSWORD not set in .env"
  skip_step "Login (iOS)" "MAESTRO_EMAIL / MAESTRO_PASSWORD not set in .env"
  skip_step "Profile edit (Android)" "MAESTRO_EMAIL / MAESTRO_PASSWORD not set in .env"
  skip_step "Profile edit (iOS)" "MAESTRO_EMAIL / MAESTRO_PASSWORD not set in .env"
  if [ "$INCLUDE_SIGNUP" = "1" ]; then
    set +e
    if want_android; then
      run_sequential_step "Fresh sign-up (Android)" "$SCRIPT_DIR/run-signup-test.sh" || true
    fi
    if want_ios && ios_available; then
      run_sequential_step "Fresh sign-up (iOS)" \
        env FLOW=.maestro/auth/signup-fresh-account.yaml "$SCRIPT_DIR/run-ios-tests.sh" || true
    fi
    set -e
  else
    skip_step "Fresh sign-up" "set INCLUDE_SIGNUP=1 to run without MAESTRO_EMAIL"
  fi
  print_summary
  exit 0
fi

# ── 3. Login (parallel — different devices, same mock user is OK) ─────────────
print_header "Phase 2 — Login (parallel)"

if want_android; then
  run_parallel_step "login-android" "$SCRIPT_DIR/run-login-test.sh"
fi
if want_ios && ios_available; then
  run_parallel_step "login-ios" \
    env FLOW=.maestro/auth/login-password.yaml "$SCRIPT_DIR/run-ios-tests.sh"
fi

if want_android; then
  wait_parallel_step "login-android" "Login (Android)" || true
fi
if want_ios && ios_available; then
  wait_parallel_step "login-ios" "Login (iOS)" || true
fi

# ── 4. Profile edit (sequential — same mock user; parallel saves can clash) ──
print_header "Phase 3 — Profile edit (sequential — shared test account)"
set +e
if want_android; then
  run_sequential_step "Profile edit (Android)" "$SCRIPT_DIR/run-profile-edit-test.sh" || true
fi
if want_ios && ios_available; then
  run_sequential_step "Profile edit (iOS)" \
    env FLOW=.maestro/profile/edit-profile.yaml "$SCRIPT_DIR/run-ios-tests.sh" || true
fi
set -e

# ── 5. Sign-up (parallel — each run creates its own random account) ───────────
if [ "$INCLUDE_SIGNUP" = "1" ]; then
  print_header "Phase 4 — Fresh sign-up (parallel)"
  if want_android; then
    run_parallel_step "signup-android" "$SCRIPT_DIR/run-signup-test.sh"
  fi
  if want_ios && ios_available; then
    run_parallel_step "signup-ios" \
      env FLOW=.maestro/auth/signup-fresh-account.yaml "$SCRIPT_DIR/run-ios-tests.sh"
  fi
  if want_android; then
    wait_parallel_step "signup-android" "Fresh sign-up (Android)" || true
  fi
  if want_ios && ios_available; then
    wait_parallel_step "signup-ios" "Fresh sign-up (iOS)" || true
  fi
fi

print_summary
