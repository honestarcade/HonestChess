// The Stockfish benchmark's arithmetic and notation (tools/benchmark/),
// which its one long run cannot be re-checked against.

import 'package:flutter_test/flutter_test.dart';
import 'package:honest_chess/engine/engine.dart';

import '../../tools/benchmark/elo.dart';
import '../../tools/benchmark/uci_match.dart';

void main() {
  group('fitElo', () {
    test('an even score against one level is that level', () {
      final fit = fitElo([const LevelScore(1800, 60, 30)]) as Estimate;
      expect(fit.elo, closeTo(1800, 0.01));
      expect(fit.low, lessThan(1800));
      expect(fit.high, greaterThan(1800));
      expect(fit.high - 1800, closeTo(1800 - fit.low, 0.01));
    });

    test('one level alone agrees with its performance rating', () {
      const score = LevelScore(1600, 60, 45);
      final fit = fitElo([score]) as Estimate;
      expect(fit.elo, closeTo(score.performance!, 0.01));
      expect(fit.elo, closeTo(1600 + 400 * 0.4771212547, 0.01));
    });

    test('more games narrow the interval', () {
      final few = fitElo([const LevelScore(1800, 20, 10)]) as Estimate;
      final many = fitElo([const LevelScore(1800, 180, 90)]) as Estimate;
      expect(many.high - many.low, lessThan(few.high - few.low));
    });

    test('the fit sits between the levels it scored across', () {
      final fit = fitElo(const [
        LevelScore(1600, 60, 50),
        LevelScore(1800, 60, 33),
        LevelScore(2000, 60, 15),
      ]) as Estimate;
      expect(fit.elo, inInclusiveRange(1800, 1900));
    });

    test('all won or all lost gives only a bound, never a number', () {
      final won = fitElo(const [
        LevelScore(1600, 60, 60),
        LevelScore(2000, 60, 60),
      ]);
      expect(won, isA<EloBound>().having((b) => b.above, 'above', isTrue));
      expect((won as EloBound).level, 2000);
      final lost = fitElo(const [LevelScore(1600, 60, 0)]);
      expect(lost, isA<EloBound>().having((b) => b.above, 'above', isFalse));
      expect(const LevelScore(1600, 60, 60).performanceText, 'above 1600');
      expect(const LevelScore(1600, 60, 0).performance, isNull);
    });
  });

  group('chainElo', () {
    test('adds the difference to the anchor and widens the interval', () {
      const anchor = Estimate(1000, 900, 1100);
      const difference = Estimate(-300, -400, -200);
      final chained = chainElo(anchor, difference);
      expect(chained.elo, closeTo(700, 0.01));
      // Two equal margins of 100 combine to 100 * sqrt(2).
      expect(chained.high - chained.elo, closeTo(141.42, 0.01));
      expect(chained.elo - chained.low, closeTo(141.42, 0.01));
    });

    test("an exact anchor leaves the difference's interval alone", () {
      final chained = chainElo(
        const Estimate(1320, 1320, 1320),
        const Estimate(-100, -180, -20),
      );
      expect((chained.low, chained.high), (1140, 1300));
    });
  });

  group('targetVerdict', () {
    test('met only when the target is inside the interval', () {
      expect(
        targetVerdict(const Estimate(650, 500, 800), 600),
        startsWith('met'),
      );
      expect(
        targetVerdict(const Estimate(900, 850, 950), 600),
        'missed: the estimate is 300 above 600, outside its interval.',
      );
      expect(
        targetVerdict(const Estimate(400, 350, 450), 600),
        'missed: the estimate is 200 below 600, outside its interval.',
      );
      expect(
        targetVerdict(const EloBound(above: false, level: 1320), 600),
        startsWith('not measured'),
      );
    });
  });

  group('san', () {
    String sanOf(String fen, String uci) {
      final position = Position.fromFen(fen);
      return san(position, Move.fromUci(position, uci));
    }

    test('pawn moves, captures and promotions', () {
      expect(sanOf(Position.initialFen, 'e2e4'), 'e4');
      expect(
        sanOf(
          'rnbqkbnr/ppp1pppp/8/3p4/4P3/8/PPPP1PPP/RNBQKBNR w KQkq d6 0 2',
          'e4d5',
        ),
        'exd5',
      );
      expect(sanOf('8/P6k/8/8/8/8/8/K7 w - - 0 1', 'a7a8q'), 'a8=Q');
      expect(sanOf('k7/8/8/3pP3/8/8/8/K7 w - d6 0 1', 'e5d6'), 'exd6');
    });

    test('castling, check, mate and disambiguation', () {
      expect(sanOf('r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1', 'e1g1'), 'O-O');
      expect(sanOf('r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1', 'e1c1'), 'O-O-O');
      expect(sanOf('4k3/8/8/8/8/8/8/R3K2R w KQ - 0 1', 'a1a8'), 'Ra8+');
      expect(sanOf('6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1', 'a1a8'), 'Ra8#');
      expect(sanOf('1k6/8/8/8/8/8/8/R4RK1 w - - 0 1', 'a1d1'), 'Rad1');
      expect(sanOf('4k3/8/8/R7/8/8/8/R3K3 w - - 0 1', 'a1a3'), 'R1a3');
      expect(sanOf('4k3/8/8/8/8/2N3N1/8/4K3 w - - 0 1', 'c3e2'), 'Nce2');
    });
  });
}
