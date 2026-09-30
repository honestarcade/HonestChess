#!/usr/bin/env bash
# The scripted end-to-end games (#107) — integration_test/e2e_game_test.dart —
# on one attached Android emulator, with a pass/fail summary from
# tools/counted_tests.sh. It never boots an emulator: start one first.
#
# The test wipes the app's saved data on the device it runs on, so a phone
# (any serial not starting `emulator-`) is refused unless --allow-wipe is
# given, and even then only after typing `wipe`. On a phone the Play-installed
# build is uninstalled first: the test installs a debug build, which Android
# will not lay over a build signed with another key.
#
# The nightly device job (.github/workflows/device.yml) runs this file with
# the rest of integration_test/ through tools/device_tests.sh.
#
# Usage: tools/e2e.sh [-d <serial>] [--allow-wipe]
# Exit:  counted_tests.sh's (0 passed, 1 failed, 3 no test ran), or
#        2  bad usage, no device, more than one without -d, or a refused phone
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

usage() {
  echo "usage: tools/e2e.sh [-d <serial>] [--allow-wipe]" >&2
  exit 2
}

serial=""
allow_wipe=0
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
    *) usage ;;
  esac
done

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
[ -n "$adb" ] || { echo "e2e: adb not found (PATH or ANDROID_HOME)" >&2; exit 2; }

attached="$("$adb" devices | awk 'NR > 1 && $2 == "device" { print $1 }')"
if [ -z "$serial" ]; then
  count="$(printf '%s\n' "$attached" | grep -c . || true)"
  if [ "$count" -eq 0 ]; then
    echo "e2e: no device attached — start an emulator first (this script never boots one)" >&2
    exit 2
  fi
  if [ "$count" -gt 1 ]; then
    echo "e2e: more than one device attached; choose one with -d <serial>:" >&2
    printf '%s\n' "$attached" | sed 's/^/  /' >&2
    exit 2
  fi
  serial="$attached"
elif ! printf '%s\n' "$attached" | grep -qx -- "$serial"; then
  echo "e2e: $serial is not attached" >&2
  exit 2
fi

case "$serial" in
  emulator-*) ;;
  *)
    if [ "$allow_wipe" -ne 1 ]; then
      echo "e2e: $serial is a phone, not an emulator. The test erases the app's" >&2
      echo "saved games, statistics and settings on it. Run with --allow-wipe to" >&2
      echo "go ahead anyway." >&2
      exit 2
    fi
    package="$(awk '/^package_id:/ { print $2 }' app_identity.yaml)"
    [ -n "$package" ] || { echo "e2e: no package_id in app_identity.yaml" >&2; exit 2; }
    echo "WARNING: this uninstalls $package from $serial and erases its saved"
    echo "games, statistics and settings. Afterwards, reinstall it from the Play"
    echo "internal test link."
    printf 'Type wipe to go ahead: '
    read -r answer || answer=""
    if [ "$answer" != "wipe" ]; then
      echo "e2e: not confirmed — nothing was touched" >&2
      exit 2
    fi
    "$adb" -s "$serial" uninstall "$package" || true
    ;;
esac

"$(dirname "$0")/counted_tests.sh" e2e --no-pub integration_test/e2e_game_test.dart -d "$serial"
status=$?
case "$serial" in
  emulator-*) ;;
  *) echo "e2e: reinstall $package on $serial from the Play internal test link." ;;
esac
exit "$status"
