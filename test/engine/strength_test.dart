// The strength dial's behaviour: the owner-approved descriptions, mate in
// one at every step, the depth floor, seeded self-play, fresh seeds per game,
// and the computer's answer to a draw offer. The invariant 4 guard is
// test/guards/strength_honesty_test.dart.

import 'package:flutter_test/flutter_test.dart';
import 'package:honest_chess/engine/engine.dart';
import 'package:honest_chess/engine/splitmix.dart';

Position _fen(String fen) => Position.fromFen(fen);

ComputerMove _choose(
  Position position,
  Strength step,
  int seed, {
  int? nodeBudget,
  List<int> history = const [],
  ShouldStop? shouldStop,
}) => chooseMove(
  position,
  step,
  seed,
  nodeBudget: nodeBudget,
  history: history,
  shouldStop: shouldStop,
  table: TranspositionTable(megabytes: 1),
)!;

bool _mates(Position position, Move move) =>
    status([position, play(position, move)]) is Win;

/// Positions where the side to move has a mate in one.
const _mateInOne = [
  '6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1', // Ra8#
  'r5k1/5ppp/8/8/8/8/5PPP/6K1 b - - 0 1', // ...Ra1#
  '6rk/6pp/8/6N1/8/8/8/6K1 w - - 0 1', // Nf7#
  '7k/8/5K2/8/8/8/8/6Q1 w - - 0 1', // Qg7#
];

/// Positions where winning the hanging queen lets the opponent mate on the
/// back rank at once, and [_blunders] names that capture.
const _walkInto = [
  '1r4k1/q4ppp/8/8/8/8/5PPP/R5K1 w - - 0 1',
  'r5k1/5ppp/8/8/8/8/Q4PPP/1R4K1 b - - 0 1',
];
const _blunders = ['a1a7', 'a8a2'];

final _seeds = [0, 1, 2, 3, 42, -1, 0x7fffffffffffffff, 0x0123456789abcdef];

final _owner = {
  Strength.beginner:
      'Looks one move ahead and chooses loosely. It will miss threats — even '
      'mate in one — and hand you pieces.',
  Strength.casual:
      'Looks two moves ahead, a little loosely. Sees direct threats, misses '
      'short combinations.',
  Strength.club:
      'Looks three moves ahead and chooses carefully. Punishes loose pieces '
      'and short tactics.',
  Strength.strong:
      'Looks five moves ahead with no looseness. You will need a plan.',
  Strength.master:
      'Thinks deeply — up to about five seconds — with nothing held back.',
};

Game _vsComputer(String fen, List<String> uci, {Colour player = Colour.white}) {
  var game = Game.start(
    VsComputer(playerColour: player, step: Strength.club, seed: 7),
    const Untimed(),
    fen: fen,
    time: () => 0,
  );
  for (final text in uci) {
    final byComputer = game.sideToMove != player;
    game = game.play(Move.fromUci(game.position, text), byComputer: byComputer);
  }
  return game;
}

void main() {
  test('the five descriptions are exactly the owner-approved text', () {
    expect(Strength.values, hasLength(5));
    for (final step in Strength.values) {
      expect(
        step.description,
        _owner[step],
        reason: 'strength: ${step.name} description is not the approved text',
      );
    }
  });

  test('the node budgets follow the calibration rule', () {
    expect(calibratedNodeBudget(0.3), 92000);
    expect(calibratedNodeBudget(5), 1500000);
    expect(
      [for (final step in Strength.values) step.settings.thinkSeconds],
      [0.3, 0.6, 1, 2, 5],
    );
  });

  group('mate in one', () {
    for (final step in Strength.values.where((s) => s.settings.seesMateInOne)) {
      test('${step.name} always takes a mate in one', () {
        for (final fen in _mateInOne) {
          for (final seed in _seeds) {
            final move = _choose(_fen(fen), step, seed).move;
            expect(
              _mates(_fen(fen), move),
              isTrue,
              reason: '${step.name} seed $seed played $move in $fen',
            );
          }
        }
      });

      test('${step.name} never plays into a mate in one', () {
        for (final (i, fen) in _walkInto.indexed) {
          for (final seed in step.settings.noiseCp > 0 ? _seeds : [0]) {
            final move = _choose(_fen(fen), step, seed).move;
            expect(
              move.toUci(),
              isNot(_blunders[i]),
              reason: '${step.name} seed $seed walked into mate in $fen',
            );
          }
        }
      }, tags: step == Strength.master ? ['slow'] : null);
    }

    test('beginner can miss a mate in one, and can play into one', () {
      final missed = [
        for (final fen in _mateInOne)
          for (final seed in _seeds)
            if (!_mates(
              _fen(fen),
              _choose(_fen(fen), Strength.beginner, seed).move,
            ))
              '$fen/$seed',
      ];
      expect(missed, isNotEmpty);
      final walked = [
        for (final (i, fen) in _walkInto.indexed)
          for (final seed in _seeds)
            if (_choose(_fen(fen), Strength.beginner, seed).move.toUci() ==
                _blunders[i])
              '$fen/$seed',
      ];
      expect(walked, isNotEmpty);
    });

    test('every step but beginner finishes two plies, even when out of '
        'nodes and time', () {
      final position = _fen(_walkInto.first);
      for (final step in Strength.values) {
        final result = _choose(
          position,
          step,
          0,
          nodeBudget: 1,
          shouldStop: () => StopReason.deadline,
        );
        expect(
          result.search.depth,
          step.settings.seesMateInOne ? greaterThanOrEqualTo(2) : 1,
          reason: step.name,
        );
        if (step.settings.seesMateInOne) {
          expect(result.move.toUci(), isNot(_blunders.first));
        }
      }
    });

    test('a cancelled search chooses nothing', () {
      expect(
        chooseMove(
          Position.initial(),
          Strength.master,
          0,
          shouldStop: () => StopReason.cancel,
          table: TranspositionTable(megabytes: 1),
        ),
        isNull,
      );
    });
  });

  group('seeded play', () {
    List<String> selfPlay(Strength step, int seed, {int? nodeBudget}) {
      final positions = [Position.initial()];
      final moves = <String>[];
      while (moves.length < 40 && !status(positions).isOver) {
        final chosen = _choose(
          positions.last,
          step,
          seed,
          nodeBudget: nodeBudget,
          history: [
            for (final p in positions.take(positions.length - 1)) p.key,
          ],
        ).move;
        moves.add(chosen.toUci());
        positions.add(play(positions.last, chosen));
      }
      return moves;
    }

    test('the same seed gives the same 20-move self-play', () {
      for (final step in [Strength.beginner, Strength.casual]) {
        expect(selfPlay(step, 99), selfPlay(step, 99), reason: step.name);
      }
      expect(
        selfPlay(Strength.club, 5, nodeBudget: 3000),
        selfPlay(Strength.club, 5, nodeBudget: 3000),
      );
    });

    test('different seeds diverge at beginner', () {
      expect(
        selfPlay(Strength.beginner, 1),
        isNot(selfPlay(Strength.beginner, 2)),
      );
    });

    test('the noise stays within ±N and reaches both ends', () {
      final position = Position.initial();
      final move = legalMoves(position).first;
      final values = {
        for (var seed = 0; seed < 4000; seed++)
          rootNoise(seed, position.key, move, 3),
      };
      expect(values, {-3, -2, -1, 0, 1, 2, 3});
      expect(rootNoise(1, position.key, move, 0), 0);
    });

    test('the noise ignores the move counters', () {
      final a = _fen('4k3/8/8/8/8/8/4P3/4K3 w - - 0 1');
      final b = _fen('4k3/8/8/8/8/8/4P3/4K3 w - - 37 90');
      for (final move in legalMoves(a)) {
        expect(rootNoise(9, a.key, move, 200), rootNoise(9, b.key, move, 200));
      }
    });

    test('SplitMix64 bounded draws refuse an impossible bound', () {
      expect(() => SplitMix64(0).nextBelow(0), throwsRangeError);
      expect(() => SplitMix64(0).nextBelow((1 << 32) + 1), throwsRangeError);
    });
  });

  group('game seeds', () {
    test('two new games get different seeds', () {
      final a = VsComputer.newGame(
        playerColour: Colour.white,
        step: Strength.club,
      );
      final b = VsComputer.newGame(
        playerColour: Colour.white,
        step: Strength.club,
      );
      expect(a.seed, isNot(b.seed));
      expect(newGameSeed(), isNot(newGameSeed()));
    });

    test('a restored game keeps its seed', () {
      for (final seed in [newGameSeed(), -1, 1 << 63, 0x7fffffffffffffff]) {
        final game = Game.start(
          VsComputer(
            playerColour: Colour.black,
            step: Strength.beginner,
            seed: seed,
          ),
          const Untimed(),
          time: () => 0,
        );
        final restored = Game.fromJson(game.toJson(), time: () => 0);
        expect((restored.mode as VsComputer).seed, seed);
      }
    });
  });

  group('draw offers', () {
    const blackUpAQueen =
        'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNB1KBNR w KQkq '
        '- 0 1';
    const whiteUpAQueen =
        'rnb1kbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq '
        '- 0 1';

    test('a computer clearly ahead declines, on either side to move', () {
      // The computer is Black, a queen up; the player (White) to move.
      expect(
        acceptsDraw(_vsComputer(blackUpAQueen, ['g1f3', 'g8f6'])),
        isFalse,
      );
      // The computer to move.
      expect(
        acceptsDraw(_vsComputer(blackUpAQueen, ['g1f3', 'g8f6', 'b1c3'])),
        isFalse,
      );
    });

    test('a level or losing computer accepts', () {
      expect(
        acceptsDraw(_vsComputer(Position.initialFen, ['e2e4', 'e7e5'])),
        isTrue,
      );
      expect(acceptsDraw(_vsComputer(whiteUpAQueen, ['g1f3', 'g8f6'])), isTrue);
    });

    test('the same rule at every step', () {
      final game = _vsComputer(blackUpAQueen, ['g1f3', 'g8f6']);
      for (final step in Strength.values) {
        final json = game.toJson();
        (json['options']! as Map<String, Object?>)['step'] = step.name;
        expect(acceptsDraw(Game.fromJson(json, time: () => 0)), isFalse);
      }
    });

    test('refused when the rules refuse an offer', () {
      expect(
        () => acceptsDraw(_vsComputer(Position.initialFen, ['e2e4'])),
        throwsStateError,
      );
      final over = _vsComputer(Position.initialFen, [
        'f2f3', 'e7e5', 'g2g4', 'd8h4', //
      ]);
      expect(over.isOver, isTrue);
      expect(() => acceptsDraw(over), throwsStateError);
      final twoPlayer = Game.start(
        const TwoPlayer(),
        const Untimed(),
        time: () => 0,
      ).play(Move.fromUci(Position.initial(), 'e2e4'));
      expect(() => acceptsDraw(twoPlayer), throwsArgumentError);
    });
  });
}
