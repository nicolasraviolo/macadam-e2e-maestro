#!/usr/bin/env bash
# Phase 2 regression on Android (Qase 298, 299, 300) — one emulator session.
#
# Usage:
#   SHUTDOWN_AFTER=0 ./scripts/run-phase2-regression-test.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export SHUTDOWN_AFTER="${SHUTDOWN_AFTER:-0}"

"$SCRIPT_DIR/run-deals-tab-exploration-test.sh"
"$SCRIPT_DIR/run-spend-coins-charity-test.sh"

echo ""
echo "✅ Phase 2 regression (298, 299, 300) — all passed"
