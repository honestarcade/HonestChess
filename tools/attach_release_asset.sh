#!/usr/bin/env bash
# Attach the signed bundle and its checksum to the GitHub release for a tag,
# then download the asset back and compare hashes.
#
# /n8-release creates the release and the tag together, but a bare tag has no
# release. That case alone is a skip: the bundle is still in the run artifact
# and on Play. Any other `gh release view` failure — a 5xx, a rate limit, a
# token without contents: write — fails, so a broken attach is never reported
# as "no release". test/guards/release_scripts_test.dart runs every branch
# against a fake gh.
#
# Usage: tools/attach_release_asset.sh <tag> [path/to/app.aab]
#        Needs <aab>.sha256 beside the bundle, and gh authenticated (GH_TOKEN).
#        Writes $RUNNER_TEMP/no-release-note when it skips, for the summary.
# Exit:  0  attached and verified, or no release for the tag
#        1  gh failed, or the downloaded asset does not match
#        2  a missing argument or input file
set -euo pipefail
export LC_ALL=C

TAG="${1:-}"
AAB="${2:-build/app/outputs/bundle/release/app-release.aab}"
WORK="${RUNNER_TEMP:-$(mktemp -d)}"

if [ -z "$TAG" ]; then
  echo "attach_release_asset: no tag given" >&2
  exit 2
fi
for required in "$AAB" "$AAB.sha256"; do
  if [ ! -r "$required" ]; then
    echo "attach_release_asset: cannot read $required" >&2
    exit 2
  fi
done

sha256() {
  if command -v sha256sum > /dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

view_err="$WORK/release-view.err"
if ! gh release view "$TAG" > /dev/null 2> "$view_err"; then
  if grep -qiE 'release not found|not found \(HTTP 404\)|could not find' "$view_err"; then
    echo "no GitHub release for $TAG; skipping asset"
    echo "no GitHub release for this tag; the bundle is in the run artifact only" \
      > "$WORK/no-release-note"
    exit 0
  fi
  echo "attach_release_asset: gh release view failed for a reason other than not-found:" >&2
  cat "$view_err" >&2
  exit 1
fi

gh release upload "$TAG" "$AAB" "$AAB.sha256" --clobber
verify="$WORK/verify"
rm -rf "$verify"
gh release download "$TAG" --pattern "$(basename "$AAB")" --dir "$verify" --clobber
if [ "$(sha256 "$AAB")" != "$(sha256 "$verify/$(basename "$AAB")")" ]; then
  echo "attach_release_asset: the uploaded asset does not match what was built" >&2
  exit 1
fi
echo "asset attached and its hash re-verified"
