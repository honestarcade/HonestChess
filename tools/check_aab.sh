#!/usr/bin/env bash
# Scan a built Android App Bundle for declared permissions and confirm its
# package id. It checks the artefact that actually ships, which is the only
# place a plugin's merged manifest can be seen; bundle_scan_test.dart runs it
# on synthetic bundles to prove it refuses.
#
# The bundle's AndroidManifest.xml is protobuf-encoded, not text XML, so this
# is a byte-string search rather than an XML parse: the permission names and
# the package id survive the encoding intact as printable runs, which is all
# the check needs.
#
# Usage:  tools/check_aab.sh [path/to/app.aab]
# Exit:   0  no permissions declared, package correct
#         1  one or more permissions declared
#         2  package id missing or wrong
#         3  file unreadable, not an .aab, or no manifest entry in the zip
#
# Needs unzip, tr, grep, sort, awk and dirname. Written for bash 3.2 (macOS
# default).
set -euo pipefail
export LC_ALL=C

# Resolve the default path from the repository root, so the script works from
# anywhere.
cd "$(dirname "$0")/.."

AAB="${1:-build/app/outputs/bundle/release/app-release.aab}"
# The default is written by tools/rename_app.py; the override is for tests.
PACKAGE="${APP_PACKAGE_ID:-com.honestarcade.chess}"
MANIFEST_ENTRY="base/manifest/AndroidManifest.xml"

case "$AAB" in
  *.aab) ;;
  *) echo "check_aab: $AAB is not an .aab (this scan only understands bundles)" >&2; exit 3 ;;
esac

if [ ! -r "$AAB" ]; then
  echo "check_aab: cannot read $AAB" >&2
  exit 3
fi

# Pre-list rather than trusting `unzip -p` to fail: it prints nothing and exits
# 0 for a missing entry, which would read as "no permissions found".
#
# grep -c, never grep -q: -q exits at the first match, closing the pipe under
# `unzip`, which then dies of SIGPIPE — and with `set -o pipefail` that failure
# becomes the pipeline's, so the result would depend on timing. -c reads to
# the end.
ENTRY_COUNT="$(unzip -Z1 "$AAB" 2>/dev/null | grep -xc "$MANIFEST_ENTRY" || true)"
if [ "${ENTRY_COUNT:-0}" -eq 0 ]; then
  echo "check_aab: $AAB has no $MANIFEST_ENTRY entry" >&2
  exit 3
fi

STRINGS="$(unzip -p "$AAB" "$MANIFEST_ENTRY" 2>/dev/null | tr -c '[:print:]' '\n' || true)"

if [ -z "$STRINGS" ]; then
  echo "check_aab: $MANIFEST_ENTRY in $AAB produced no readable strings" >&2
  exit 3
fi

# The package id first, and on its own: the allowlisted self-permission below
# is derived from it, so with a wrong id that permission would be reported as
# an offender and the real problem would be misdiagnosed.
#
# The id must appear as a whole token, followed by end-of-run or a character
# that cannot continue an id. `grep -x` would never match: the protobuf packs
# the next field's bytes straight after the string, so the run reads
# `com.honestarcade.chess"K`. grep -c rather than grep -q, for the SIGPIPE reason
# given at the entry check above.
PACKAGE_HITS="$(printf '%s\n' "$STRINGS" | grep -cE "(^|[^.A-Za-z0-9_])${PACKAGE//./\\.}([^.A-Za-z0-9_]|\$)" || true)"
if [ "${PACKAGE_HITS:-0}" -eq 0 ]; then
  echo "PACKAGE MISSING: expected $PACKAGE in $AAB" >&2
  exit 2
fi

# What counts as an offender, and why the obvious rule is wrong.
#
# A byte scan cannot see XML structure, and `android.permission.X` appears in a
# manifest for two opposite reasons:
#
#   REQUESTING   <uses-permission android:name="android.permission.INTERNET"/>
#                the app asks Android for a capability.  This is what invariant
#                1 forbids.
#
#   RESTRICTING  <receiver android:permission="android.permission.DUMP">
#                the app refuses to talk to callers who lack DUMP.  This grants
#                the app nothing; it is a lock, not a key.
#
# Every Flutter release build contains exactly one of the second kind, from
# androidx.profileinstaller's ProfileInstallReceiver. So a rule of "fail on any
# android.permission. string" can never pass on any Flutter app, which is why
# the allowlist below exists. It holds one entry, matched exactly. Anything
# else — including a new restriction — fails and forces a human to look.
#
# Also present in every release build: a signature-level permission the app
# declares on ITSELF (<package>.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION), added
# by androidx.core so dynamically-registered receivers are not world-readable.
# It is granted only to this app's own signature, is not an android.permission.*
# and is not shown to users by Play. It is allowlisted below, as both the
# declaration and the request, and only at `signature` level.
ALLOWED_RESTRICTION="android.permission.DUMP"

FOUND_PERMS="$(printf '%s\n' "$STRINGS" | grep -o 'android\.permission\.[A-Z_]*' | sort -u || true)"

OFFENDERS=""
ALLOWED_SEEN=""
SELF_PERM_SEEN=""
DECLARE_SEEN=""
REQUEST_SEEN=""
while IFS= read -r perm; do
  [ -z "$perm" ] && continue
  if [ "$perm" = "$ALLOWED_RESTRICTION" ]; then
    ALLOWED_SEEN="$perm"
  else
    OFFENDERS="$OFFENDERS$perm
"
  fi
done <<EOF
$FOUND_PERMS
EOF

# Permissions, requested and declared.
#
# The manifest has two kinds of permission element and they fail differently:
#
#   REQUESTED   <uses-permission android:name="…"/>
#               the app asks Android for a capability. Invariant 1 forbids it.
#
#   DECLARED    <permission android:name="…" android:protectionLevel="…"/>
#               the app defines a permission other apps may request. It grants
#               this app nothing, but the release build declares none, and
#               manifest_permission_example_test.dart refuses one in source.
#
# Both kinds are decoded from the element, the same way. An element name is not
# a run of its own: the protobuf packs the next field's tag onto it, so the run
# reads `uses-permission"y`. Matching dotted names anywhere instead would hit
# intent actions. The encoding is regular:
#
#     permission"y                                   <- element name + next tag
#     *http://schemas.android.com/apk/res/android    <- the android namespace
#     name                                           <- the attribute's name
#     @com.honestarcade.chess.DYNAMIC_…PERMISSION(  <- length byte + value
#     *http://schemas.android.com/apk/res/android
#     protectionLevel
#     signature"
#
# What this does NOT cover: a permission name of 128 characters or more takes a
# two-byte length varint and both bytes are non-printable, so it decodes
# cleanly; a name of 32 to 127 characters keeps one printable length byte, and
# is reported with a stray character in front. The verdict never depends on
# decoding the name — only the message does. It also reads `base/` only, so a
# feature-module manifest is out of scope; this app has no deferred components.
#
# One request and one declaration are allowlisted, and they are the same
# permission: androidx.core makes every app declare
# <package>.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION on itself so that
# dynamically-registered receivers are not world-readable. It is allowlisted
# only at `signature` protection level — at any other level it would be a
# permission other apps could actually hold, and that is a different thing
# wearing the same name.
ALLOWED_SELF_PERMISSION="${PACKAGE}.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION"

# One tab-separated line per permission element: kind, name, protection level.
# An element whose name cannot be read reports `<undecoded>`, which is a
# failure and not a pass — a permission nobody can name is still a permission.
PERM_ENTRIES="$(printf '%s\n' "$STRINGS" | awk '
  function flush() {
    if (inel) {
      print kind "\t" (name == "" ? "<undecoded>" : name) "\t" level
      inel = 0
    }
  }
  /^uses-permission(-sdk-23)?([^A-Za-z0-9_-]|$)/ {
    flush(); kind = "REQUEST"; inel = 1; window = 0; want = ""; name = ""; level = ""; next
  }
  # The two element-start patterns are deliberately NOT the same shape.
  # `permission` is also an ATTRIBUTE name — `android:permission` on a
  # receiver — and its run is bare, so the looser request pattern
  # would read the DUMP access restriction as a declared permission.
  # `uses-permission` never appears as an attribute name, so it can afford it.
  /^permission(-group|-tree)?["*]/ {
    flush(); kind = "DECLARE"; inel = 1; window = 0; want = ""; name = ""; level = ""; next
  }
  inel {
    if ($0 == "") next
    if (++window > 16) { flush(); next }
    if ($0 == "name") { want = "name"; next }
    if ($0 == "protectionLevel") { want = "level"; next }
    if (index($0, "schemas.android.com/apk/res")) next
    if (want != "") {
      v = $0
      sub(/[("].*$/, "", v)
      if (want == "name") { name = v } else { level = v }
      want = ""
      next
    }
    # The element ends at the next element name, or the `name` attribute of a
    # later element would overwrite the permission. An element name is a
    # lowercase run with the next field tag packed onto it: `application"n`,
    # `intent-filter*`.
    # Checked AFTER the value assignment above, so a value that happens to
    # look like one — `signature"` is exactly that — is still read first.
    if ($0 ~ /^[a-z][a-z0-9_-]*["*]/) { flush(); next }
    # Fallback for a layout this decoder has not seen: a run shaped like a
    # permission name (a dotted id ending in a SHOUTING segment).
    if (name == "" && $0 ~ /\.[A-Z][A-Z0-9_]*(\(|$)/) {
      v = $0; sub(/[("].*$/, "", v); name = v; next
    }
  }
  END { flush() }
' || true)"

while IFS="$(printf '\t')" read -r kind rawname rawlevel; do
  [ -z "${kind:-}" ] && continue
  # Drop the length byte in front, if the run kept one.
  value="$rawname"
  level="${rawlevel:-}"
  if [ "$value" = "$ALLOWED_SELF_PERMISSION" ] ||
    [ "${value#?}" = "$ALLOWED_SELF_PERMISSION" ]; then
    if [ "$kind" = "DECLARE" ] && [ "$level" != "signature" ] &&
      [ "${level#?}" != "signature" ]; then
      OFFENDERS="$OFFENDERS$ALLOWED_SELF_PERMISSION declared at protectionLevel '${level:-none}', not signature
"
      continue
    fi
    SELF_PERM_SEEN="$ALLOWED_SELF_PERMISSION"
    if [ "$kind" = "DECLARE" ]; then
      DECLARE_SEEN=1
    else
      REQUEST_SEEN=1
    fi
    continue
  fi
  if [ "$value" = "<undecoded>" ]; then
    if [ "$kind" = "DECLARE" ]; then
      OFFENDERS="$OFFENDERS<permission element with an unreadable name>
"
    else
      OFFENDERS="$OFFENDERS<uses-permission with an unreadable name>
"
    fi
    continue
  fi
  name="$(printf '%s' "$value" | grep -oE '[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z0-9_]+)+$' || true)"
  [ -z "$name" ] && name="$value"
  if [ "$kind" = "DECLARE" ]; then
    OFFENDERS="$OFFENDERS$name (declared)
"
  else
    OFFENDERS="$OFFENDERS$name
"
  fi
done <<EOF
$PERM_ENTRIES
EOF

# The decoder must not go inert on a real bundle.
#
# bundle_scan_test.dart proves the decoder on synthetic bundles; this proves it
# still sees something on the real artefact, on every gate run, which a test
# cannot do without running the build.
#
# Every Flutter build carries `flutterEmbedding` meta-data, and every one also
# carries the androidx.core self-permission — as a <permission> declaration and
# a <uses-permission> request. So in a bundle that is recognisably a Flutter
# app, finding no permission element at all does not mean the app is clean; it
# means the element matcher stopped matching.
#
# If a future Flutter or androidx drops that self-permission this will fail
# loudly and wrongly. That is the intended direction: a human looks, confirms
# the encoding, and edits this check. Silence would be the other kind of wrong.
if printf '%s\n' "$STRINGS" | grep -qF 'flutterEmbedding'; then
  # BOTH halves, not either: a decoder blind to declarations alone, or to
  # requests alone, must fail here too.
  #
  # What this does NOT catch:
  #
  #   1. A PARTIALLY blind decoder, one that still sees the self-permission
  #      but misses a third-party one beside it. That shape is for
  #      bundle_scan_test.dart's fixtures, which include such a bundle.
  #   2. DECLARE_SEEN and REQUEST_SEEN are set from a decoded NAME, not from
  #      a confirmed element, so a string run that merely reads as an element
  #      start sets the flag.
  if [ -z "$OFFENDERS" ]; then
    MISSING=""
    [ -z "${DECLARE_SEEN:-}" ] && MISSING="the <permission> declaration"
    if [ -z "${REQUEST_SEEN:-}" ]; then
      if [ -n "$MISSING" ]; then
        MISSING="$MISSING and the <uses-permission> request"
      else
        MISSING="the <uses-permission> request"
      fi
    fi
    if [ -n "$MISSING" ]; then
      echo "check_aab: this is a Flutter bundle but the scan did not find $MISSING" >&2
      echo "  of ${PACKAGE}.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION, which androidx.core" >&2
      echo "  puts in every build as both. Finding it missing means this decoder has gone" >&2
      echo "  inert for that half, not that the bundle is clean." >&2
      exit 1
    fi
  fi
fi

OFFENDERS="$(printf '%s' "$OFFENDERS" | grep -v '^$' | sort -u || true)"

# Report everything found before exiting, so one run tells the whole story.
STATUS=0
if [ -n "$OFFENDERS" ]; then
  while IFS= read -r line; do
    [ -n "$line" ] && echo "PERMISSION: $line" >&2
  done <<EOF
$OFFENDERS
EOF
  STATUS=1
fi

if [ "$STATUS" -ne 0 ]; then
  exit "$STATUS"
fi

if [ -n "$ALLOWED_SEEN" ]; then
  echo "note: $ALLOWED_SEEN present as a receiver access restriction, not a request (allowlisted)" >&2
fi
if [ -n "${SELF_PERM_SEEN:-}" ]; then
  echo "note: $SELF_PERM_SEEN is this app's own signature-level permission, added by androidx.core (allowlisted)" >&2
fi
echo "no permissions declared (package $PACKAGE)"
