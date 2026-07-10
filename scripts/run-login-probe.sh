#!/usr/bin/env bash
# Boot emulator (if needed), ensure Metro is reachable, run login probe.
#
# Usage:
#   ./scripts/run-login-probe.sh
#
# Before first run: start Metro in macadam-app (separate terminal):
#   cd ~/macadam-app && yarn start

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
export PATH="$HOME/.maestro/bin:$ANDROID_HOME/emulator:$ANDROID_HOME/platform-tools:$PATH"

METRO_URL="${METRO_URL:-http://localhost:8081/status}"
MOCK_HEALTH_URL="${MOCK_HEALTH_URL:-http://localhost:4010/test/health}"
ADB="$ANDROID_HOME/platform-tools/adb"

if [ -f "$REPO_ROOT/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  source "$REPO_ROOT/.env"
  set +a
fi

if [ -z "${MAESTRO_EMAIL:-}" ]; then
  echo "❌ MAESTRO_EMAIL is not set — add it to .env"
  exit 1
fi

if ! curl -sf "$MOCK_HEALTH_URL" >/dev/null 2>&1; then
  echo "❌ Mock server is not running on :4010"
  echo "   Start it: cd ~/macadam-app && yarn mock-server:dev"
  exit 1
fi

if ! curl -sf "$METRO_URL" >/dev/null 2>&1 && ! curl -sf "http://localhost:8081" >/dev/null 2>&1; then
  echo "❌ Metro is not running on :8081"
  echo "   Start it: cd ~/macadam-app && yarn start"
  exit 1
fi

emulator_udid() {
  "$ADB" devices | awk '/^emulator-.*device/{print $1; exit}'
}

if [ -z "$(emulator_udid)" ]; then
  echo "Starting Pixel_7 emulator..."
  "$ANDROID_HOME/emulator/emulator" -avd Pixel_7 -gpu host -no-window -no-snapshot-load -memory 2048 >>/tmp/macadam-emulator.log 2>&1 &
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
until [ "$("$ADB" -s "$UDID" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; do sleep 2; done
"$ADB" -s "$UDID" reverse tcp:8081 tcp:8081 2>/dev/null || true
"$ADB" -s "$UDID" reverse tcp:4010 tcp:4010 2>/dev/null || true

echo "Running login probe on $UDID ..."
cd "$REPO_ROOT"
maestro test --udid "$UDID" \
  -e APP_ID="${APP_ID:-com.macadamapp.beta}" \
  -e MAESTRO_EMAIL="${MAESTRO_EMAIL}" \
  -e MAESTRO_PASSWORD="${MAESTRO_PASSWORD:-Test123!}" \
  .maestro/auth/login-password-probe.yaml
