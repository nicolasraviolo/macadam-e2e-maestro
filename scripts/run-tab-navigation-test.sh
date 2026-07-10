#!/usr/bin/env bash
# Tab navigation regression (MACADAM-305).
#
# Usage:
#   ./scripts/run-tab-navigation-test.sh

set -euo pipefail
export MAESTRO_FLOW=".maestro/regression/tab-navigation.yaml"
export MAESTRO_TEST_LABEL="tab navigation test"
# shellcheck source=lib/run-mock-test.sh
source "$(cd "$(dirname "$0")" && pwd)/lib/run-mock-test.sh"
