#!/usr/bin/env bash
# View profile regression (MACADAM-301).
#
# Usage:
#   ./scripts/run-view-profile-test.sh

set -euo pipefail
export MAESTRO_FLOW=".maestro/regression/view-profile.yaml"
export MAESTRO_TEST_LABEL="view profile test"
# shellcheck source=lib/run-mock-test.sh
source "$(cd "$(dirname "$0")" && pwd)/lib/run-mock-test.sh"
