@Tags(['guard', 'slow'])
library;

// Invariant 3 (CLAUDE.md): move generation matches the published perft
// counts on the standard reference positions, on every pull request. Deeper
// counts run weekly: test/engine/perft_weekly_test.dart.
//
// Counts from the Chess Programming Wiki's "Perft Results" page,
// https://www.chessprogramming.org/Perft_Results (read 2026-09-28).
//
// Depths: this file ran in 1.3 s wall clock, test startup included, on an
// Apple M3 Max, measured 2026-09-28 with
// `time flutter test --no-pub test/guards/perft_test.dart` — far inside the
// ~30 s the plan allows the pull-request gate. What holds them here instead
// is the weekly tier: one ply deeper each, and that must stay at most 20 M
// nodes per position.

import 'package:flutter_test/flutter_test.dart';
import 'package:honest_chess/engine/engine.dart';

import '../fixtures/fens.dart';

/// Position name in `cpwPerftFens` → (depth, published node count).
const prDepths = {
  'initial': (4, 197281),
  'kiwipete': (3, 97862),
  'position3': (5, 674624),
  'position4': (4, 422333),
  'position4-mirrored': (4, 422333),
  'position5': (3, 62379),
  'position6': (3, 89890),
};

void main() {
  for (final MapEntry(key: name, value: (depth, nodes)) in prDepths.entries) {
    test('perft($name, $depth) == $nodes', () {
      final counted = perft(Position.fromFen(cpwPerftFens[name]!), depth);
      expect(
        counted,
        nodes,
        reason:
            'perft: $name at depth $depth counted $counted, published $nodes',
      );
    }, timeout: const Timeout(Duration(minutes: 2)));
  }
}
