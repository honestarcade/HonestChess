#!/usr/bin/env bash
# Refuse to release an app that still carries the template's identity.
#
# Play refuses a com.example.* package id, but only once a signed bundle is
# uploaded to it. release.yml runs this first, so a clone that was never
# renamed fails before anything is built.
#
# Usage: tools/release_identity.sh [path/to/app_identity.yaml]
# Exit:  0  prints the package id
#        1  no package id, or the template's placeholder
set -euo pipefail
export LC_ALL=C
cd "$(dirname "$0")/.."

FILE="${1:-app_identity.yaml}"
if [ ! -r "$FILE" ]; then
  echo "release-identity: cannot read $FILE" >&2
  exit 1
fi
id="$(sed -n 's/^package_id:[[:space:]]*\([^[:space:]#]*\).*/\1/p' "$FILE" | head -1)"
if [ -z "$id" ]; then
  echo "release-identity: $FILE names no package_id" >&2
  exit 1
fi
case "$id" in
  com.example.*)
    echo "release-identity: $id is the template's placeholder;" >&2
    echo "  run tools/rename_app.py <package-id> \"<label>\" first" >&2
    exit 1
    ;;
esac
echo "$id"
