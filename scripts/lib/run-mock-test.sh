#!/usr/bin/env bash
# Shared Android runner for flows that need mock server + Metro + login credentials.
#
# Required env:
#   MAESTRO_FLOW  — path under .maestro/, e.g. .maestro/regression/tab-navigation.yaml
# Optional env:
#   MAESTRO_TEST_LABEL — human label for logs (default: Maestro flow)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_ROOT="${MACADAM_APP_ROOT:-$HOME/macadam-app}"
MOCK_HEALTH_URL="${MOCK_HEALTH_URL:-http://localhost:4010/test/health}"
METRO_URL="${METRO_URL:-http://localhost:8081/status}"
AVD_NAME="${AVD_NAME:-Pixel_7}"
EMULATOR_GPU="${EMULATOR_GPU:-host}"
HEADLESS="${HEADLESS:-0}"
SHUTDOWN_AFTER="${SHUTDOWN_AFTER:-1}"
MAESTRO_FLOW="${MAESTRO_FLOW:?Set MAESTRO_FLOW to a .maestro/... path}"
MAESTRO_TEST_LABEL="${MAESTRO_TEST_LABEL:-$MAESTRO_FLOW}"

export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
export JAVA_HOME="${JAVA_HOME:-/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home}"
export PATH="$HOME/.maestro/bin:$JAVA_HOME/bin:$ANDROID_HOME/emulator:$ANDROID_HOME/platform-tools:$PATH"
export MAESTRO_CLI_NO_ANALYTICS="${MAESTRO_CLI_NO_ANALYTICS:-1}"
export MAESTRO_CLI_ANALYSIS_NOTIFICATION_DISABLED="${MAESTRO_CLI_ANALYSIS_NOTIFICATION_DISABLED:-1}"

ADB="$ANDROID_HOME/platform-tools/adb"
EMULATOR="$ANDROID_HOME/emulator/emulator"

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

if ! curl -sf "$MOCK_HEALTH_URL" >/dev/null 2>&1; then
  echo "❌ Mock server is not running on :4010"
  echo "   Start it: cd ~/macadam-app && yarn mock-server:dev"
  exit 1
fi
echo "✅ Mock server is up"

if ! curl -sf "$METRO_URL" >/dev/null 2>&1 && ! curl -sf "http://localhost:8081" >/dev/null 2>&1; then
  echo "❌ Metro is not running on :8081"
  echo "   Start it: cd ~/macadam-app && yarn start"
  exit 1
fi
echo "✅ Metro is up"

ENV_FILE="$APP_ROOT/.env.development"
if [ -f "$ENV_FILE" ]; then
  if ! grep -qE "^E2E_TESTING=['\"]?true['\"]?" "$ENV_FILE"; then
    echo "⚠️  E2E_TESTING=true is missing from $ENV_FILE"
    exit 1
  fi
  if ! grep -qE '^BASE_URL=http://localhost:4010' "$ENV_FILE"; then
    echo "⚠️  BASE_URL is not http://localhost:4010 in $ENV_FILE"
    exit 1
  fi
  echo "✅ E2E_TESTING=true and BASE_URL=localhost:4010 in .env.development"
fi

emulator_udid() {
  "$ADB" devices | awk '/^emulator-.*device/{print $1; exit}'
}

if [ -z "$(emulator_udid)" ]; then
  if [ ! -x "$EMULATOR" ]; then
    echo "❌ Emulator not found at $EMULATOR"
    exit 1
  fi
  echo "Starting emulator: $AVD_NAME"
  EMULATOR_ARGS=(-avd "$AVD_NAME" -gpu "$EMULATOR_GPU" -no-snapshot-load -memory 2048)
  if [ "$HEADLESS" = "1" ]; then
    EMULATOR_ARGS+=(-no-window)
  fi
  "$EMULATOR" "${EMULATOR_ARGS[@]}" >>/tmp/macadam-emulator.log 2>&1 &
  for _ in $(seq 1 50); do
    UDID="$(emulator_udid)"
    [ -n "$UDID" ] && break
    sleep 3
  done
fi

UDID="$(emulator_udid)"
if [ -z "$UDID" ]; then
  echo "❌ Emulator did not start. See /tmp/macadam-emulator.log"
  exit 1
fi

"$ADB" -s "$UDID" wait-for-device
until [ "$("$ADB" -s "$UDID" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; do
  sleep 2
done

# Cold boots can report boot_completed before adb is fully stable.
sleep 5

APP_ID="${APP_ID:-com.macadamapp.beta}"
if ! "$ADB" -s "$UDID" shell pm list packages "$APP_ID" 2>/dev/null | grep -q "$APP_ID"; then
  echo "❌ Macadam beta is not installed on $UDID ($APP_ID)"
  echo "   Install once: cd ~/macadam-app && yarn android"
  echo "   Then check:   adb shell pm list packages | grep macadam"
  exit 1
fi
echo "✅ App installed: $APP_ID"

"$ADB" -s "$UDID" reverse tcp:8081 tcp:8081 2>/dev/null || true
"$ADB" -s "$UDID" reverse tcp:4010 tcp:4010 2>/dev/null || true

# shellcheck source=lib/device-shutdown.sh
source "$REPO_ROOT/scripts/lib/device-shutdown.sh"
trap shutdown_android_device EXIT

echo "Running $MAESTRO_TEST_LABEL on $UDID ..."
cd "$REPO_ROOT"
run_maestro_and_exit maestro test --udid "$UDID" \
  -e APP_ID="${APP_ID:-com.macadamapp.beta}" \
  -e MAESTRO_EMAIL="${MAESTRO_EMAIL:-}" \
  -e MAESTRO_PASSWORD="${MAESTRO_PASSWORD:-Test123!}" \
  "$MAESTRO_FLOW"
