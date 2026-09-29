#!/usr/bin/env bash
# Builds the piece font, assets/fonts/pieces/HonestPieces.ttf: Noto Sans
# Symbols 2 cut down to the twelve chess symbols, U+2654–265F (#71).
#
# The app draws its pieces only from this bundled font, never from a system
# fallback, so Android cannot swap in its colour emoji. The font ships inside
# the app and is never downloaded at run time (invariant 1); this script is
# how the file got here and how a later bump is made. CI never runs it.
#
# Needs curl and fontTools (`pip install fonttools`, for pyftsubset). The
# output's bytes depend on the fontTools version; SOURCE.md names the one used.
#
#   tools/subset_piece_font.sh
#
# Exit: 0 written, 2 a tool is missing, 3 the download failed.
#
# Bumping the pin is an edit to COMMIT below, a re-run, and the new hashes
# in assets/fonts/SOURCE.md.
set -euo pipefail
cd "$(dirname "$0")/.."

COMMIT="23e54b51ddffbc7713c583748e3bd86f62b1fa4a"
UPSTREAM="https://raw.githubusercontent.com/google/fonts/$COMMIT/ofl/notosanssymbols2"
DEST="assets/fonts/pieces"

command -v curl >/dev/null 2>&1 || { echo "subset_piece_font: curl is missing" >&2; exit 2; }
command -v pyftsubset >/dev/null 2>&1 || { echo "subset_piece_font: pyftsubset is missing (pip install fonttools)" >&2; exit 2; }

work="$(mktemp -d "${TMPDIR:-/tmp}/pieces.XXXXXX")"
trap 'rm -rf "$work"' EXIT

curl -fsSL "$UPSTREAM/NotoSansSymbols2-Regular.ttf" -o "$work/full.ttf" ||
  { echo "subset_piece_font: could not download the font" >&2; exit 3; }
curl -fsSL "$UPSTREAM/OFL.txt" -o "$work/OFL.txt" ||
  { echo "subset_piece_font: could not download the licence" >&2; exit 3; }

mkdir -p "$DEST"
pyftsubset "$work/full.ttf" \
  --unicodes="U+2654-265F" \
  --layout-features='*' \
  --no-hinting \
  --desubroutinize \
  --output-file="$work/HonestPieces.ttf"
mv "$work/HonestPieces.ttf" "$DEST/HonestPieces.ttf"
mv "$work/OFL.txt" "$DEST/OFL.txt"
echo "subset_piece_font: wrote $DEST/HonestPieces.ttf"
