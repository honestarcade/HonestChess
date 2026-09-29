// The result card's words and numbers (#78), as pure functions: every
// ending named in both modes, the kicker red only when you lost to the
// computer, and the stats counted from the game's history. The
// complements: an ongoing game has no result text, a two-player game
// never reads YOU WIN or YOU LOSE, and a taken-back capture is not counted.
import 'package:flutter_test/flutter_test.dart';

import 'package:honest_chess/engine/engine.dart';
import 'package:honest_chess/ui/game/result_text.dart';

const _vsWhite = VsComputer(
  playerColour: Colour.white,
  step: Strength.club,
  seed: 1,
);
const _two = TwoPlayer();

Game _played(
  List<String> ucis, {
  GameMode mode = _two,
  TimeControl control = const Untimed(),
  String? fen,
  int Function()? time,
}) {
  var game = Game.start(mode, control, fen: fen, time: time ?? () => 0);
  for (final uci in ucis) {
    final computer = switch (mode) {
      VsComputer(:final computerColour) => game.sideToMove == computerColour,
      TwoPlayer() => false,
    };
    game = game.play(Move.fromUci(game.position, uci), byComputer: computer);
  }
  return game;
}

void main() {
  group('describeResult', () {
    // The design's words (renderVals' overTitle / overBody), with the
    // discretion lines' corrections for resignation and the fifty-move
    // rule, and the two endings the design lacks.
    const wins = {
      GameEndReason.checkmate: (
        'Black delivers checkmate',
        'The king has no legal square, nothing blocks the check and the '
            'attacker cannot be taken.',
      ),
      GameEndReason.resignation: (
        'White resigned',
        'Resignation ends the game at once.',
      ),
      GameEndReason.flag: (
        'White ran out of time',
        'The clock hit zero with mating material still on the board.',
      ),
    };
    const draws = {
      GameEndReason.stalemate: (
        'Stalemate — no legal move',
        'The side to move is not in check but has no legal move at all. '
            'That is a draw, not a win.',
      ),
      GameEndReason.fiftyMoves: (
        'Draw by the fifty-move rule',
        'Fifty moves each with no capture or pawn move — the game is drawn '
            'automatically.',
      ),
      GameEndReason.insufficientMaterial: (
        'Draw — not enough material',
        'Neither side has the material to force mate, so the game is drawn '
            'on the spot.',
      ),
      GameEndReason.threefoldRepetition: (
        'Draw by repetition',
        'The same position came up three times.',
      ),
      GameEndReason.flagNoMatingMaterial: (
        'Flag fell, but no mating material',
        'The clock ran out, but the other side could never have mated. '
            'Drawn.',
      ),
      GameEndReason.resignationNoMatingMaterial: (
        'White resigned — drawn',
        'The other side had no way left to checkmate, so the game is a '
            'draw.',
      ),
      GameEndReason.agreement: (
        'Draw agreed',
        'Both players agreed to split the point.',
      ),
    };

    test('every ending is worded', () {
      expect(
        {...wins.keys, ...draws.keys},
        GameEndReason.values.toSet(),
        reason: 'result-text: an ending has no words on the card',
      );
    });

    for (final MapEntry(key: reason, value: (title, body)) in wins.entries) {
      test('a win by ${reason.name}, in both modes', () {
        final result = Win(Colour.black, reason);
        final two = describeResult(result, _two, Colour.white);
        expect(two.tag, 'BLACK WINS');
        expect(two.title, title);
        expect(two.body, body);
        expect(two.lost, isFalse, reason: 'result-text: no one "loses" 2P');

        final lost = describeResult(result, _vsWhite, Colour.white);
        expect(lost.tag, 'YOU LOSE');
        expect(lost.title, title);
        expect(lost.body, body);
        expect(lost.lost, isTrue, reason: 'result-text: the kicker turns red');

        final won = describeResult(
          result,
          const VsComputer(
            playerColour: Colour.black,
            step: Strength.club,
            seed: 1,
          ),
          Colour.black,
        );
        expect(won.tag, 'YOU WIN');
        expect(won.lost, isFalse, reason: 'result-text: a win stays teal');
      });
    }

    for (final MapEntry(key: reason, value: (title, body)) in draws.entries) {
      test('a draw by ${reason.name}, in both modes', () {
        for (final mode in [_two, _vsWhite]) {
          final text = describeResult(Draw(reason), mode, Colour.white);
          expect(text.tag, 'DRAWN');
          expect(text.title, title);
          expect(text.body, body);
          expect(text.lost, isFalse, reason: 'result-text: a draw is teal');
        }
      });
    }

    test('a drawn resignation names the side that resigned', () {
      expect(
        describeResult(
          const Draw(GameEndReason.resignationNoMatingMaterial),
          _two,
          Colour.black,
        ).title,
        'Black resigned — drawn',
      );
    });

    test('an ongoing game has no result text', () {
      expect(
        () => describeResult(const Ongoing(inCheck: false), _two, Colour.white),
        throwsArgumentError,
      );
    });
  });

  group('resultYou', () {
    test('your colour vs the computer; the side to move between two', () {
      final vsBlack = Game.start(
        const VsComputer(
          playerColour: Colour.black,
          step: Strength.club,
          seed: 1,
        ),
        const Untimed(),
      );
      expect(resultYou(vsBlack), Colour.black);
      expect(resultYou(_played(['e2e4'])), Colour.black);
      expect(resultYou(_played([])), Colour.white);
    });
  });

  group('endedByMove', () {
    test('mate yes; resignation, agreement and flag no', () {
      final mate = _played(['f2f3', 'e7e5', 'g2g4', 'd8h4']);
      expect(mate.status, const Win(Colour.black, GameEndReason.checkmate));
      expect(endedByMove(mate), isTrue);
      expect(endedByMove(_played([]).resign(Colour.white)), isFalse);
      expect(
        endedByMove(_played(['e2e4', 'e7e5']).agreeDraw()),
        isFalse,
        reason: 'result-card: an agreed draw shows at once',
      );
    });
  });

  group('resultStats', () {
    List<(String, String)> stats(Game game) => [
      for (final s in resultStats(game)) (s.label, s.value),
    ];

    test("fool's mate: 2 moves, no captures, untimed", () {
      final game = _played(['f2f3', 'e7e5', 'g2g4', 'd8h4']);
      expect(stats(game), [
        ('MOVES', '2'),
        ('CAPTURES', '0'),
        ('CLOCK', 'Untimed'),
        ('TIME LEFT', '—'),
      ]);
      expect(
        [for (final s in resultStats(game)) s.spoken],
        ['Moves, 2', 'Captures, 0', 'Clock, Untimed', 'Time left, no clock'],
      );
    });

    test('MOVES counts only White\'s moves, from a FEN with Black to move', () {
      final game = _played(
        ['e7e5', 'g1f3', 'b8c6'],
        fen: 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1',
      ).resign(Colour.white);
      expect(stats(game).first, ('MOVES', '1'));
    });

    test('CAPTURES counts both sides; a taken-back capture is gone', () {
      var game = _played(['e2e4', 'd7d5', 'e4d5', 'd8d5', 'b1c3']);
      expect(stats(game.resign(Colour.black))[1], ('CAPTURES', '2'));
      game = game.takeBack().takeBack();
      expect(game.moves.length, 3);
      expect(stats(game.resign(Colour.black))[1], (
        'CAPTURES',
        '1',
      ), reason: 'result-stats: a taken-back capture still counted');
    });

    test('LEVEL vs the computer, CLOCK names the control two-player', () {
      final vs = _played([], mode: _vsWhite).resign(Colour.white);
      expect(stats(vs)[2], ('LEVEL', 'Club'));
      expect(clockName(const Untimed()), 'Untimed');
      expect(clockName(Timed.blitz), 'Blitz 5+0');
      expect(clockName(Timed.rapid), 'Rapid 10+5');
      expect(clockName(Timed.classical), 'Classical 30+0');
      expect(clockName(Timed(15, 10)), '15+10');
    });

    test(
      'TIME LEFT: yours vs the computer, else the winner\'s or White\'s',
      () {
        var now = 0;
        int time() => now;
        // Your clock (White), though the computer's flag fell.
        final vs = _played(
          ['e2e4'],
          mode: _vsWhite,
          control: Timed(1, 0),
          time: time,
        );
        now = 60000;
        final flagged = vs.flag();
        expect(flagged.status, const Win(Colour.white, GameEndReason.flag));
        expect(stats(flagged)[3], ('TIME LEFT', '1:00'));

        // Two players: the winner's clock; White's has run 14.9 s.
        now = 0;
        final two = _played(['e2e4', 'e7e5'], control: Timed(1, 0), time: time);
        now = 14900;
        expect(stats(two.resign(Colour.white))[3], ('TIME LEFT', '1:00'));
        expect(stats(two.resign(Colour.black))[3], (
          'TIME LEFT',
          '0:46',
        ), reason: 'result-stats: two-player TIME LEFT is the winner\'s clock');
        now = 51000;
        expect(stats(two.resign(Colour.black))[3], ('TIME LEFT', '0:09.0'));

        // A draw: White's clock, 0:00 as White's flag fell.
        now = 0;
        final bare = _played(
          ['e2e3', 'e8d8'],
          fen: '4k3/8/8/8/8/8/4P3/4K3 w - - 0 1',
          control: Timed(1, 0),
          time: time,
        );
        now = 60000;
        final draw = bare.flag();
        expect(draw.status, const Draw(GameEndReason.flagNoMatingMaterial));
        expect(stats(draw)[3], ('TIME LEFT', '0:00'));
        expect(resultStats(draw)[3].spoken, 'Time left, 0 seconds');
      },
    );
  });
}
