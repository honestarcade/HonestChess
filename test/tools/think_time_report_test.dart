// The thinking-time run's positions and arithmetic (#112), which its device
// run cannot re-check: perf_test/ is built as an app, never run by
// `flutter test`.

import 'package:flutter_test/flutter_test.dart';
import 'package:honest_chess/engine/engine.dart';

import '../../perf_test/think_positions.dart';
import '../../perf_test/think_time_report.dart';

void main() {
  group('thinkPositions', () {
    test('40 positions: 15 openings, 15 middlegames, 10 endgames', () {
      int count(ThinkCategory c) =>
          thinkPositions.where((p) => p.category == c).length;
      expect(
        (
          thinkPositions.length,
          count(ThinkCategory.opening),
          count(ThinkCategory.middlegame),
          count(ThinkCategory.endgame),
        ),
        (40, 15, 15, 10),
        reason: 'think-positions: the timed set is not 15 + 15 + 10',
      );
    });

    test('none is over, has a single legal move, or repeats another', () {
      final seen = <String>{};
      for (final (i, p) in thinkPositions.indexed) {
        final game = Game.start(const TwoPlayer(), const Untimed(), fen: p.fen);
        expect(
          game.isOver,
          isFalse,
          reason: 'think-positions: $i (${p.name}) is already over',
        );
        expect(
          legalMoves(game.position).length,
          greaterThan(1),
          reason: 'think-positions: $i (${p.name}) has one legal move or none',
        );
        expect(
          seen.add(p.fen.split(' ').take(4).join(' ')),
          isTrue,
          reason: 'think-positions: $i (${p.name}) repeats an earlier one',
        );
      }
    });
  });

  group('targets', () {
    test('every target is its step\'s stated time plus 10 %', () {
      for (final step in Strength.values) {
        expect(
          targetMs(step),
          (step.settings.thinkSeconds * 1100).round(),
          reason: 'think-target: ${step.name} is not stated + 10 %',
        );
      }
      expect(
        targetMs(Strength.master),
        5500,
        reason: 'think-target: Master\'s target is not 5.5 s',
      );
    });
  });

  group('nearestRank', () {
    final hundred = [for (var i = 100; i >= 1; i--) i];

    test('p95 of 1..100 is 95, p50 is 50, p100 is the max', () {
      expect(
        (
          nearestRank(hundred, 95),
          nearestRank(hundred, 50),
          nearestRank(hundred, 100),
        ),
        (95, 50, 100),
      );
    });

    test('p95 of 40 values is the 38th smallest, never interpolated', () {
      final forty = [for (var i = 1; i <= 40; i++) i * 10];
      expect(nearestRank(forty, 95), 380);
    });

    test('an empty list or a percentile outside 1..100 is refused', () {
      expect(() => nearestRank([], 95), throwsArgumentError);
      expect(() => nearestRank([1], 0), throwsRangeError);
      expect(() => nearestRank([1], 101), throwsRangeError);
    });
  });

  group('the report', () {
    List<MoveTiming> timings(Strength step, List<int> ms) => [
      for (final (i, t) in ms.indexed)
        MoveTiming(
          step: step,
          index: i,
          ms: t,
          uci: 'e2e4',
          depth: 1,
          nodes: 1,
        ),
    ];

    test('a p95 past the target is a MISS, never ok', () {
      final r = StepReport(Strength.club, [for (var i = 0; i < 20; i++) 1101]);
      expect(r.within, isFalse);
      expect(table([r]).last, contains('MISS'));
      expect(table([r]).last, isNot(contains('ok')));
    });

    test('a p95 at the target is within it, and slower than stated', () {
      final r = StepReport(Strength.club, [for (var i = 0; i < 20; i++) 1100]);
      expect((r.within, r.vsStatedPercent), (true, 10));
      expect(table([r]).last, endsWith('  ok'));
    });

    test('a step faster than stated is logged as overstated, not failed', () {
      final r = StepReport(Strength.master, [
        for (var i = 0; i < 20; i++) 1000,
      ]);
      expect((r.within, r.vsStatedPercent), (true, -80));
      expect(table([r]).last, contains('ok, overstated'));
      expect(table([r]).last, contains('-80%'));
    });

    test('summarise reports each step it has timings for, weakest first', () {
      final reports = summarise([
        ...timings(Strength.master, [10, 20]),
        ...timings(Strength.beginner, [30]),
      ]);
      expect(
        [for (final r in reports) (r.step, r.count, r.max)],
        [(Strength.beginner, 1, 30), (Strength.master, 2, 20)],
      );
    });
  });
}
