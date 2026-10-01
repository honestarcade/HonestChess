#!/usr/bin/env bash
# The computer's thinking time on one attached Android device (#112): builds
# perf_test/think_time_test.dart as a profile-mode app (debug builds run the
# search JIT-compiled, so their times mean nothing), installs and launches
# it, reads its results from logcat, prints the table and writes the JSON to
# build/perf/. It never boots an emulator: start one, or connect the phone
# with USB debugging on.
#
# Installing the timing build replaces the app and erases its saved games,
# statistics and settings, so a phone (any serial not starting `emulator-`)
# is refused unless --allow-wipe is given, and even then only after typing
# `wipe`. The timing build is uninstalled at the end; on a phone, reinstall
# the app from Play afterwards.
#
# A step whose 95th percentile is past its target fails the run on a phone;
# on an emulator the table is a report only. A step faster than its stated
# time is shown as overstated and never fails. --compare <json> diffs every
# move against another run's JSON (CLAUDE.md invariant 4: the same position,
# step and seed give the same move on any device).
#
# Usage: tools/think_time.sh [-d <serial>] [--allow-wipe] [--compare <json>]
# Exit:  0  done (and, on a phone, every step within its target)
#        1  a step missed on a phone, the moves changed, or the run failed
#        2  bad usage, no device, more than one without -d, or a refused phone
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

usage() {
  echo "usage: tools/think_time.sh [-d <serial>] [--allow-wipe] [--compare <json>]" >&2
  exit 2
}

serial=""
allow_wipe=0
compare=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -d)
      [ "$#" -ge 2 ] || usage
      serial="$2"
      shift 2
      ;;
    --allow-wipe)
      allow_wipe=1
      shift
      ;;
    --compare)
      [ "$#" -ge 2 ] || usage
      compare="$2"
      shift 2
      ;;
    *) usage ;;
  esac
done
if [ -n "$compare" ] && [ ! -f "$compare" ]; then
  echo "think_time: $compare does not exist" >&2
  exit 2
fi

# adb from PATH, else the Android SDK's own.
adb="$(command -v adb || true)"
if [ -z "$adb" ]; then
  for sdk in "${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}" "$HOME/Library/Android/sdk" "$HOME/Android/Sdk"; do
    if [ -n "$sdk" ] && [ -x "$sdk/platform-tools/adb" ]; then
      adb="$sdk/platform-tools/adb"
      break
    fi
  done
fi
[ -n "$adb" ] || { echo "think_time: adb not found (PATH or ANDROID_HOME)" >&2; exit 2; }

attached="$("$adb" devices | awk 'NR > 1 && $2 == "device" { print $1 }')"
if [ -z "$serial" ]; then
  count="$(printf '%s\n' "$attached" | grep -c . || true)"
  if [ "$count" -eq 0 ]; then
    echo "think_time: no device attached — connect the phone or start an emulator first" >&2
    exit 2
  fi
  if [ "$count" -gt 1 ]; then
    echo "think_time: more than one device attached; choose one with -d <serial>:" >&2
    printf '%s\n' "$attached" | sed 's/^/  /' >&2
    exit 2
  fi
  serial="$attached"
elif ! printf '%s\n' "$attached" | grep -qx -- "$serial"; then
  echo "think_time: $serial is not attached" >&2
  exit 2
fi

package="$(awk '/^package_id:/ { print $2 }' app_identity.yaml)"
[ -n "$package" ] || { echo "think_time: no package_id in app_identity.yaml" >&2; exit 2; }

phone=1
case "$serial" in
  emulator-*) phone=0 ;;
esac
if [ "$phone" -eq 1 ]; then
  if [ "$allow_wipe" -ne 1 ]; then
    echo "think_time: $serial is a phone, not an emulator. The timing build" >&2
    echo "replaces $package on it and erases its saved games, statistics and" >&2
    echo "settings. Run with --allow-wipe to go ahead anyway." >&2
    exit 2
  fi
  echo "WARNING: this uninstalls $package from $serial and erases its saved"
  echo "games, statistics and settings. Afterwards, reinstall it from Play."
  printf 'Type wipe to go ahead: '
  read -r answer || answer=""
  if [ "$answer" != "wipe" ]; then
    echo "think_time: not confirmed — nothing was touched" >&2
    exit 2
  fi
fi

flutter="$(command -v flutter || true)"
[ -n "$flutter" ] || { echo "think_time: flutter not found on PATH" >&2; exit 2; }

echo "think_time: building the profile-mode timing app"
"$flutter" build apk --profile -t perf_test/think_time_test.dart ||
  { echo "think_time: the build failed" >&2; exit 1; }
apk="build/app/outputs/flutter-apk/app-profile.apk"

on() { "$adb" -s "$serial" "$@"; }

# Keep the screen on while the run lasts, so the device does not sleep
# mid-search; the setting is put back however the script ends.
stay_on="$(on shell settings get global stay_on_while_plugged_in | tr -d '\r')"
logcat_pid=""
cleanup() {
  [ -n "$logcat_pid" ] && kill "$logcat_pid" 2>/dev/null
  on shell am force-stop "$package" >/dev/null 2>&1
  on uninstall "$package" >/dev/null 2>&1
  case "$stay_on" in
    '' | null) ;;
    *) on shell settings put global stay_on_while_plugged_in "$stay_on" >/dev/null 2>&1 ;;
  esac
}
trap cleanup EXIT
on shell svc power stayon true >/dev/null 2>&1
on shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1

# Another signing key's build cannot be updated in place, so the app goes.
on uninstall "$package" >/dev/null 2>&1
on install "$apk" || { echo "think_time: install failed" >&2; exit 1; }

mkdir -p build/perf
stamp="$(date -u +%Y-%m-%dT%H%M%SZ)"
raw="build/perf/think_time-$stamp-${serial//[^A-Za-z0-9_-]/_}.log"
json="${raw%.log}.json"
on logcat -c
on logcat -v raw -s flutter:I >"$raw" 2>&1 &
logcat_pid=$!
on shell monkey -p "$package" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 ||
  { echo "think_time: the app did not launch" >&2; exit 1; }

echo "think_time: running on $serial — keep the device unlocked and plugged in."
# An hour, so even a slow phone is never cut off mid-run.
deadline=$(($(date +%s) + 3600))
until grep -qE '^think_time \{"kind":"(done|error)"' "$raw"; do
  if [ "$(date +%s)" -ge "$deadline" ]; then
    echo "think_time: no result within an hour; the log is $raw" >&2
    exit 1
  fi
  sleep 5
  printf '.'
done
echo

grep '^think_time table ' "$raw" | sed 's/^think_time table //'

THINK_SERIAL="$serial" THINK_PHONE="$phone" THINK_COMPARE="$compare" \
  THINK_COMMIT="$(git rev-parse --short HEAD)$(git diff --quiet HEAD -- lib perf_test || echo '-dirty')" \
  THINK_MODEL="$(on shell getprop ro.product.model | tr -d '\r')" \
  THINK_ANDROID="$(on shell getprop ro.build.version.release | tr -d '\r')" \
  THINK_SDK="$(on shell getprop ro.build.version.sdk | tr -d '\r')" \
  python3 - "$raw" "$json" <<'PY'
import json, os, sys
from datetime import datetime, timezone

raw, out = sys.argv[1], sys.argv[2]
records = []
for line in open(raw, encoding="utf-8", errors="replace"):
    if line.startswith('think_time {'):
        records.append(json.loads(line[len('think_time '):]))
kinds = lambda k: [r for r in records if r["kind"] == k]
errors = kinds("error")
if errors:
    print(f"think_time: the run failed: {errors[0]['message']}", file=sys.stderr)
    sys.exit(1)
moves, steps, done = kinds("move"), kinds("step"), kinds("done")[0]
expected = sum(s["count"] for s in steps)
if len(moves) != expected:
    print(f"think_time: {len(moves)} move lines for {expected} moves; logcat lost some", file=sys.stderr)
    sys.exit(1)
phone = os.environ["THINK_PHONE"] == "1"
result = {
    "date": datetime.now(timezone.utc).isoformat(timespec="seconds"),
    "commit": os.environ["THINK_COMMIT"],
    "mode": "profile",
    "device": {
        "serial": os.environ["THINK_SERIAL"],
        "model": os.environ["THINK_MODEL"],
        "android": os.environ["THINK_ANDROID"],
        "sdk": os.environ["THINK_SDK"],
        "emulator": not phone,
    },
    "steps": steps,
    "determinism": kinds("determinism")[0],
    "moves": moves,
}
with open(out, "w", encoding="utf-8") as f:
    json.dump(result, f, indent=1)
print(f"think_time: wrote {out}")

status = 0
over = [s["step"] for s in steps if s["vsStatedPercent"] < 0]
if over:
    print("think_time: faster than stated (logged, not a failure): " + ", ".join(over))
if not done["deterministic"]:
    print(f"think_time: FAILED — the repeat gave different moves: {result['determinism']['mismatches']}")
    status = 1
if done["misses"]:
    if phone:
        print("think_time: FAILED — past the target: " + ", ".join(done["misses"]))
        status = 1
    else:
        print("think_time: past the target on the emulator (report only): " + ", ".join(done["misses"]))
compare = os.environ["THINK_COMPARE"]
if compare:
    other = {(m["step"], m["index"]): m["uci"] for m in json.load(open(compare))["moves"]}
    differ = [(m["step"], m["index"], other[(m["step"], m["index"])], m["uci"])
              for m in moves if (m["step"], m["index"]) in other
              and other[(m["step"], m["index"])] != m["uci"]]
    shared = sum(1 for m in moves if (m["step"], m["index"]) in other)
    if differ:
        print(f"think_time: FAILED — {len(differ)} of {shared} moves differ from {compare}:")
        for step, index, then, now in differ:
            print(f"  {step} {index}: {then} there, {now} here")
        status = 1
    else:
        print(f"think_time: all {shared} moves match {compare}")
sys.exit(status)
PY
status=$?
if [ "$phone" -eq 1 ]; then
  echo "think_time: the timing build is being removed; reinstall $package from Play."
fi
exit "$status"
