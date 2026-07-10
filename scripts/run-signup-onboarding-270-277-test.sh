#!/usr/bin/env bash
# Sign-up onboarding with product tour + Slomo gate (Qase 269, 270, 277).
#
# Usage:
#   SHUTDOWN_AFTER=0 ./scripts/run-signup-onboarding-270-277-test.sh

set -euo pipefail
export MAESTRO_FLOW=".maestro/auth/signup-onboarding-to-home.yaml"
export MAESTRO_TEST_LABEL="signup onboarding + product tour + Slomo (269/270/277)"
# shellcheck source=lib/run-mock-test.sh
source "$(cd "$(dirname "$0")" && pwd)/lib/run-mock-test.sh"
