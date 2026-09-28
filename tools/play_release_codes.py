#!/usr/bin/env python3
"""Pick the version codes of the newest release on a Play track.

Reads the Play Developer API's track JSON on stdin. Prints the chosen
release's version codes, space separated, on one line.

Usage: play_release_codes.py [status]      (default: completed)

The status argument lets play_promote.sh confirm a draft release the same
way it confirms a completed one.

A real JSON parse rather than a regex over flattened JSON, because a regex
cannot see past a nested object such as release notes, nor tell the newest
release from the last one listed.

"Newest" is the release whose highest version code is highest. Play lists
releases newest-first, but that is a presentation detail, not a guarantee,
and version codes are required to rise (see tools/ci_version.sh).

Exit: 0  codes printed
      1  no release with that status (stdout empty)
      2  stdin was not the JSON this expects (stdout empty)
"""
import json
import re
import sys


def main() -> int:
    # A backstop, unreachable today: the ten-digit check below refuses a long
    # run of digits before int() sees it. Kept against a change to that check.
    if hasattr(sys, "set_int_max_str_digits"):
        sys.set_int_max_str_digits(100000)
    want_status = sys.argv[1] if len(sys.argv) > 1 else "completed"
    if len(sys.argv) > 2:
        print("play_release_codes: expected at most one argument", file=sys.stderr)
        return 2
    raw = sys.stdin.read()
    try:
        doc = json.loads(raw)
    except (ValueError, TypeError):
        print("play_release_codes: stdin is not valid JSON", file=sys.stderr)
        return 2
    if not isinstance(doc, dict):
        print("play_release_codes: expected a JSON object", file=sys.stderr)
        return 2

    releases = doc.get("releases")
    if releases is None:
        releases = []
    if not isinstance(releases, list):
        print("play_release_codes: 'releases' is not a list", file=sys.stderr)
        return 2

    best = None
    for release in releases:
        if not isinstance(release, dict):
            # Refused, not skipped: skipping would report a track holding an
            # unreadable release as empty.
            print(
                "play_release_codes: release is not an object: %r" % (release,),
                file=sys.stderr,
            )
            return 2
        if release.get("status") != want_status:
            continue
        # Key presence, not `.get()` or `or []`: only an absent key may mean
        # "no codes". An explicit null, 0, false or {} is malformed input and
        # must exit 2, not read as an empty track.
        codes = [] if "versionCodes" not in release else release["versionCodes"]
        if not isinstance(codes, list):
            print(
                "play_release_codes: versionCodes is not a list: %r" % (codes,),
                file=sys.stderr,
            )
            return 2
        # The API sends them as strings; accept ints too rather than trust that.
        numeric = []
        for code in codes:
            # Strict, because bare `int()` accepts things JSON does not mean:
            # "1_0_1" -> 101, fullwidth "１０１" -> 101, True -> 1, " 101 " ->
            # 101. Each of those would become a plausible *wrong* code and be
            # PUT to the target track, rather than refused.
            if isinstance(code, bool) or not isinstance(code, (int, str)):
                print(
                    "play_release_codes: version code is not a number: %r" % (code,),
                    file=sys.stderr,
                )
                return 2
            text = code if isinstance(code, str) else str(code)
            # Digits only: no sign, no whitespace.
            if not re.fullmatch(r"[0-9]+", text):
                print(
                    "play_release_codes: version code is not a number: %r" % (code,),
                    file=sys.stderr,
                )
                return 2
            # Android's versionCode is a signed 32-bit int, so it cannot
            # exceed 2100000000 and can never be more than ten digits. A
            # longer run of digits is malformed input, not a large version,
            # and refusing it here keeps the int() below away from CPython's
            # digit ceiling.
            if len(text) > 10:
                print(
                    "play_release_codes: version code has %d digits; Android's"
                    " versionCode is a 32-bit int" % (len(text),),
                    file=sys.stderr,
                )
                return 2
            try:
                value = int(text)
            except ValueError as exc:
                # Caught rather than allowed to escape: an uncaught exception
                # exits 1, the code for "no release with that status".
                print(
                    "play_release_codes: could not read version code %r: %s"
                    % (code, exc),
                    file=sys.stderr,
                )
                return 2
            if value > 2100000000:
                print(
                    "play_release_codes: version code %d exceeds Android's"
                    " maximum of 2100000000" % (value,),
                    file=sys.stderr,
                )
                return 2
            numeric.append(value)
        if not numeric:
            continue
        if best is None or max(numeric) > max(best):
            best = numeric

    if best is None:
        return 1
    print(" ".join(str(code) for code in sorted(best)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
