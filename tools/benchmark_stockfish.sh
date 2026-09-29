#!/usr/bin/env bash
# Dev-only (#69): Master against Stockfish at UCI_Elo 1600, 1800 and 2000,
# 60 games each, appending the estimate to .n8/memory/engine-strength.md
# (not committed). CI never runs this; the benchmark-not-ci guard in
# test/guards/scheduled_tests_test.dart keeps it out of every workflow.
# Options pass through to tools/benchmark/uci_match.dart (--games N,
# --levels a,b,c, --out FILE, --pgn DIR).
#
# Exits 3 without Stockfish on PATH (e.g. `brew install stockfish`), so it
# can never report a result it did not play.
set -euo pipefail

if ! stockfish=$(command -v stockfish); then
  echo "stockfish not found on PATH — install it (brew install stockfish) to run the benchmark" >&2
  exit 3
fi

cd "$(dirname "$0")/.."
exec dart run tools/benchmark/uci_match.dart --stockfish "$stockfish" "$@"
