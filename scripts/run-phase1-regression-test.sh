#!/usr/bin/env bash
# Phase 1 regression on Android (Qase 305, 301, 304) — one emulator session.
#
# Prerequisites: mock server + Metro running, app installed (yarn android).
#
# Usage:
#   SHUTDOWN_AFTER=0 ./scripts/run-phase1-regression-test.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export SHUTDOWN_AFTER="${SHUTDOWN_AFTER:-0}"

"$SCRIPT_DIR/run-tab-navigation-test.sh"
"$SCRIPT_DIR/run-view-profile-test.sh"
"$SCRIPT_DIR/run-open-settings-test.sh"

echo ""
echo "✅ Phase 1 regression (305, 301, 304) — all passed"
