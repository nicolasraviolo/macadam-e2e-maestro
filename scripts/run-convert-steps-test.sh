#!/usr/bin/env bash
# Convert steps → wallet → streak (MACADAM-272/273/275).
#
# Usage:
#   ./scripts/run-convert-steps-test.sh
#
# May fail on emulator if health reports 0 steps (see flow header TODO).

set -euo pipefail
export MAESTRO_FLOW=".maestro/regression/convert-steps-wallet-streak.yaml"
export MAESTRO_TEST_LABEL="convert steps / wallet / streak test"
# shellcheck source=lib/run-mock-test.sh
source "$(cd "$(dirname "$0")" && pwd)/lib/run-mock-test.sh"
