#!/usr/bin/env bash
# Start Android emulator (if needed) and run Maestro tests.
#
# Usage (from anywhere):
#   ~/Desktop/macadam-e2e-maestro/scripts/run-android-tests.sh
#
# Headless emulator (no phone window):
#   HEADLESS=1 ~/Desktop/macadam-e2e-maestro/scripts/run-android-tests.sh
#
# Single flow:
#   FLOW=.maestro/smoke/app-launches-android.yaml ./scripts/run-android-tests.sh
#
# Shutdown emulator when tests finish (default: yes, pass or fail):
#   SHUTDOWN_AFTER=0 ~/Desktop/macadam-e2e-maestro/scripts/run-android-tests.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AVD_NAME="${AVD_NAME:-Pixel_7}"
EMULATOR_GPU="${EMULATOR_GPU:-host}"
HEADLESS="${HEADLESS:-0}"
FLOW="${FLOW:-.maestro/smoke/}"
SHUTDOWN_AFTER="${SHUTDOWN_AFTER:-1}"

export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
export JAVA_HOME="${JAVA_HOME:-/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home}"
export PATH="$HOME/.maestro/bin:$JAVA_HOME/bin:$ANDROID_HOME/emulator:$ANDROID_HOME/platform-tools:$PATH"
export MAESTRO_CLI_NO_ANALYTICS="${MAESTRO_CLI_NO_ANALYTICS:-1}"
export MAESTRO_CLI_ANALYSIS_NOTIFICATION_DISABLED="${MAESTRO_CLI_ANALYSIS_NOTIFICATION_DISABLED:-1}"

EMULATOR="$ANDROID_HOME/emulator/emulator"
ADB="$ANDROID_HOME/platform-tools/adb"

if ! command -v maestro >/dev/null 2>&1; then
  echo "Maestro not found. Install: curl -Ls \"https://get.maestro.mobile.dev\" | bash"
  exit 1
fi

if [ ! -x "$EMULATOR" ]; then
  echo "Emulator not found at $EMULATOR. Check ANDROID_HOME."
  exit 1
fi

emulator_is_ready() {
  EMULATOR_UDID="$("$ADB" devices 2>/dev/null | awk 'NR>1 && $2=="device" && $1 ~ /^emulator-/ { print $1; exit }')"
  [ -n "$EMULATOR_UDID" ]
}

wait_for_boot() {
  echo "Waiting for emulator to boot..."
  "$ADB" -s "$EMULATOR_UDID" wait-for-device
  until [ "$("$ADB" -s "$EMULATOR_UDID" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; do
    sleep 2
  done
  # Extra beat for home screen / adb shell stability
  sleep 3
  echo "Emulator ready: $EMULATOR_UDID"
}

if emulator_is_ready; then
  echo "Emulator already running ($EMULATOR_UDID) — skipping launch."
else
  echo "Starting emulator: $AVD_NAME (HEADLESS=$HEADLESS)"
  EMULATOR_ARGS=(-avd "$AVD_NAME" -gpu "$EMULATOR_GPU" -no-snapshot-load -memory 2048)
  if [ "$HEADLESS" = "1" ]; then
    EMULATOR_ARGS+=(-no-window)
  fi
  "$EMULATOR" "${EMULATOR_ARGS[@]}" >/tmp/macadam-emulator.log 2>&1 &
  # After launch, discover the new emulator id
  sleep 5
  for _ in $(seq 1 30); do
    EMULATOR_UDID="$("$ADB" devices 2>/dev/null | awk 'NR>1 && $2=="device" && $1 ~ /^emulator-/ { print $1; exit }')"
    [ -n "$EMULATOR_UDID" ] && break
    sleep 2
  done
  if [ -z "${EMULATOR_UDID:-}" ]; then
    echo "Emulator did not appear in adb. Log: /tmp/macadam-emulator.log"
    exit 1
  fi
  wait_for_boot
fi

export ANDROID_SERIAL="$EMULATOR_UDID"

APP_ID="${APP_ID:-com.macadamapp.beta}"
if ! "$ADB" -s "$EMULATOR_UDID" shell pm list packages --user 0 2>/dev/null \
  | grep -qF "package:${APP_ID}"; then
  echo "❌ App '$APP_ID' is not installed on this emulator."
  echo "   Build + install it once:"
  echo "     cd ${MACADAM_APP_ROOT:-$HOME/macadam-app} && yarn android"
  echo "   (make sure .env.development has E2E_TESTING=true and BASE_URL=http://localhost:4010)"
  exit 1
fi
echo "✅ App installed: $APP_ID"

# shellcheck source=lib/device-shutdown.sh
source "$REPO_ROOT/scripts/lib/device-shutdown.sh"
trap shutdown_android_device EXIT

cd "$REPO_ROOT"

maestro_common_args=(
  test --udid "$EMULATOR_UDID"
  -e APP_ID="${APP_ID:-com.macadamapp.beta}"
)

run_smoke_flows_sequentially() {
  local flow exit_code=0
  for flow in .maestro/smoke/app-launches-android.yaml .maestro/smoke/sign-in-screen-android.yaml; do
    echo ""
    echo "▶ Smoke flow: $flow"
    set +e
    maestro "${maestro_common_args[@]}" "$flow"
    exit_code=$?
    set -e
    if [ "$exit_code" != "0" ]; then
      exit "$exit_code"
    fi
  done
}

echo "Running Maestro on $EMULATOR_UDID: $FLOW"
case "$FLOW" in
  .maestro/smoke/|.maestro/smoke)
    run_smoke_flows_sequentially
    ;;
  *)
    run_maestro_and_exit maestro "${maestro_common_args[@]}" "$FLOW"
    ;;
esac
