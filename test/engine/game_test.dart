// A game played through `Game`: moving and turn refusal, takeback in both
// modes with the position, clocks and repetition history restored, the
// flag, resignation and agreed draws — each with the complement that must
// not happen.

import 'package:flutter_test/flutter_test.dart';
import 'package:honest_chess/engine/engine.dart';

const white = Colour.white, black = Colour.black;
const minute = 60000;

/// A hand-wound monotonic time source.
class FakeTime {
  int ms = 0;
  int call() => ms;
  void advance(int by) => ms += by;
}

const twoPlayer = TwoPlayer();
const vsAsWhite = VsComputer(
  playerColour: white,
  step: Strength.club,
  seed: 0x0123456789abcdef,
);
const vsAsBlack = VsComputer(
  playerColour: black,
  step: Strength.beginner,
  seed: 42,
);

Game _start(
  GameMode mode, {
  TimeControl control = const Untimed(),
  GameOptions options = const GameOptions(),
  String? fen,
  FakeTime? time,
}) => Game.start(
  mode,
  control,
  options: options,
  fen: fen,
  time: (time ?? FakeTime()).call,
);

/// [game] after the moves in [ucis], alternating between the player and the
/// computer against the computer.
Game _play(Game game, List<String> ucis) {
  for (final uci in ucis) {
    final byComputer = switch (game.mode) {
      VsComputer(:final computerColour) => game.sideToMove == computerColour,
      TwoPlayer() => false,
    };
    game = game.play(Move.fromUci(game.position, uci), byComputer: byComputer);
  }
  return game;
}

Matcher _refused(GameRefusal reason) =>
    throwsA(isA<GameActionError>().having((e) => e.reason, 'reason', reason));

const _knightShuffle = ['g1f3', 'g8f6', 'f3g1', 'f6g8'];

void main() {
  group('start', () {
    test('a new game is the starting position, ongoing, nothing played', () {
      final game = _start(twoPlayer);
      expect(game.position, Position.initial());
      expect(game.history, hasLength(1));
      expect(game.history.single.move, isNull);
      expect(game.moves, isEmpty);
      expect(game.status, const Ongoing(inCheck: false));
      expect(game.isOver, isFalse);
      expect(game.sideToMove, white);
      expect(game.options.takebackAllowed, isTrue);
      expect(game.clock.phase, ClockPhase.notStarted);
      expect(game.canTakeBack, isFalse);
      expect(game.canAgreeDraw, isFalse);
    });

    test('a custom FEN is the starting position, over if already mate', () {
      const fen = '4k3/8/8/8/8/8/8/R3K3 b - - 0 1';
      expect(_start(twoPlayer, fen: fen).position.toFen(), fen);
      expect(_start(twoPlayer, fen: fen).sideToMove, black);
      final mated = _start(twoPlayer, fen: '7k/6Q1/6K1/8/8/8/8/8 b - - 0 1');
      expect(mated.status, const Win(white, GameEndReason.checkmate));
      expect(
        () => mated.play(Move.fromUci(Position.initial(), 'e2e4')),
        _refused(GameRefusal.gameOver),
      );
    });
  });

  group('moving', () {
    test('play records the move, the position and the status', () {
      final game = _play(_start(twoPlayer), ['e2e4', 'e7e5']);
      expect(game.moves.map((m) => m.toUci()), ['e2e4', 'e7e5']);
      expect(game.history, hasLength(3));
      expect(
        game.position.toFen(),
        'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq e6 0 2',
      );
      expect(game.sideToMove, white);
    });

    test('checkmate ends the game and stops the clock', () {
      final time = FakeTime();
      var game = _start(twoPlayer, control: Timed.blitz, time: time);
      for (final uci in ['f2f3', 'e7e5', 'g2g4']) {
        time.advance(1000);
        game = _play(game, [uci]);
      }
      time.advance(1000);
      game = _play(game, ['d8h4']);
      expect(game.status, const Win(black, GameEndReason.checkmate));
      expect(game.history.last.status, game.status);
      expect(game.clock.phase, ClockPhase.ended);
    });

    test('moving after the end is refused', () {
      final mated = _play(_start(twoPlayer), ['f2f3', 'e7e5', 'g2g4', 'd8h4']);
      expect(mated.isOver, isTrue);
      final anyMove = Move.fromUci(Position.initial(), 'e2e4');
      expect(() => mated.play(anyMove), _refused(GameRefusal.gameOver));

      final resigned = _start(twoPlayer).resign(white);
      expect(
        () => resigned.play(Move.fromUci(resigned.position, 'e2e4')),
        _refused(GameRefusal.gameOver),
        reason: 'game: a resigned game takes no more moves',
      );
    });

    test('moving the side not to move is refused', () {
      final game = _start(twoPlayer);
      final blackMove = Move.fromUci(
        Position.fromFen(
          'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR b KQkq - 0 1',
        ),
        'e7e5',
      );
      expect(() => game.play(blackMove), _refused(GameRefusal.notYourTurn));
      expect(game.history, hasLength(1), reason: 'game: no move was added');
    });

    test('an illegal move is refused', () {
      final game = _start(twoPlayer);
      final kingside = Move.fromUci(
        Position.fromFen('4k3/8/8/8/8/8/8/4K2R w K - 0 1'),
        'e1g1',
      );
      expect(() => game.play(kingside), _refused(GameRefusal.illegalMove));
    });

    test('against the computer each side acts only on its own turn', () {
      final game = _start(vsAsWhite);
      final e4 = Move.fromUci(game.position, 'e2e4');
      expect(
        () => game.play(e4, byComputer: true),
        _refused(GameRefusal.notYourTurn),
        reason: 'game: the computer may not move the player\'s colour',
      );
      final afterE4 = game.play(e4);
      final e5 = Move.fromUci(afterE4.position, 'e7e5');
      expect(
        () => afterE4.play(e5),
        _refused(GameRefusal.notYourTurn),
        reason: 'game: the player may not move the computer\'s colour',
      );
      expect(afterE4.play(e5, byComputer: true).moves, hasLength(2));
      expect(
        () => _start(twoPlayer).play(e4, byComputer: true),
        throwsArgumentError,
      );
    });

    test('an action leaves the game it was called on unchanged', () {
      final before = _play(_start(twoPlayer), ['e2e4']);
      final snapshot = [...before.history];
      _play(before, ['e7e5']);
      before.resign(white);
      before.takeBack();
      expect(before.history, snapshot);
      expect(before.status, const Ongoing(inCheck: false));
    });

    test('a threefold repetition draws', () {
      final game = _play(_start(twoPlayer), [
        ..._knightShuffle,
        ..._knightShuffle,
      ]);
      expect(game.status, const Draw(GameEndReason.threefoldRepetition));
    });
  });

  group('two-player takeback', () {
    test('undoes one ply, restoring the FEN and the clocks', () {
      final time = FakeTime();
      var game = _start(twoPlayer, control: Timed.blitz, time: time);
      time.advance(1000);
      game = _play(game, ['e2e4']);
      time.advance(5000);
      game = _play(game, ['e7e5']);
      final beforeNf3 = game.position.toFen();
      time.advance(3000);
      game = _play(game, ['g1f3']);
      expect(game.remaining(white), 5 * minute - 3000);
      time.advance(11000);

      game = game.takeBack();
      expect(game.position.toFen(), beforeNf3);
      expect(game.moves.map((m) => m.toUci()), ['e2e4', 'e7e5']);
      expect(game.sideToMove, white);
      expect(game.remaining(white), 5 * minute);
      expect(game.remaining(black), 5 * minute - 5000);
      expect(game.clock.phase, ClockPhase.paused);
      time.advance(60000);
      expect(
        game.remaining(white),
        5 * minute,
        reason: 'game: a clock restored by takeback stays paused',
      );
      game = _play(game, ['g1f3']);
      expect(
        game.remaining(white),
        5 * minute,
        reason: 'game: the paused interval is not charged to the mover',
      );
      expect(game.clock.phase, ClockPhase.running);
    });

    test('restores the repetition history: an undone occurrence no longer '
        'counts', () {
      var game = _play(_start(twoPlayer), _knightShuffle);
      expect(
        isSamePosition(game.position, Position.initial()),
        isTrue,
        reason: 'game: the starting position has occurred twice',
      );
      game = game.takeBack();
      game = _play(game, ['f6g8']);
      expect(
        game.status,
        const Ongoing(inCheck: false),
        reason:
            'game: the occurrence undone by takeback must not count '
            'towards threefold',
      );
      game = _play(game, _knightShuffle);
      expect(game.status, const Draw(GameEndReason.threefoldRepetition));
    });

    test('restores the halfmove clock', () {
      var game = _play(_start(twoPlayer), ['g1f3', 'g8f6']);
      expect(game.position.halfmoveClock, 2);
      game = _play(game, ['e2e4']);
      expect(game.position.halfmoveClock, 0);
      expect(game.takeBack().position.halfmoveClock, 2);
    });

    test('re-opens a game ended by a move, and can go back to the start', () {
      var game = _play(_start(twoPlayer), ['f2f3', 'e7e5', 'g2g4', 'd8h4']);
      game = game.takeBack();
      expect(game.isOver, isFalse);
      expect(game.sideToMove, black);
      for (var i = 0; i < 3; i++) {
        game = game.takeBack();
      }
      expect(game.position, Position.initial());
      expect(game.canTakeBack, isFalse);
      expect(game.takeBack, _refused(GameRefusal.nothingToTakeBack));
    });

    test('with no moves is refused', () {
      expect(
        _start(twoPlayer).takeBack,
        _refused(GameRefusal.nothingToTakeBack),
      );
    });

    test('is refused when the game turned it off', () {
      final game = _play(
        _start(twoPlayer, options: const GameOptions(takebackAllowed: false)),
        ['e2e4'],
      );
      expect(game.canTakeBack, isFalse);
      expect(game.takeBack, _refused(GameRefusal.takebackDisabled));
      expect(
        game.resign(white).takeBack,
        _refused(GameRefusal.takebackDisabled),
        reason: 'game: a disabled takeback cannot re-open a resignation',
      );
    });
  });

  group('takeback against the computer', () {
    test('after the computer replied, undoes both plies', () {
      final game = _play(_start(vsAsWhite), ['e2e4', 'e7e5', 'g1f3', 'b8c6']);
      final back = game.takeBack();
      expect(back.moves.map((m) => m.toUci()), ['e2e4', 'e7e5']);
      expect(back.sideToMove, white, reason: 'game: back to the player');
    });

    test('while the computer is thinking, undoes the player\'s move', () {
      final game = _play(_start(vsAsWhite), ['e2e4', 'e7e5', 'g1f3']);
      final back = game.takeBack();
      expect(back.moves.map((m) => m.toUci()), ['e2e4', 'e7e5']);
      expect(back.sideToMove, white);
    });

    test('the player\'s first move goes back to the start', () {
      expect(
        _play(_start(vsAsWhite), ['e2e4', 'e7e5']).takeBack().position,
        Position.initial(),
      );
    });

    test('only the computer\'s opening move cannot be taken back', () {
      final game = _play(_start(vsAsBlack), ['e2e4']);
      expect(game.canTakeBack, isFalse);
      expect(game.takeBack, _refused(GameRefusal.nothingToTakeBack));
      final later = _play(game, ['e7e5', 'g1f3']);
      final back = later.takeBack();
      expect(back.moves.map((m) => m.toUci()), ['e2e4']);
      expect(back.sideToMove, black);
    });
  });

  group('flag', () {
    test('a fallen flag ends the game; play checks it first', () {
      final time = FakeTime();
      var game = _start(twoPlayer, control: Timed.blitz, time: time);
      game = _play(game, ['e2e4']);
      time.advance(5 * minute - 1);
      expect(game.flag(), same(game), reason: 'game: 1 ms is still left');
      time.advance(1);
      final flagged = game.flag();
      expect(flagged.status, const Win(white, GameEndReason.flag));
      final late = game.play(Move.fromUci(game.position, 'e7e5'));
      expect(late.status, const Win(white, GameEndReason.flag));
      expect(
        late.moves,
        hasLength(1),
        reason: 'game: a move after the flag fell is not played',
      );
    });

    test('with no mating material for the opponent, draws', () {
      final time = FakeTime();
      var game = _start(
        twoPlayer,
        control: Timed(1, 0),
        fen: '4k3/8/8/8/8/8/4P3/4K3 b - - 0 1',
        time: time,
      );
      game = _play(game, ['e8d8']);
      time.advance(minute);
      expect(
        game.flag().status,
        const Draw(GameEndReason.flagNoMatingMaterial),
      );
    });

    test('re-opening a flagged game restores the previous ply\'s clock', () {
      final time = FakeTime();
      var game = _start(twoPlayer, control: Timed.blitz, time: time);
      game = _play(game, ['e2e4']);
      time.advance(5 * minute);
      game = game.flag();
      expect(game.isOver, isTrue);
      game = game.takeBack();
      expect(game.isOver, isFalse);
      expect(game.moves, hasLength(1), reason: 'game: no ply was undone');
      expect(game.remaining(black), 5 * minute);
      expect(game.clock.phase, ClockPhase.paused);
    });
  });

  group('resignation', () {
    test('is a loss for the resigner, whoever is to move', () {
      final game = _play(_start(twoPlayer), ['e2e4']);
      expect(
        game.resign(white).status,
        const Win(black, GameEndReason.resignation),
      );
      expect(
        game.resign(black).status,
        const Win(white, GameEndReason.resignation),
      );
      expect(game.resign(white).history, game.history);
    });

    test('the side with only a bare king opposite draws by resigning', () {
      final game = _start(twoPlayer, fen: '4k3/8/8/8/8/8/4P3/4K3 w - - 0 1');
      expect(
        game.resign(white).status,
        const Draw(GameEndReason.resignationNoMatingMaterial),
        reason: 'game: black has only a king, so cannot win by resignation',
      );
      expect(
        game.resign(black).status,
        const Win(white, GameEndReason.resignation),
      );
    });

    test('the computer never resigns; the player may', () {
      final game = _start(vsAsWhite);
      expect(
        () => game.resign(black),
        _refused(GameRefusal.computerNeverResigns),
      );
      expect(
        game.resign(white).status,
        const Win(black, GameEndReason.resignation),
      );
    });

    test('on a finished game is refused', () {
      final game = _start(twoPlayer).resign(white);
      expect(() => game.resign(black), _refused(GameRefusal.gameOver));
      expect(game.agreeDraw, _refused(GameRefusal.gameOver));
    });

    test('takeback re-opens a resigned game; a second undoes a ply', () {
      var game = _play(_start(twoPlayer), ['e2e4']).resign(black);
      game = game.takeBack();
      expect(game.isOver, isFalse);
      expect(game.moves, hasLength(1), reason: 'game: no ply was undone');
      game = game.takeBack();
      expect(game.moves, isEmpty);
    });
  });

  group('agreed draw', () {
    test('before both sides have moved is refused', () {
      final start = _start(twoPlayer);
      expect(start.canAgreeDraw, isFalse);
      expect(start.agreeDraw, _refused(GameRefusal.drawTooEarly));
      final afterWhite = _play(start, ['e2e4']);
      expect(afterWhite.canAgreeDraw, isFalse);
      expect(
        afterWhite.agreeDraw,
        _refused(GameRefusal.drawTooEarly),
        reason: 'game: black has not moved yet',
      );
    });

    test('once each side has moved, draws by agreement', () {
      final game = _play(_start(twoPlayer), ['e2e4', 'e7e5']);
      expect(game.canAgreeDraw, isTrue);
      final drawn = game.agreeDraw();
      expect(drawn.status, const Draw(GameEndReason.agreement));
      expect(drawn.history, game.history);
      expect(drawn.canAgreeDraw, isFalse);
    });

    test('counts moves from a custom FEN with black to move', () {
      final game = _play(
        _start(twoPlayer, fen: '4k3/8/8/8/8/8/4P3/4K3 b - - 0 1'),
        ['e8d8'],
      );
      expect(game.agreeDraw, _refused(GameRefusal.drawTooEarly));
      expect(
        _play(game, ['e1d1']).agreeDraw().status,
        const Draw(GameEndReason.agreement),
      );
    });
  });

  group('modes', () {
    test('compare by value', () {
      expect(
        const VsComputer(playerColour: white, step: Strength.club, seed: 1),
        const VsComputer(playerColour: white, step: Strength.club, seed: 1),
      );
      expect(
        const VsComputer(playerColour: white, step: Strength.club, seed: 1),
        isNot(
          const VsComputer(playerColour: white, step: Strength.club, seed: 2),
        ),
      );
      expect(vsAsWhite.computerColour, black);
      expect(Strength.values.map((s) => s.name), [
        'beginner',
        'casual',
        'club',
        'strong',
        'master',
      ]);
    });
  });
}
