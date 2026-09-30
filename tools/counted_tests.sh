#!/usr/bin/env bash
# Run `flutter test` with the given arguments and refuse to pass having run no
# test (#37, #38).
#
# A scheduled job that passes while running nothing is the quietest false
# green there is: it looks healthy for as long as nobody reads it. So the
# verdict is read from the test runner's own event stream, and zero passed
# tests is a failure whatever the exit code says. tools/weekly_tests.sh and
# tools/device_tests.sh are the two callers.
#
# Usage: tools/counted_tests.sh <label> <flutter test arguments...>
# Exit:  0  at least one test ran and every one passed
#        1  a test failed
#        2  bad usage
#        3  no test ran
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

[ "$#" -ge 1 ] || { echo "counted_tests: usage: counted_tests.sh <label> [args...]" >&2; exit 2; }
label="$1"
shift

events="$(mktemp "${TMPDIR:-/tmp}/counted-tests.XXXXXX")"
trap 'rm -f "$events"' EXIT

flutter test "$@" --reporter json > "$events"
status=$?

# One line per event. A visible test that ran to success is a testDone with
# "result":"success" and "hidden":false (setUpAll/tearDownAll are hidden).
# Key order is the reporter's business, so each field is matched on its own.
done_lines() { grep '"type":"testDone"' "$events" || true; }
passed="$(done_lines | grep '"result":"success"' | grep -c '"hidden":false' || true)"
failed="$(done_lines | grep -cE '"result":"(failure|error)"' || true)"

counts="$label tests: $passed passed, $failed failed (flutter test exit $status)"
echo "$counts"
# The job summary is where a scheduled run is read, so the counts and any
# refusal go there too, not only into the step log (#45).
summarise() {
  [ -n "${GITHUB_STEP_SUMMARY:-}" ] && printf '%s\n\n' "$@" >> "$GITHUB_STEP_SUMMARY"
  return 0
}
# A red run names each failed test and its reason, in the log and the summary;
# the event stream that holds them is deleted on exit (#127). If the listing
# itself fails, the verdict below still stands.
explain() {
  python3 tools/failed_tests.py "$events" "${GITHUB_STEP_SUMMARY:-}" \
    || echo "$label: could not list the failed tests" >&2
}
if [ "$passed" -eq 0 ] && [ "$failed" -eq 0 ]; then
  echo "$label: no test ran — refusing to pass empty" >&2
  summarise "**$counts**" "$label: no test ran — refusing to pass empty"
  explain
  exit 3
fi
summarise "**$counts**"
if [ "$failed" -ne 0 ] || [ "$status" -ne 0 ]; then
  explain
  exit 1
fi
exit 0
