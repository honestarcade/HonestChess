// Measures the search's speed with Master's settings, for the strength
// dial's node-budget calibration (lib/engine/strength.dart,
// `calibrationNodesPerSecond`): a 3,000,000-node search of each of the six
// Chess Programming Wiki perft positions, after a warm-up search.
//
// The app runs ahead-of-time compiled, so measure the same way:
//   dart compile exe tools/bench_search.dart -o build/bench_search
//   build/bench_search

import 'dart:io';

import 'package:honest_chess/engine/engine.dart';

import '../test/fixtures/fens.dart';

const int nodesPerPosition = 3000000;

void main() {
  const limits = SearchLimits(nodes: nodesPerPosition, exactRootScores: false);
  final positions = [
    for (final MapEntry(:key, :value) in cpwPerftFens.entries)
      if (key != 'position4-mirrored') Position.fromFen(value),
  ];
  search(positions.first, limits: const SearchLimits(nodes: 200000));

  var nodes = 0;
  final stopwatch = Stopwatch()..start();
  for (final position in positions) {
    final found = search(position, limits: limits) as Found;
    nodes += found.nodes;
    stdout.writeln(
      'depth ${found.depth}, ${found.nodes} nodes: ${position.toFen()}',
    );
  }
  final seconds = stopwatch.elapsedMicroseconds / 1e6;
  stdout.writeln(
    '$nodes nodes in ${seconds.toStringAsFixed(2)} s = '
    '${(nodes / seconds).round()} nodes/s',
  );
}
