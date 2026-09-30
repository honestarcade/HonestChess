#!/usr/bin/env python3
"""Name every failed test in a `flutter test --reporter json` event stream,
and say why it failed (#127).

tools/counted_tests.sh calls this on a red or empty run. Without it, a failed
scheduled run shows only its counts: the stream that holds the names and
reasons is a temp file, deleted on exit.

Usage: failed_tests.py <events file> [summary file]

The log (stdout) gets each failed test's name, its file and line, what the
test printed, its error (an `expect`'s reason is part of that text), and the
top of its stack trace. A failed `testWidgets` case's reason is in what it
printed: the Flutter test framework prints the failure, and its error says
only "Test failed. See exception logs above."
If a summary file is given, the same information goes into it as Markdown,
without the stack traces. If no test failed, the tail of the runner's
non-JSON output goes to both instead. A build or device error that stops any
test from starting only ever appears there.

Exit: 0  whatever was found has been written
      2  bad usage, or the events file cannot be read
"""
import json
import os
import sys

# A failure message can be a whole widget tree. The log is capped more
# generously than the summary because the summary is read on one page.
LOG_ERROR_LINES = 80
SUMMARY_ERROR_LINES = 30
STACK_LINES = 8
SUMMARY_TESTS = 20
RUNNER_TAIL = 40


def clip(text: str, limit: int) -> list[str]:
    lines = text.rstrip("\n").split("\n")
    if len(lines) > limit:
        lines = lines[:limit] + [f"... ({len(lines) - limit} more lines)"]
    return lines


def fence(lines: list[str]) -> list[str]:
    # A longer fence than any backtick run inside, so the text cannot close it.
    ticks = 3
    for line in lines:
        run = 0
        for ch in line:
            run = run + 1 if ch == "`" else 0
            ticks = max(ticks, run + 1)
    return ["`" * ticks + "text", *lines, "`" * ticks]


def main(argv: list[str]) -> int:
    if len(argv) not in (2, 3):
        print("failed_tests: usage: failed_tests.py <events> [summary]", file=sys.stderr)
        return 2
    try:
        with open(argv[1], encoding="utf-8", errors="replace") as f:
            raw = f.read().splitlines()
    except OSError as e:
        print(f"failed_tests: cannot read {argv[1]}: {e}", file=sys.stderr)
        return 2

    suites: dict[int, str] = {}
    tests: dict[int, dict] = {}
    errors: dict[int, list[dict]] = {}
    prints: dict[int, list[str]] = {}
    failed: list[int] = []
    other: list[str] = []
    for line in raw:
        try:
            event = json.loads(line)
        except ValueError:
            event = None
        if not isinstance(event, dict):
            if line.strip():
                other.append(line)
            continue
        kind = event.get("type")
        if kind == "suite":
            suite = event.get("suite") or {}
            path = suite.get("path") or "?"
            if os.path.isabs(path):
                path = os.path.relpath(path)
            suites[suite.get("id")] = path
        elif kind == "testStart":
            test = event.get("test") or {}
            tests[test.get("id")] = test
        elif kind == "print":
            prints.setdefault(event.get("testID"), []).append(str(event.get("message", "")))
        elif kind == "error":
            errors.setdefault(event.get("testID"), []).append(event)
        elif kind == "testDone" and event.get("result") in ("failure", "error"):
            failed.append(event.get("testID"))

    log: list[str] = []
    summary: list[str] = []
    for n, test_id in enumerate(failed):
        test = tests.get(test_id, {})
        name = test.get("name") or f"test {test_id}"
        where = suites.get(test.get("suiteID"), "?")
        line = test.get("root_line") or test.get("line")
        if line:
            where = f"{where}:{line}"
        log.append(f"FAILED: {name}  ({where})")
        printed = "\n".join(prints.get(test_id, []))
        if printed:
            log += ["  " + l for l in clip(printed, LOG_ERROR_LINES)]
        detail = errors.get(test_id, [])
        if not detail:
            log.append("  (the runner reported no error for this test)")
        for e in detail:
            log += ["  " + l for l in clip(str(e.get("error", "")), LOG_ERROR_LINES)]
            stack = str(e.get("stackTrace") or "").strip()
            if stack:
                log += ["    " + l for l in clip(stack, STACK_LINES)]
        if n < SUMMARY_TESTS:
            summary.append(f"**FAILED: `{name}`** (`{where}`)")
            text = "\n".join(str(e.get("error", "")) for e in detail) or "(no error reported)"
            if printed:
                summary += fence(clip(printed, SUMMARY_ERROR_LINES))
            summary += fence(clip(text, SUMMARY_ERROR_LINES))
            summary.append("")
    if len(failed) > SUMMARY_TESTS:
        summary.append(f"... and {len(failed) - SUMMARY_TESTS} more failed tests; see the log.")

    if not failed and other:
        tail = other[-RUNNER_TAIL:]
        log.append(f"no test failed; the runner's last {len(tail)} lines of other output:")
        log += ["  " + l for l in tail]
        summary.append("No test failed. The runner's last lines of other output:")
        summary += fence(tail)

    if log:
        print("\n".join(log))
    if len(argv) == 3 and argv[2] and summary:
        with open(argv[2], "a", encoding="utf-8") as f:
            f.write("\n".join(summary) + "\n\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
