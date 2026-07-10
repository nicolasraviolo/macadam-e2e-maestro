#!/usr/bin/env bash
# Run Maestro flows on an iOS Simulator.
#
# Usage (from anywhere):
#   ~/Desktop/macadam-e2e-maestro/scripts/run-ios-tests.sh
#
# Choose a flow (default: smoke suite):
#   FLOW=.maestro/profile/edit-profile-ios.yaml ./scripts/run-ios-tests.sh
#   FLOW=.maestro/auth/login-password-ios.yaml  ./scripts/run-ios-tests.sh
#
# Choose a simulator (default: first available iPhone, else "iPhone 15"):
#   SIM_NAME="iPhone 15 Pro" ./scripts/run-ios-tests.sh
#
# iOS one-time setup (do these once, they need a build):
#   1) Use the Xcode version the app team builds with: Xcode 26.2.
#      This script auto-selects /Applications/Xcode-26.2.0.app if present
#      (via DEVELOPER_DIR), so you do NOT need `sudo xcode-select`.
#      You can override it: DEVELOPER_DIR=/path/to/Xcode.app/Contents/Developer
#   2) Build + install the app on the simulator (from macadam-app):
#        cd ~/macadam-app
#        ENVFILE=.env.development APP_VARIANT=beta \
#          npx expo run:ios --device "<sim name or udid>"
#      IMPORTANT: ENVFILE=.env.development is REQUIRED on iOS. react-native-config
#      bakes env values (BASE_URL, MIXPANEL_*, …) from the file named by $ENVFILE
#      (default ".env", which does NOT exist here). Without it, Config.* is empty
#      and the app red-screens at launch ("token is not a valid string" in
#      mixpanel.ts). The Android build gets this via the withReactNativeConfig
#      gradle plugin; iOS has no equivalent, so you must pass ENVFILE explicitly.
#
# Why Xcode 26.2 (learned the hard way):
#   - The Fyber/InMobi ad SDK (IASDKCore) is a prebuilt binary that needs the
#     Swift 6.2 runtime → only links with Xcode 26.x.
#   - React Native's bundled `fmt` breaks on Xcode 26.6's newer clang (consteval),
#     but compiles fine on Xcode 26.2's clang-1700.
#   - So Xcode 26.2 is the sweet spot. 16.4 fails to link Fyber; 26.6 fails on fmt.
#
# Notes:
#   - The iOS simulator reaches the mock server / Metro on localhost directly
#     (no adb reverse needed, unlike Android).
#   - Needs an iOS simulator runtime that the active Xcode supports (e.g. iOS
#     26.3.x for Xcode 26.2). Install via: xcodebuild -downloadPlatform iOS
#
# Shutdown simulator when this script finishes (default: no — leave open for debugging).
#   SHUTDOWN_AFTER=1 ./scripts/run-ios-tests.sh
#
# iOS driver retries (default: 2 retries = 3 attempts total). Set 0 to disable.
#   MAESTRO_IOS_MAX_RETRIES=0 ./scripts/run-ios-tests.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_ROOT="${MACADAM_APP_ROOT:-$HOME/macadam-app}"
APP_ID="${APP_ID:-com.macadam.app.beta}"
SIM_NAME="${SIM_NAME:-}"
FLOW="${FLOW:-.maestro/smoke/}"
MOCK_HEALTH_URL="${MOCK_HEALTH_URL:-http://localhost:4010/test/health}"
METRO_URL="${METRO_URL:-http://localhost:8081/status}"
SHUTDOWN_AFTER="${SHUTDOWN_AFTER:-0}"

export PATH="$HOME/.maestro/bin:$PATH"
export MAESTRO_CLI_NO_ANALYTICS="${MAESTRO_CLI_NO_ANALYTICS:-1}"
export MAESTRO_CLI_ANALYSIS_NOTIFICATION_DISABLED="${MAESTRO_CLI_ANALYSIS_NOTIFICATION_DISABLED:-1}"
export MAESTRO_DRIVER_STARTUP_TIMEOUT="${MAESTRO_DRIVER_STARTUP_TIMEOUT:-180000}"

if [ -f "$REPO_ROOT/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  source "$REPO_ROOT/.env"
  set +a
fi

if ! command -v maestro >/dev/null 2>&1; then
  echo "❌ Maestro not found. Install: curl -Ls \"https://get.maestro.mobile.dev\" | bash"
  exit 1
fi

# --- Prefer the app team's Xcode (26.2) without needing sudo xcode-select ---
# If DEVELOPER_DIR is already set (by the caller) we respect it. Otherwise we
# look for a known-good Xcode and export DEVELOPER_DIR so xcrun/simctl/Maestro
# all use it. Falls back to whatever `xcode-select` points at.
if [ -z "${DEVELOPER_DIR:-}" ]; then
  for _xc in \
    /Applications/Xcode-26.2.0.app \
    /Applications/Xcode-26.2.app; do
    if [ -d "$_xc/Contents/Developer" ]; then
      export DEVELOPER_DIR="$_xc/Contents/Developer"
      break
    fi
  done
fi

# --- Xcode must be selected (not Command Line Tools) ---
DEV_DIR="${DEVELOPER_DIR:-$(xcode-select -p 2>/dev/null || true)}"
if [ -z "$DEV_DIR" ] || ! command -v xcrun >/dev/null 2>&1 || ! xcrun simctl help >/dev/null 2>&1; then
  echo "❌ Xcode is not active (found: ${DEV_DIR:-none})."
  echo "   The simulator tools (simctl) are unavailable."
  echo
  if [ -d /Applications/Xcode.app ]; then
    echo "   Fix it once (needs your password):"
    echo "     sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
    echo "   Then accept the license if prompted:"
    echo "     sudo xcodebuild -license accept"
  else
    echo "   Install Xcode from the App Store first, then run the command above."
  fi
  exit 1
fi
echo "✅ Xcode active: $DEV_DIR"

# --- Mock server + Metro (auth/profile/signup only; smoke runs without them) ---
needs_mock_metro() {
  case "$FLOW" in
    *smoke*|*/smoke/*) return 1 ;;
  esac
  [ "${REQUIRE_MOCK_METRO:-1}" != "0" ]
}

if needs_mock_metro; then
  if ! curl -sf "$MOCK_HEALTH_URL" >/dev/null 2>&1; then
    echo "❌ Mock server is not running on :4010"
    echo "   Start it: cd $APP_ROOT && yarn mock-server:dev"
    exit 1
  fi
  echo "✅ Mock server is up"

  if ! curl -sf "$METRO_URL" >/dev/null 2>&1 && ! curl -sf "http://localhost:8081" >/dev/null 2>&1; then
    echo "❌ Metro is not running on :8081"
    echo "   Start it: cd $APP_ROOT && yarn start"
    exit 1
  fi
  echo "✅ Metro is up"
else
  echo "ℹ️  Smoke flow — skipping mock server / Metro checks"
fi

# --- Pick / boot a simulator ---
# grep returns 1 when nothing is booted; with pipefail that must not kill the script.
booted_udid() {
  xcrun simctl list devices booted 2>/dev/null \
    | grep -Eo '\(([0-9A-F-]{36})\)' 2>/dev/null | head -1 | tr -d '()' || true
}

# Offline check: find an available simulator that already has the app bundle installed.
sim_udid_with_app() {
  local bundle_id="$1"
  local devices_root="$HOME/Library/Developer/CoreSimulator/Devices"
  local udid app_path
  for udid in $(xcrun simctl list devices available 2>/dev/null \
    | grep -Eo '\([0-9A-F-]{36}\)' 2>/dev/null | tr -d '()' || true); do
    app_path="$(find "$devices_root/$udid/data/Containers/Bundle/Application" \
      -maxdepth 2 -name "${bundle_id}*.app" -print -quit 2>/dev/null || true)"
    if [ -n "$app_path" ]; then
      echo "$udid"
      return 0
    fi
  done
  return 1
}

sim_name_for_udid() {
  local target_udid="$1"
  xcrun simctl list devices available 2>/dev/null \
    | grep -F "($target_udid)" | sed -E 's/^[[:space:]]+//; s/ \([^)]+\).*$//' | head -1
}

sim_has_app() {
  local target_udid="$1"
  find "$HOME/Library/Developer/CoreSimulator/Devices/$target_udid/data/Containers/Bundle/Application" \
    -maxdepth 2 -name "${APP_ID}*.app" -print -quit 2>/dev/null | grep -q .
}

UDID="$(booted_udid)"

# A booted simulator without the app blocks auto-selection — shut it down and pick another.
if [ -n "$UDID" ] && [ -z "$SIM_NAME" ] && ! sim_has_app "$UDID"; then
  echo "Booted simulator lacks $APP_ID — selecting a device with the app installed…"
  xcrun simctl shutdown "$UDID" 2>/dev/null || true
  UDID=""
fi

if [ -z "$UDID" ]; then
  if [ -z "$SIM_NAME" ]; then
    UDID="$(sim_udid_with_app "$APP_ID" || true)"
    if [ -n "$UDID" ]; then
      SIM_NAME="$(sim_name_for_udid "$UDID")"
      echo "Using simulator with app installed: $SIM_NAME"
    fi
  fi
  if [ -z "$UDID" ]; then
    # Fall back to name-based selection (E2E device first, then any iPhone).
    if [ -z "$SIM_NAME" ]; then
      SIM_NAME="$(xcrun simctl list devices available 2>/dev/null \
        | grep -E 'iPhone.*E2E' | grep -Eo 'iPhone [^()]+' | tail -1 | sed 's/ *$//' || true)"
    fi
    if [ -z "$SIM_NAME" ]; then
      SIM_NAME="$(xcrun simctl list devices available 2>/dev/null \
        | grep -Eo 'iPhone [0-9][0-9A-Za-z ]*' 2>/dev/null | head -1 | sed 's/ *$//' || true)"
    fi
    if [ -z "$SIM_NAME" ]; then
      echo "❌ No iPhone simulator available."
      echo "   Open Xcode → Settings → Platforms and install an iOS runtime,"
      echo "   or create a simulator in Xcode → Window → Devices and Simulators."
      exit 1
    fi
    echo "Booting simulator: $SIM_NAME"
    UDID="$(xcrun simctl list devices available 2>/dev/null \
      | grep -F "$SIM_NAME (" | grep -Eo '\(([0-9A-F-]{36})\)' 2>/dev/null | head -1 | tr -d '()' || true)"
    if [ -z "$UDID" ]; then
      echo "❌ Simulator named '$SIM_NAME' not found. Set SIM_NAME to an installed device."
      exit 1
    fi
  fi
  xcrun simctl boot "$UDID" 2>/dev/null || true
  open -a Simulator 2>/dev/null || true
  # Wait until booted
  for _ in $(seq 1 30); do
    STATE="$(xcrun simctl list devices 2>/dev/null | grep -F "$UDID" | grep -o 'Booted' || true)"
    [ "$STATE" = "Booted" ] && break
    sleep 2
  done
fi

if [ -z "$UDID" ]; then
  echo "❌ No booted simulator."
  exit 1
fi
echo "✅ Simulator booted: $UDID"

refresh_ios_maestro_driver() {
  echo "Refreshing iOS Maestro driver…"
  xcrun simctl terminate "$UDID" com.macadam.app.beta 2>/dev/null || true
  xcrun simctl terminate "$UDID" com.mobile.dev.maestro-driver-iosUITests.xcrun 2>/dev/null || true
  pkill -f "maestro-driver-iosUITests-Runner" 2>/dev/null || true
  pkill -f "maestro_xctestrunner_xcodebuild_output" 2>/dev/null || true
  sleep 5
}

# Stale Maestro XCTest runners cause kAXErrorInvalidUIElement / SafariViewService popups.
# REFRESH_IOS_DRIVER=1 — use between suite phases (smoke → login → profile).
if [ "${REFRESH_IOS_DRIVER:-0}" = "1" ]; then
  refresh_ios_maestro_driver
else
  xcrun simctl terminate "$UDID" com.mobile.dev.maestro-driver-iosUITests.xcrun 2>/dev/null || true
  pkill -f "maestro-driver-iosUITests-Runner" 2>/dev/null || true
fi

# --- Force a deterministic locale (English) so text assertions are stable ---
# The flows assume English UI (same as the Android emulator). The iOS simulator
# can default to the Mac's language (e.g. Spanish), which breaks text matching.
# Maestro's `clearState` does NOT reset device language, so setting it here (on
# the device's global prefs) persists across flow runs.
# Set FORCE_EN=0 to skip this.
if [ "${FORCE_EN:-1}" = "1" ]; then
  GLOBAL_PLIST="$HOME/Library/Developer/CoreSimulator/Devices/$UDID/data/Library/Preferences/.GlobalPreferences.plist"
  CUR_LANG="$(xcrun simctl spawn "$UDID" defaults read -g AppleLanguages 2>/dev/null | tr -d ' \n' || true)"
  if [ -n "$GLOBAL_PLIST" ] && ! printf '%s' "$CUR_LANG" | grep -qi '"en'; then
    echo "Setting simulator language to English (was: ${CUR_LANG:-unknown})…"
    xcrun simctl shutdown "$UDID" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Delete :AppleLanguages" "$GLOBAL_PLIST" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :AppleLanguages array" "$GLOBAL_PLIST" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :AppleLanguages:0 string en-US" "$GLOBAL_PLIST" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Delete :AppleLocale" "$GLOBAL_PLIST" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :AppleLocale string en_US" "$GLOBAL_PLIST" 2>/dev/null || true
    xcrun simctl boot "$UDID" 2>/dev/null || true
    open -a Simulator 2>/dev/null || true
    sleep 6
  fi
  echo "✅ Simulator language: $(xcrun simctl spawn "$UDID" defaults read -g AppleLanguages 2>/dev/null | tr -d ' \n')"
fi

# --- App installed? ---
if ! xcrun simctl get_app_container "$UDID" "$APP_ID" >/dev/null 2>&1; then
  echo "❌ App '$APP_ID' is not installed on this simulator."
  echo "   Build + install it once:"
  echo "     cd $APP_ROOT && yarn ios"
  echo "   (make sure macadam-app/.env.development has E2E_TESTING=true and"
  echo "    BASE_URL=http://localhost:4010, then rebuild)"
  exit 1
fi
echo "✅ App installed: $APP_ID"

# shellcheck source=lib/device-shutdown.sh
source "$REPO_ROOT/scripts/lib/device-shutdown.sh"
trap shutdown_ios_device EXIT

echo "Running Maestro on iOS ($UDID): $FLOW"
cd "$REPO_ROOT"

maestro_common_args=(
  test --udid "$UDID"
  -e APP_ID="$APP_ID"
  -e MAESTRO_EMAIL="${MAESTRO_EMAIL:-}"
  -e MAESTRO_PASSWORD="${MAESTRO_PASSWORD:-Test123!}"
)

# Run one flow with driver refresh + optional retries (infra flake on iOS 26).
run_maestro_ios_with_retry() {
  local flow="$1"
  local max_retries="${MAESTRO_IOS_MAX_RETRIES:-2}"
  local total_attempts=$((max_retries + 1))
  local attempt exit_code=1

  for attempt in $(seq 1 "$total_attempts"); do
    if [ "$attempt" -gt 1 ]; then
      echo ""
      echo "↻ iOS retry $((attempt - 1))/$max_retries for $flow (refreshing driver)…"
    fi
    refresh_ios_maestro_driver
    echo ""
    echo "▶ $flow (attempt $attempt/$total_attempts)"
    exit_code=0
    run_maestro_cmd maestro "${maestro_common_args[@]}" "$flow" || exit_code=$?
    if [ "$exit_code" = "0" ]; then
      return 0
    fi
    if [ "$attempt" -lt "$total_attempts" ]; then
      echo "⚠️  Attempt $attempt failed (exit $exit_code)"
    fi
  done
  echo "❌ All $total_attempts attempts failed for $flow"
  return "$exit_code"
}

# Smoke: run each flow in its own Maestro session. Running both in one session
# (clearState twice back-to-back) often triggers iOS driver flake (kAXErrorInvalidUIElement).
run_smoke_flows_sequentially() {
  local flow
  for flow in .maestro/smoke/app-launches-ios.yaml .maestro/smoke/sign-in-screen-ios.yaml; do
    run_maestro_ios_with_retry "$flow" || exit $?
  done
}

case "$FLOW" in
  .maestro/smoke/|.maestro/smoke)
    run_smoke_flows_sequentially
    ;;
  *)
    run_maestro_ios_with_retry "$FLOW"
    exit $?
    ;;
esac
