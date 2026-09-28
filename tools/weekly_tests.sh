#!/usr/bin/env bash
# Run the `weekly`-tagged tests — the ones too slow for the pull-request gate —
# and refuse to pass having run none (#37).
#
# A scheduled job that passes while running nothing is the quietest false
# green there is: it looks healthy for as long as nobody reads it. So the
# verdict is read from the test runner's own event stream, and zero passed
# tests is a failure whatever the exit code says.
#
# Usage: tools/weekly_tests.sh
# Exit:  0  at least one weekly test ran and every one passed
#        1  a weekly test failed
#        3  no weekly test ran
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

events="$(mktemp "${TMPDIR:-/tmp}/weekly-tests.XXXXXX")"
trap 'rm -f "$events"' EXIT

flutter test --no-pub --tags weekly --reporter json > "$events"
status=$?

# One line per event; a visible test that ran to success is a testDone with
# "result":"success" and "hidden":false (setUpAll/tearDownAll are hidden).
# Key order is the reporter's business, so each field is matched on its own.
done_lines() { grep '"type":"testDone"' "$events" || true; }
passed="$(done_lines | grep '"result":"success"' | grep -c '"hidden":false' || true)"
failed="$(done_lines | grep -cE '"result":"(failure|error)"' || true)"

echo "weekly tests: $passed passed, $failed failed (flutter test exit $status)"
if [ "$passed" -eq 0 ] && [ "$failed" -eq 0 ]; then
  echo "weekly_tests: no weekly test ran — refusing to pass empty" >&2
  exit 3
fi
if [ "$failed" -ne 0 ] || [ "$status" -ne 0 ]; then
  exit 1
fi
exit 0
