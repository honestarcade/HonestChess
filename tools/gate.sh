#!/usr/bin/env bash
# The quality gate: everything CI will run, in the order CI will run it.
#
# "Green locally" and "green in CI" mean the same thing only if they are the
# same list, so ci.yml runs this script rather than restating the steps. A
# step added here is a step CI gains.
#
# Signing: with no HS_* variables the release build falls back to the debug key
# (see android/app/build.gradle.kts), so the gate passes on a fresh clone with
# no secrets. With HS_RELEASE=1 and no secrets it fails at the build step, as
# release.yml's build does.
#
# Usage: tools/gate.sh
set -euo pipefail
# Deterministic classification: the whitespace rules below must behave the
# same in a UTF-8 shell and in the C locale a bare CI runner has.
export LC_ALL=C
cd "$(dirname "$0")/.."

LABELS=(
  "resolve dependencies"
  "analyze"
  "check formatting"
  "test (includes the invariant guards)"
  "build release bundle"
  "scan the bundle for permissions"
)

# The build step runs WITHOUT --no-pub: `flutter pub get` writes a plugin
# registrant that includes dev-only plugins (the device-test harness, #38), and only
# the build's own resolution regenerates it for release, which excludes them.
# With --no-pub the release build compiles a registrant naming a plugin it
# does not link, and fails.
COMMANDS=(
  "flutter pub get --enforce-lockfile"
  "dart analyze --fatal-infos"
  "dart format --output=none --set-exit-if-changed ."
  "flutter test --no-pub --exclude-tags weekly"
  "flutter build appbundle --release"
  "tools/check_aab.sh"
)

BUNDLE="build/app/outputs/bundle/release/app-release.aab"

SIGNING_VARS=(HS_KEYSTORE_PATH HS_KEYSTORE_PASS HS_KEY_ALIAS HS_KEY_PASS)

# Say which key the bundle will be signed with, so a passing gate never leaves
# the reader guessing whether the artefact is real.
#
# Four states: upload, debug fallback, partial (Gradle refuses, and the message
# names the missing variable), and HS_RELEASE=1 with nothing set.
#
# Blank, not merely empty, because build.gradle.kts decides with Kotlin's
# isNullOrBlank(), which treats whitespace as unset; if the two disagreed, the
# gate would announce one key while Gradle signed with the other. This matches
# Kotlin's Character.isWhitespace for the ASCII range: POSIX [:space:] plus
# 0x1C-0x1F, which Java also counts.
#
# What this does NOT cover: the multi-byte whitespace Java also counts
# (U+1680, U+2000-U+200A, U+2028, U+2029, U+205F, U+3000). Rather than widen
# `tr` further, the build states which key it used and the gate fails if this
# prediction disagreed — see the step-5 cross-check below.
hs_is_blank() {
  [ -z "$(printf '%s' "${1:-}" | tr -d '\011\012\013\014\015\034\035\036\037\040')" ]
}

# The machine-readable half of signing_mode: `upload`, `debug`, or `refusal`.
# Separate from the message, because two of the message's states predict a
# failed build, and a build that succeeds must not count as agreeing with them.
signing_prediction() {
  local set_count=0
  local name
  for name in "${SIGNING_VARS[@]}"; do
    if ! hs_is_blank "${!name:-}"; then set_count=$((set_count + 1)); fi
  done

  if [ "$set_count" -eq "${#SIGNING_VARS[@]}" ]; then
    if [ ! -f "${HS_KEYSTORE_PATH}" ] || [ ! -r "${HS_KEYSTORE_PATH}" ]; then
      echo "refusal"
    else
      echo "upload"
    fi
  elif [ "$set_count" -gt 0 ]; then
    echo "refusal"
  elif [ "${HS_RELEASE:-}" = "1" ]; then
    echo "refusal"
  else
    echo "debug"
  fi
}

# A non-`1` value is ignored, and says so.
warn_hs_release() {
  local v="${HS_RELEASE:-}"
  if [ -n "$v" ] && [ "$v" != "1" ]; then
    echo "gate: HS_RELEASE is '$v' — only the exact value 1 enables release" >&2
    echo "  mode. This run is treated as if HS_RELEASE were unset." >&2
  fi
}

signing_mode() {
  local set_count=0
  local missing=""
  local name
  for name in "${SIGNING_VARS[@]}"; do
    if hs_is_blank "${!name:-}"; then
      if [ -z "$missing" ]; then missing="$name"; fi
    else
      set_count=$((set_count + 1))
    fi
  done

  if [ "$set_count" -eq "${#SIGNING_VARS[@]}" ]; then
    # Say what the build will do, not what the variables suggest. Promising
    # the upload key while the keystore is missing is the same class of
    # false headline as the blank check above.
    if [ ! -f "${HS_KEYSTORE_PATH}" ] || [ ! -r "${HS_KEYSTORE_PATH}" ]; then
      echo "HS_* set but HS_KEYSTORE_PATH is not readable — the build will fail"
    elif [ "${HS_RELEASE:-}" = "1" ]; then
      echo "HS_* set, HS_RELEASE=1 — signing with the upload key"
    else
      echo "HS_* set — signing with the upload key"
    fi
  elif [ "$set_count" -gt 0 ]; then
    echo "partial — $missing is empty, Gradle will refuse this build"
  elif [ "${HS_RELEASE:-}" = "1" ]; then
    echo "HS_RELEASE=1 with no HS_* variables — Gradle will refuse this build"
  else
    echo "debug fallback — no HS_* variables set"
  fi
}

# Report the mode and stop, so the gate's signing branches can be checked
# without running a build.
if [ "${1:-}" = "--signing-mode" ]; then
  warn_hs_release
  signing_mode
  exit 0
fi

# Say when the local Flutter is not the one CI pins.
#
# A warning, never a failure: a contributor on a nearby version should be able
# to run the gate, and the only thing that matters is that they know CI will
# use a different one. `.fvmrc` is the single pin `subosito/flutter-action`
# reads, so this compares against the same file rather than a second copy.
#
# Parsed with sed rather than jq, which stock macOS does not have. Either read
# failing is silence, not noise — this is a courtesy line, and a courtesy that
# errors is worse than none.
flutter_pin_warning() {
  local pin local_version
  [ -r .fvmrc ] || return 0
  pin="$(sed -n 's/.*"flutter"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' .fvmrc | head -1)"
  [ -n "$pin" ] || return 0
  local_version="$(flutter --version --machine 2>/dev/null |
    sed -n 's/.*"frameworkVersion"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
  [ -n "$local_version" ] || return 0
  if [ "$local_version" != "$pin" ]; then
    echo "note: flutter $local_version differs from .fvmrc pin $pin; CI uses the pin" >&2
  fi
}
flutter_pin_warning

# The path GATE PASSED names must hold THIS run's artefact or nothing, for the
# whole run, so a stale bundle is removed before any step reads it.
rm -f "$BUNDLE"
# Portable across BSD and GNU: `mktemp -t <prefix>` appends a suffix on macOS
# and demands a template ending in XXX on GNU coreutils.
BUILD_LOG="$(mktemp "${TMPDIR:-/tmp}/hs-gate-build.XXXXXX")"
# Named by the gate, written only by build.gradle.kts, read back below, rather
# than grepping the build log for a phrase anything could print.
VERDICT_FILE="$(mktemp "${TMPDIR:-/tmp}/hs-gate-verdict.XXXXXX")"
: > "$VERDICT_FILE"
export HS_SIGNING_VERDICT="$VERDICT_FILE"
trap 'rm -f "$BUILD_LOG" "$VERDICT_FILE"' EXIT
SIGNING_MODE=""

# Runs one step as an array of words, without `eval`.
run_step() {
  local -a words
  read -r -a words <<< "$1"
  "${words[@]}"
}

total=${#LABELS[@]}
i=0
while [ "$i" -lt "$total" ]; do
  step=$((i + 1))
  label="${LABELS[$i]}"
  command="${COMMANDS[$i]}"

  if [ "$step" -eq 5 ]; then
    warn_hs_release
    SIGNING_MODE="$(signing_mode)"
    echo "[$step/$total] $label ($SIGNING_MODE)"
  else
    echo "[$step/$total] $label"
  fi

  # Output streams live: a gate that buffers is a gate nobody watches.
  #
  # The status is captured BEFORE any test, not inside `if ! cmd; then $? ...`,
  # where `$?` is the status of the negation and always 0.
  status=0
  if [ "$step" -eq 5 ]; then
    # Captured as well as streamed. PIPESTATUS[0] is Gradle's status, not
    # tee's. `set +e` around the pipeline, because under `set -e` a failing
    # pipeline would end the script before GATE FAILED is printed; `|| true`
    # would not do, since PIPESTATUS would then describe `true`.
    set +e
    run_step "$command" 2>&1 | tee "$BUILD_LOG"
    status=${PIPESTATUS[0]}
    set -e
  else
    run_step "$command" || status=$?
  fi
  if [ "$status" -ne 0 ]; then
    # On stderr, with the code, so a caller separating the streams still sees
    # it.
    echo "GATE FAILED at $label (exit $status)" >&2
    exit "$status"
  fi

  # The cross-check. `signing_mode` is a prediction; Gradle is the fact. A
  # disagreement is a gate failure, so the header can never announce the
  # upload key over a debug-signed bundle.
  if [ "$step" -eq 5 ]; then
    # Read from a file Gradle wrote, not grepped out of the build log: the log
    # is not ours. JAVA_TOOL_OPTIONS or _JAVA_OPTIONS make the JVM echo
    # arbitrary text into it before Gradle starts.
    if [ ! -s "$VERDICT_FILE" ]; then
      echo "GATE FAILED at $label: the build wrote no signing verdict to" >&2
      echo "  \$HS_SIGNING_VERDICT. build.gradle.kts must write one of" >&2
      echo "  'upload' or 'debug' there, or the gate cannot tell you what" >&2
      echo "  it built." >&2
      exit 1
    fi
    actual="$(tr -d ' \n\r\t' < "$VERDICT_FILE")"
    case "$actual" in
    upload | debug) ;;
    *)
      echo "GATE FAILED at $label: the signing verdict file says '$actual'," >&2
      echo "  which is neither 'upload' nor 'debug'." >&2
      exit 1
      ;;
    esac

    predicted="$(signing_prediction)"
    # A refusal predicted and a bundle produced is a failure on its own: the
    # header said the build would fail and it did not.
    if [ "$predicted" = "refusal" ]; then
      echo "GATE FAILED at $label: the header said '$SIGNING_MODE'," >&2
      echo "  and the build succeeded anyway, signing with the $actual key." >&2
      echo "  A predicted refusal that builds means the gate and Gradle" >&2
      echo "  disagree about what the HS_* variables mean." >&2
      exit 1
    fi
    if [ "$actual" != "$predicted" ]; then
      echo "GATE FAILED at $label: the header said '$SIGNING_MODE'," >&2
      echo "  predicting the $predicted key, and Gradle signed with the" >&2
      echo "  $actual key. These two decide 'is this variable set'" >&2
      echo "  separately and have disagreed before." >&2
      exit 1
    fi
    echo "signing: Gradle used the $actual key (prediction agreed)"
  fi
  i=$((i + 1))
done

echo "GATE PASSED $BUNDLE"
# The battery is NOT part of this gate: it runs as its own CI job because it
# executes the guard suite once per mutation. A green gate says the guards
# pass; it says nothing about whether they can fail.
echo "note: tools/mutation_check.py is not part of this gate — run it before changing a guard"
# The gate reads the WORKING TREE, and CI reads the commit, so a defect
# committed and then corrected only in the tree passes here and fails in CI.
# This note is so the difference is not a surprise.
if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
  echo "note: the working tree is dirty, so this verdict is about the tree, not HEAD:"
  git status --porcelain | sed 's/^/  /'
fi
