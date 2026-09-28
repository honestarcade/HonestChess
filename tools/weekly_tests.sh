#!/usr/bin/env bash
# The `weekly`-tagged tests — too slow for the pull-request gate — run by
# .github/workflows/weekly.yml (#37). tools/counted_tests.sh refuses a run in
# which no test ran.
set -euo pipefail
exec "$(dirname "$0")/counted_tests.sh" weekly --no-pub --tags weekly
