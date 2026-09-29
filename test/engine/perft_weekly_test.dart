@Tags(['weekly'])
library;

// One ply deeper than the pull-request perft guard
// (test/guards/perft_test.dart), each at most 20 M nodes. Counts from
// https://www.chessprogramming.org/Perft_Results (read 2026-09-28).

import 'package:flutter_test/flutter_test.dart';
import 'package:honest_chess/engine/engine.dart';

import '../fixtures/fens.dart';

/// Position name in `cpwPerftFens` → (depth, published node count).
const weeklyDepths = {
  'initial': (5, 4865609),
  'kiwipete': (4, 4085603),
  'position3': (6, 11030083),
  'position4': (5, 15833292),
  'position4-mirrored': (5, 15833292),
  'position5': (4, 2103487),
  'position6': (4, 3894594),
};

void main() {
  for (final MapEntry(key: name, value: (depth, nodes))
      in weeklyDepths.entries) {
    test('perft($name, $depth) == $nodes', () {
      final counted = perft(Position.fromFen(cpwPerftFens[name]!), depth);
      expect(
        counted,
        nodes,
        reason:
            'perft-weekly: $name at depth $depth counted $counted, published $nodes',
      );
    }, timeout: const Timeout(Duration(minutes: 5)));
  }
}
