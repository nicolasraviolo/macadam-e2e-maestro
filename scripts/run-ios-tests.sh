#!/usr/bin/env bash
# Run Maestro flows on an iOS Simulator.
#
# Usage (from anywhere):
#   ~/Desktop/macadam-e2e-maestro/scripts/run-ios-tests.sh
#
# Choose a flow (default: smoke suite):
#   FLOW=.maestro/profile/edit-profile.yaml ./scripts/run-ios-tests.sh
#   FLOW=.maestro/auth/login-password.yaml  ./scripts/run-ios-tests.sh
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
# Shutdown simulator when tests finish (default: yes, pass or fail):
#   SHUTDOWN_AFTER=0 ./scripts/run-ios-tests.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_ROOT="${MACADAM_APP_ROOT:-$HOME/macadam-app}"
APP_ID="${APP_ID:-com.macadam.app.beta}"
SIM_NAME="${SIM_NAME:-}"
FLOW="${FLOW:-.maestro/smoke/}"
MOCK_HEALTH_URL="${MOCK_HEALTH_URL:-http://localhost:4010/test/health}"
METRO_URL="${METRO_URL:-http://localhost:8081/status}"
SHUTDOWN_AFTER="${SHUTDOWN_AFTER:-1}"

export PATH="$HOME/.maestro/bin:$PATH"
export MAESTRO_CLI_NO_ANALYTICS="${MAESTRO_CLI_NO_ANALYTICS:-1}"
export MAESTRO_CLI_ANALYSIS_NOTIFICATION_DISABLED="${MAESTRO_CLI_ANALYSIS_NOTIFICATION_DISABLED:-1}"

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
booted_udid() {
  xcrun simctl list devices booted 2>/dev/null \
    | grep -Eo '\(([0-9A-F-]{36})\)' | head -1 | tr -d '()'
}

UDID="$(booted_udid)"

if [ -z "$UDID" ]; then
  # Choose a target simulator by name (or first available iPhone)
  if [ -z "$SIM_NAME" ]; then
    SIM_NAME="$(xcrun simctl list devices available 2>/dev/null \
      | grep -Eo 'iPhone [0-9][0-9A-Za-z ]*' | head -1 | sed 's/ *$//')"
  fi
  if [ -z "$SIM_NAME" ]; then
    echo "❌ No iPhone simulator available."
    echo "   Open Xcode → Settings → Platforms and install an iOS runtime,"
    echo "   or create a simulator in Xcode → Window → Devices and Simulators."
    exit 1
  fi
  echo "Booting simulator: $SIM_NAME"
  # Find the UDID for that device name
  UDID="$(xcrun simctl list devices available 2>/dev/null \
    | grep -F "$SIM_NAME (" | grep -Eo '\(([0-9A-F-]{36})\)' | head -1 | tr -d '()')"
  if [ -z "$UDID" ]; then
    echo "❌ Simulator named '$SIM_NAME' not found. Set SIM_NAME to an installed device."
    exit 1
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
run_maestro_and_exit maestro test --udid "$UDID" \
  -e APP_ID="$APP_ID" \
  -e MAESTRO_EMAIL="${MAESTRO_EMAIL:-}" \
  -e MAESTRO_PASSWORD="${MAESTRO_PASSWORD:-Test123!}" \
  "$FLOW"
