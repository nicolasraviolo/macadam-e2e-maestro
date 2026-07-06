#!/usr/bin/env bash
# Run password login E2E test (mock server + Metro + emulator).
#
# Usage:
#   ./scripts/run-login-test.sh
#
# Terminals you need open first:
#   1. cd ~/macadam-app && yarn mock-server:dev
#   2. cd ~/macadam-app && yarn start
#
# One-time: add E2E_TESTING=true to ~/macadam-app/.env.development and rebuild (yarn android).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_ROOT="${MACADAM_APP_ROOT:-$HOME/macadam-app}"
MOCK_HEALTH_URL="${MOCK_HEALTH_URL:-http://localhost:4010/test/health}"
METRO_URL="${METRO_URL:-http://localhost:8081/status}"
AVD_NAME="${AVD_NAME:-Pixel_7}"
EMULATOR_GPU="${EMULATOR_GPU:-host}"
HEADLESS="${HEADLESS:-0}"
SHUTDOWN_AFTER="${SHUTDOWN_AFTER:-1}"

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
    echo "   Add this line, then rebuild the app: cd ~/macadam-app && yarn android"
    echo "   Without it, magic link stays on and this test will fail."
    exit 1
  fi
  if ! grep -qE '^BASE_URL=http://localhost:4010' "$ENV_FILE"; then
    echo "⚠️  BASE_URL is not http://localhost:4010 in $ENV_FILE"
    echo "   The app will ignore the mock server. Set BASE_URL=http://localhost:4010 and rebuild."
    exit 1
  fi
  echo "✅ E2E_TESTING=true and BASE_URL=localhost:4010 in .env.development"
else
  echo "⚠️  Could not find $ENV_FILE — ensure the app is built for E2E"
fi

if [ -z "${MAESTRO_EMAIL:-}" ]; then
  echo "❌ MAESTRO_EMAIL is not set"
  echo "   Add MAESTRO_EMAIL to .env"
  exit 1
fi

if [ -z "${MAESTRO_PASSWORD:-}" ]; then
  echo "❌ MAESTRO_PASSWORD is not set"
  echo "   Copy .env.example to .env and fill MAESTRO_PASSWORD, or run:"
  echo "   MAESTRO_PASSWORD='your-password' ./scripts/run-login-test.sh"
  exit 1
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

"$ADB" -s "$UDID" reverse tcp:8081 tcp:8081 2>/dev/null || true
"$ADB" -s "$UDID" reverse tcp:4010 tcp:4010 2>/dev/null || true

# shellcheck source=lib/device-shutdown.sh
source "$REPO_ROOT/scripts/lib/device-shutdown.sh"
trap shutdown_android_device EXIT

echo "Running login test on $UDID ..."
cd "$REPO_ROOT"
run_maestro_and_exit maestro test --udid "$UDID" \
  -e APP_ID="${APP_ID:-com.macadamapp.beta}" \
  -e MAESTRO_EMAIL="${MAESTRO_EMAIL}" \
  -e MAESTRO_PASSWORD="$MAESTRO_PASSWORD" \
  .maestro/auth/login-password.yaml
