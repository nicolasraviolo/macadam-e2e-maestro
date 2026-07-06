# Shared shutdown helpers — source from test runner scripts.
# Shuts down the emulator/simulator used for the run when the script exits
# (pass or fail). Set SHUTDOWN_AFTER=0 to leave devices running.

shutdown_android_device() {
  if [ "${SHUTDOWN_AFTER:-1}" = "0" ]; then
    return 0
  fi
  local udid="${EMULATOR_UDID:-${UDID:-}}"
  if [ -z "$udid" ] || [ -z "${ADB:-}" ]; then
    return 0
  fi
  echo ""
  echo "Shutting down Android emulator ($udid)…"
  "$ADB" -s "$udid" emu kill 2>/dev/null || true
}

shutdown_ios_device() {
  if [ "${SHUTDOWN_AFTER:-1}" = "0" ]; then
    return 0
  fi
  local udid="${UDID:-}"
  if [ -z "$udid" ]; then
    return 0
  fi
  echo ""
  echo "Shutting down iOS simulator ($udid)…"
  xcrun simctl shutdown "$udid" 2>/dev/null || true
}

run_maestro_and_exit() {
  # run_maestro_and_exit maestro test ...args
  set +e
  "$@"
  local exit_code=$?
  set -e
  exit "$exit_code"
}
