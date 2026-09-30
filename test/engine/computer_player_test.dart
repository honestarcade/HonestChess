// The computer thinking on its worker isolate: the move it answers is the
// one `chooseMove` gives inline, the thinking state follows each request, a
// cancelled request never yields a move, and a timed game's clock caps the
// search. One test is the invariant 4 guard, reasons starting
// `computer-isolate:` — the search never runs in the caller's isolate.

import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:honest_chess/engine/engine.dart';

const _guard = ['guard'];
const white = Colour.white, black = Colour.black;

/// A hand-wound monotonic time source.
class FakeTime {
  int ms = 0;
  int call() => ms;
}

/// Small budgets keep these tests quick; the worker runs the same
/// `chooseMove` at any budget.
const _budget = 20000;

const _seed = 0x5eed;

VsComputer _vs(Strength step, {Colour player = white}) =>
    VsComputer(playerColour: player, step: step, seed: _seed);

/// [game] after [ucis], each played by whoever is to move.
Game _play(Game game, List<String> ucis) {
  for (final uci in ucis) {
    final mode = game.mode;
    game = game.play(
      Move.fromUci(game.position, uci),
      byComputer: mode is VsComputer && game.sideToMove == mode.computerColour,
    );
  }
  return game;
}

Future<Moved> _moved(Future<MoveResult> result) async {
  final answer = await result;
  expect(answer, isA<Moved>());
  return answer as Moved;
}

void main() {
  test('the search runs on the worker isolate, never the caller\'s', () async {
    final player = ComputerPlayer(Strength.club, _seed, nodeBudget: _budget);
    addTearDown(player.dispose);
    final game = _play(Game.start(_vs(Strength.club), const Untimed()), [
      'e2e4',
    ]);
    final moved = await _moved(player.chooseMove(game));
    expect(
      moved.debugSearchIsolate,
      isNotNull,
      reason:
          'computer-isolate: the reply did not say which isolate searched '
          '(the debug-build identity is missing)',
    );
    expect(
      moved.debugSearchIsolate,
      isNot(Isolate.current.controlPort),
      reason:
          'computer-isolate: the search ran in the calling isolate — on the '
          'UI thread in the app',
    );
  }, tags: _guard);

  group('chooseMove', () {
    test('answers the move chooseMove gives inline, game after game', () async {
      for (final step in Strength.values) {
        final player = ComputerPlayer(step, _seed, nodeBudget: _budget);
        addTearDown(player.dispose);
        var game = Game.start(_vs(step), const Untimed());
        game = _play(game, ['d2d4', 'g8f6', 'c2c4', 'e7e6', 'g1f3']);
        // Black is to move: the computer's side.
        final moved = await _moved(player.chooseMove(game));
        final inline = chooseMove(
          game.position,
          step,
          _seed,
          history: [
            for (final s in game.history.take(game.history.length - 1))
              s.position.key,
          ],
          nodeBudget: _budget,
          // The worker's table size: a smaller table can search differently.
          table: TranspositionTable(),
        )!;
        expect(moved.move, inline.move, reason: '$step');
        expect(moved.ply, 5);
        expect(moved.depth, inline.search.depth);
        expect(moved.nodes, inline.search.nodes);
        expect(game.play(moved.move, byComputer: true).moves, hasLength(6));
      }
    });

    test('plays for the computer as White, and in a two-player game', () async {
      final player = ComputerPlayer(
        Strength.casual,
        _seed,
        nodeBudget: _budget,
      );
      addTearDown(player.dispose);
      final asWhite = Game.start(
        _vs(Strength.casual, player: black),
        const Untimed(),
      );
      final first = await _moved(player.chooseMove(asWhite));
      expect(legalMoves(asWhite.position), contains(first.move));
      final twoPlayer = _play(Game.start(const TwoPlayer(), const Untimed()), [
        'e2e4',
      ]);
      final reply = await _moved(player.chooseMove(twoPlayer));
      expect(legalMoves(twoPlayer.position), contains(reply.move));
    });

    test('refuses a finished game, the player\'s turn and another game\'s '
        'step or seed', () {
      final player = ComputerPlayer(Strength.club, _seed);
      addTearDown(player.dispose);
      final fresh = Game.start(_vs(Strength.club), const Untimed());
      expect(() => player.chooseMove(fresh), throwsStateError);
      final mated = _play(Game.start(const TwoPlayer(), const Untimed()), [
        'f2f3',
        'e7e5',
        'g2g4',
        'd8h4',
      ]);
      expect(() => player.chooseMove(mated), throwsStateError);
      final otherStep = _play(
        Game.start(_vs(Strength.master), const Untimed()),
        ['e2e4'],
      );
      expect(() => player.chooseMove(otherStep), throwsArgumentError);
      final otherSeed = _play(
        Game.start(
          const VsComputer(playerColour: white, step: Strength.club, seed: 1),
          const Untimed(),
        ),
        ['e2e4'],
      );
      expect(() => player.chooseMove(otherSeed), throwsArgumentError);
      expect(player.isThinking, isFalse);
    });

    test('is refused after dispose', () async {
      final player = ComputerPlayer(Strength.club, _seed);
      await player.dispose();
      final game = _play(Game.start(_vs(Strength.club), const Untimed()), [
        'e2e4',
      ]);
      expect(() => player.chooseMove(game), throwsStateError);
    });
  });

  group('thinking state', () {
    test('is true from chooseMove until the move arrives', () async {
      final player = ComputerPlayer(Strength.club, _seed, nodeBudget: _budget);
      addTearDown(player.dispose);
      final changes = <bool>[];
      player.thinking.listen(changes.add);
      final game = _play(Game.start(_vs(Strength.club), const Untimed()), [
        'e2e4',
      ]);
      expect(player.isThinking, isFalse);
      final answer = player.chooseMove(game);
      expect(player.isThinking, isTrue);
      await answer;
      expect(player.isThinking, isFalse);
      expect(changes, [true, false]);
    });

    test('is true until a cancellation, and a replaced request does not '
        'flicker it', () async {
      final player = ComputerPlayer(Strength.master, _seed);
      addTearDown(player.dispose);
      final changes = <bool>[];
      player.thinking.listen(changes.add);
      final game = _play(Game.start(_vs(Strength.master), const Untimed()), [
        'e2e4',
      ]);
      final first = player.chooseMove(game);
      final second = player.chooseMove(game);
      expect(await first, const MoveCancelled());
      expect(player.isThinking, isTrue);
      await player.cancel();
      expect(await second, const MoveCancelled());
      expect(player.isThinking, isFalse);
      expect(changes, [true, false]);
    });
  });

  group('cancel', () {
    test(
      'stops the worker within 100 ms, and no move arrives afterwards',
      () async {
        final player = ComputerPlayer(Strength.master, _seed);
        addTearDown(player.dispose);
        await player.start();
        final game = _play(Game.start(_vs(Strength.master), const Untimed()), [
          'e2e4',
        ]);
        final results = <MoveResult>[];
        final answer = player.chooseMove(game)..then(results.add);
        // Master's full budget takes far longer than this to search.
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(
          results,
          isEmpty,
          reason: 'the search finished before the cancel',
        );
        final stopping = Stopwatch()..start();
        await player.cancel();
        stopping.stop();
        expect(
          stopping.elapsedMilliseconds,
          lessThan(100),
          reason: 'the worker took ${stopping.elapsedMilliseconds} ms to stop',
        );
        expect(await answer, const MoveCancelled());
        // Long enough for the killed search to have finished, had it lived.
        await Future<void>.delayed(const Duration(seconds: 3));
        expect(results, [const MoveCancelled()]);
        expect(player.isThinking, isFalse);
      },
    );

    test(
      'a newer request cancels the older; the next answer is its own',
      () async {
        final player = ComputerPlayer(
          Strength.club,
          _seed,
          nodeBudget: _budget,
        );
        addTearDown(player.dispose);
        final before = _play(Game.start(_vs(Strength.club), const Untimed()), [
          'e2e4',
        ]);
        final after = _play(before, ['e7e5', 'g1f3']);
        final old = player.chooseMove(before);
        final current = player.chooseMove(after);
        expect(await old, const MoveCancelled());
        final moved = await _moved(current);
        expect(moved.ply, 3);
        expect(legalMoves(after.position), contains(moved.move));
      },
    );

    test(
      'with nothing pending does nothing, and the worker still answers',
      () async {
        final player = ComputerPlayer(
          Strength.club,
          _seed,
          nodeBudget: _budget,
        );
        addTearDown(player.dispose);
        await player.cancel();
        final game = _play(Game.start(_vs(Strength.club), const Untimed()), [
          'e2e4',
        ]);
        await _moved(player.chooseMove(game));
        await player.newGame();
        await _moved(player.chooseMove(game));
      },
    );
  });

  group('clock cap', () {
    test('shares the clock, adds half the increment, keeps a margin', () {
      expect(
        clockCapMs(remainingMs: 300000, incrementMs: 0, fullmoveNumber: 1),
        300000 ~/ 39,
      );
      expect(
        clockCapMs(remainingMs: 300000, incrementMs: 0, fullmoveNumber: 30),
        300000 ~/ 20,
      );
      expect(
        clockCapMs(remainingMs: 600000, incrementMs: 5000, fullmoveNumber: 1),
        600000 ~/ 39 + 2500,
      );
      // Half an increment larger than the clock itself is capped by it.
      expect(
        clockCapMs(remainingMs: 1000, incrementMs: 60000, fullmoveNumber: 1),
        1000 - minClockMarginMs,
      );
      expect(
        clockCapMs(remainingMs: 50, incrementMs: 60000, fullmoveNumber: 1),
        0,
      );
    });

    test('never exceeds the clock less its margin', () {
      for (var remaining = 0; remaining <= 5400000; remaining += 997) {
        for (final increment in [0, 1000, 5000, 60000]) {
          for (final move in [1, 10, 25, 39, 40, 80, 200]) {
            final cap = clockCapMs(
              remainingMs: remaining,
              incrementMs: increment,
              fullmoveNumber: move,
            );
            final margin = remaining * clockMarginPercent ~/ 100;
            final keep = margin > minClockMarginMs ? margin : minClockMarginMs;
            expect(cap, greaterThanOrEqualTo(0));
            expect(
              cap,
              lessThanOrEqualTo(remaining > keep ? remaining - keep : 0),
              reason: '$remaining ms, +$increment, move $move',
            );
          }
        }
      }
    });

    test('the clock limit is the clock less the margin, never the cap\'s '
        'less', () {
      expect(clockLimitMs(remainingMs: 150), 150 - minClockMarginMs);
      expect(clockLimitMs(remainingMs: 50), 0);
      expect(clockLimitMs(remainingMs: 0), 0);
      expect(clockLimitMs(remainingMs: 300000), 300000 * 98 ~/ 100);
      for (var remaining = 0; remaining <= 5400000; remaining += 997) {
        final limit = clockLimitMs(remainingMs: remaining);
        expect(limit, lessThan(remaining == 0 ? 1 : remaining));
        expect(
          limit,
          greaterThanOrEqualTo(
            clockCapMs(
              remainingMs: remaining,
              incrementMs: 60000,
              fullmoveNumber: 1,
            ),
          ),
        );
      }
    });

    test('is null untimed and reads the side to move\'s clock', () {
      final time = FakeTime();
      expect(
        gameClockCapMs(Game.start(_vs(Strength.club), const Untimed())),
        isNull,
      );
      var game = Game.start(_vs(Strength.club), Timed.blitz, time: time.call);
      game = _play(game, ['e2e4']);
      time.ms = 240000;
      expect(gameClockCapMs(game), 60000 ~/ 39);
    });

    test('stops a timed search at the cap, well inside the budget', () async {
      final time = FakeTime();
      final player = ComputerPlayer(Strength.master, _seed);
      addTearDown(player.dispose);
      await player.start();
      var game = Game.start(_vs(Strength.master), Timed.blitz, time: time.call);
      game = _play(game, ['e2e4']);
      // Black, the computer, has 2 s left: a cap of about 51 ms.
      time.ms = 298000;
      final cap = gameClockCapMs(game)!;
      final thinking = Stopwatch()..start();
      final moved = await _moved(player.chooseMove(game));
      thinking.stop();
      expect(
        moved.nodes,
        lessThan(Strength.master.settings.nodeBudget),
        reason: 'the search used its whole node budget',
      );
      expect(
        thinking.elapsedMilliseconds,
        lessThan(cap + 250),
        reason: 'thought ${thinking.elapsedMilliseconds} ms against $cap ms',
      );
      time.ms += thinking.elapsedMilliseconds;
      final after = game.play(moved.move, byComputer: true);
      expect(after.isOver, isFalse);
      expect(after.remaining(black), greaterThan(0));
    });

    test('inside the margin, plays the first legal move on the worker, '
        'unsearched', () async {
      final time = FakeTime();
      for (final step in Strength.values) {
        final player = ComputerPlayer(step, _seed);
        addTearDown(player.dispose);
        var game = Game.start(_vs(step), Timed.blitz, time: time.call);
        game = _play(game, ['e2e4']);
        time.ms = Timed.blitz.initialMs - minClockMarginMs;
        expect(clockLimitMs(remainingMs: game.remaining(black)!), 0);
        final moved = await _moved(player.chooseMove(game));
        expect(
          (moved.move, moved.depth, moved.nodes),
          (legalMoves(game.position).first, 0, 0),
          reason:
              '${step.name} with its clock at the margin did not play the '
              'first legal move unsearched',
        );
        expect(
          moved.debugSearchIsolate,
          isNot(anyOf(isNull, Isolate.current.controlPort)),
          reason: '${step.name} did not answer from the worker',
        );
        time.ms = 0;
      }
    });
  });

  group('acceptsDraw', () {
    test('answers on the worker as it does inline', () async {
      final player = ComputerPlayer(Strength.club, _seed);
      addTearDown(player.dispose);
      final level = _play(Game.start(_vs(Strength.club), const Untimed()), [
        'e2e4',
        'e7e5',
      ]);
      // White, the player, leaves its queen to Black, the computer, which
      // is then far ahead and declines.
      final ahead = _play(level, ['d1h5', 'd8g5', 'd2d4', 'g5h5']);
      for (final game in [level, ahead]) {
        expect(
          await player.acceptsDraw(game),
          acceptsDraw(game),
          reason: '$game',
        );
      }
      expect(await player.acceptsDraw(ahead), isFalse);
      expect(
        () =>
            player.acceptsDraw(Game.start(_vs(Strength.club), const Untimed())),
        throwsStateError,
      );
    });
  });
}
