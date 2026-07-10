#!/usr/bin/env bash
# Settings screen regression (MACADAM-304).
#
# Usage:
#   ./scripts/run-open-settings-test.sh

set -euo pipefail
export MAESTRO_FLOW=".maestro/regression/open-settings.yaml"
export MAESTRO_TEST_LABEL="open settings test"
# shellcheck source=lib/run-mock-test.sh
source "$(cd "$(dirname "$0")" && pwd)/lib/run-mock-test.sh"
