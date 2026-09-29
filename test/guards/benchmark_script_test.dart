@Tags(['guard', 'slow'])
library;

// The dev-only Stockfish benchmark (#69) must refuse to run without
// Stockfish rather than report a result it never played.

import 'package:flutter_test/flutter_test.dart';

import 'stubs.dart';

void main() {
  test('benchmark_stockfish.sh refuses without stockfish on PATH', () {
    final r = runWithStubs([tool('benchmark_stockfish.sh')]);
    expect(
      (r.exitCode, r.output.contains('stockfish not found')),
      (3, true),
      reason:
          'benchmark-refuses: without Stockfish the benchmark did not exit 3 '
          'saying "stockfish not found" (exit ${r.exitCode})\n${r.output}',
    );
  });
}
