#!/usr/bin/env bash
# Spend tab / offers wall regression (MACADAM-298, MACADAM-299).

set -euo pipefail
export MAESTRO_FLOW=".maestro/regression/deals-tab-exploration.yaml"
export MAESTRO_TEST_LABEL="deals tab exploration (298/299)"
# shellcheck source=lib/run-mock-test.sh
source "$(cd "$(dirname "$0")" && pwd)/lib/run-mock-test.sh"
