#!/usr/bin/env bash
# Charity entry from Spend tab (MACADAM-300).

set -euo pipefail
export MAESTRO_FLOW=".maestro/regression/spend-coins-charity.yaml"
export MAESTRO_TEST_LABEL="spend coins charity (300)"
# shellcheck source=lib/run-mock-test.sh
source "$(cd "$(dirname "$0")" && pwd)/lib/run-mock-test.sh"
