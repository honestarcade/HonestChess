#!/usr/bin/env bash
# The device-level tests in integration_test/, on whatever Android device or
# emulator is attached — run by .github/workflows/device.yml (#38).
# tools/counted_tests.sh refuses a run in which no test ran.
set -euo pipefail
exec "$(dirname "$0")/counted_tests.sh" device --no-pub integration_test
