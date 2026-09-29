// Playing the computer (#75) with a scripted fake: it answers after your
// move and never before its think-time floor, the board ignores you on its
// turn, it opens as White when you are Black, and every way of ending its
// turn early — takeback, restart, resign, pause, a flag, leaving — cancels
// the search so its late move is never played.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:honest_chess/engine/engine.dart' hide play;
import 'package:honest_chess/ui/board/board_options.dart';
import 'package:honest_chess/ui/game/computer_turns.dart';
import 'package:honest_chess/ui/game/defaults.dart';
import 'package:honest_chess/ui/game/game_controller.dart';
import 'package:honest_chess/ui/game/game_screen.dart';

import '../board/board_interaction_test.dart' show tap;
import '../../support/app_harness.dart';
import 'fake_computer.dart';
import 'player_panel_test.dart' show pumpGame, play, text, Harness;

const asWhite = VsComputer(
  playerColour: Colour.white,
  step: Strength.club,
  seed: 1,
);

const asBlack = VsComputer(
  playerColour: Colour.black,
  step: Strength.club,
  seed: 1,
);

List<String> moves(GameController c) => [
  for (final m in c.game.moves) m.toUci(),
];

/// A timed game against the fake computer, you White unless [mode] says.
Future<(Harness, FakeComputers)> pumpVs(
  WidgetTester tester, {
  GameMode mode = asWhite,
  TimeControl timeControl = Timed.rapid,
}) async {
  final fakes = FakeComputers();
  final h = await pumpGame(
    tester,
    mode: mode,
    timeControl: timeControl,
    computer: fakes,
  );
  return (h, fakes);
}

void main() {
  group('the computer\'s turn', () {
    testWidgets('it answers your move, no sooner than the floor', (
      tester,
    ) async {
      final (h, fakes) = await pumpVs(tester);
      final c = h.controller;
      expect(c.state.thinking, isFalse, reason: 'turns: your turn first');
      expect(fakes.current.requests, isEmpty);

      expect(c.move(Square.parse('e2'), Square.parse('e4')), isTrue);
      expect(
        c.state.thinking,
        isTrue,
        reason: 'turns: thinking from the moment its turn begins',
      );
      expect(
        fakes.current.requests,
        isEmpty,
        reason: 'turns: the request waits for the frame showing your move',
      );
      await tester.pump();
      expect(fakes.current.requests, hasLength(1));
      expect(fakes.current.last.game.moves.map((m) => m.toUci()), ['e2e4']);
      expect(text(tester, 'status-text'), 'THINKING…');
      expect(text(tester, 'name-black'), 'Club is thinking');

      fakes.current.last.move('e7e5');
      await h.clock.advance(minThinkTime - const Duration(milliseconds: 1));
      expect(moves(c), [
        'e2e4',
      ], reason: 'turns: an instant answer still waits for the floor');
      await h.clock.advance(const Duration(milliseconds: 1));
      expect(moves(c), ['e2e4', 'e7e5'], reason: 'turns: its move lands');
      expect(c.state.thinking, isFalse);
      expect(c.state.lastMove!.toUci(), 'e7e5');
      expect(c.state.tintAt(Square.parse('e5')), SquareTint.lastMove);
      expect(text(tester, 'status-text'), 'WHITE TO MOVE');
      expect(
        c.remaining(Colour.black),
        const Duration(minutes: 10, seconds: 5) - minThinkTime,
        reason:
            'turns: its clock ran through the floor, then took the '
            'increment',
      );
      expect(fakes.current.requests, hasLength(1));
    });

    testWidgets('your taps and drags do nothing while it thinks', (
      tester,
    ) async {
      final (h, fakes) = await pumpVs(tester);
      final c = h.controller;
      await play(tester, c, 'e2e4');
      await tap(tester, 'd2');
      await tap(tester, 'd4');
      await tap(tester, 'e7');
      await tap(tester, 'e5');
      expect(c.state.selection, isNull, reason: 'turns: nothing picked up');
      expect(moves(c), ['e2e4'], reason: 'turns: no move for either side');
      expect(c.move(Square.parse('e7'), Square.parse('e5')), isFalse);
      expect(fakes.current.requests, hasLength(1));
      // Answered, so no request or floor outlives the test.
      fakes.current.last.move();
      await h.clock.advance(minThinkTime);
    });

    testWidgets('as Black, the computer makes the first move', (tester) async {
      final (h, fakes) = await pumpVs(tester, mode: asBlack);
      final c = h.controller;
      expect(c.state.thinking, isTrue);
      expect(fakes.current.requests, hasLength(1));
      expect(fakes.current.last.ply, 0);
      expect(
        (fakes.current.strength, fakes.current.seed),
        (Strength.club, 1),
        reason: 'turns: the game\'s own step and seed',
      );
      await tap(tester, 'e7');
      expect(c.state.selection, isNull);
      fakes.current.last.move('d2d4');
      await h.clock.advance(minThinkTime);
      expect(moves(c), ['d2d4']);
      expect(c.inputLocked, isFalse, reason: 'turns: then it is yours');
    });

    testWidgets('it does not think in a two-player game', (tester) async {
      final fakes = FakeComputers();
      final h = await pumpGame(tester, computer: fakes);
      await play(tester, h.controller, 'e2e4');
      expect(h.controller.state.thinking, isFalse);
      expect(fakes.built, isEmpty, reason: 'turns: no computer is built');
    });
  });

  group('cancel', () {
    /// You played e4; the computer's search is pending past its floor.
    Future<(Harness, FakeComputers, FakeRequest)> thinking(
      WidgetTester tester,
    ) async {
      final (h, fakes) = await pumpVs(tester);
      await play(tester, h.controller, 'e2e4');
      // A real search outlasts the floor: its answer is all that is missing.
      await h.clock.advance(minThinkTime * 2);
      expect(h.controller.state.thinking, isTrue);
      return (h, fakes, fakes.current.last);
    }

    Future<void> lateAnswer(Harness h, FakeRequest request) async {
      request.move('e7e5');
      await h.clock.advance(const Duration(seconds: 2));
    }

    testWidgets('takeback cancels, and the late move is dropped', (
      tester,
    ) async {
      final (h, fakes, request) = await thinking(tester);
      final c = h.controller;
      expect(c.takeBack(), isTrue);
      expect(fakes.current.cancels, 1, reason: 'cancel: takeback stops it');
      expect(c.state.thinking, isFalse);
      expect(moves(c), isEmpty, reason: 'cancel: back to your turn');
      await lateAnswer(h, request);
      expect(moves(c), isEmpty, reason: 'cancel: the late move is dropped');
      expect(c.state.lastMove, isNull);
      expect(fakes.current.requests, hasLength(1), reason: 'no re-request');
      expect(c.inputLocked, isFalse);
    });

    testWidgets('restart cancels and brings a new computer, new seed', (
      tester,
    ) async {
      final (h, fakes, request) = await thinking(tester);
      final c = h.controller;
      final old = fakes.current;
      expect(await c.restart(), isTrue);
      expect(old.cancels, 1);
      expect(old.disposed, isTrue, reason: 'cancel: one computer per game');
      expect(fakes.built, hasLength(2));
      final mode = c.game.mode as VsComputer;
      expect(mode.seed, isNot(1), reason: 'restart: a fresh seed');
      expect(fakes.current.seed, mode.seed);
      expect((mode.playerColour, mode.step), (Colour.white, Strength.club));
      expect(c.game.clock.control, Timed.rapid);
      await lateAnswer(h, request);
      expect(moves(c), isEmpty, reason: 'cancel: the old game\'s move');
      expect(fakes.current.requests, isEmpty);
    });

    testWidgets('restart as Black asks the new computer to open', (
      tester,
    ) async {
      final (h, fakes) = await pumpVs(tester, mode: asBlack);
      h.controller.restart();
      await tester.pump();
      expect(fakes.built.first.cancels, 1);
      expect(fakes.current.requests.single.ply, 0);
      fakes.current.last.move('e2e4');
      await h.clock.advance(minThinkTime);
      expect(moves(h.controller), ['e2e4']);
    });

    testWidgets('resign cancels; the game is over and stays so', (
      tester,
    ) async {
      final (h, fakes, request) = await thinking(tester);
      final c = h.controller;
      expect(c.resign(), isTrue);
      expect(c.game.status, const Win(Colour.black, GameEndReason.resignation));
      expect(fakes.current.cancels, 1);
      expect(c.state.thinking, isFalse);
      await lateAnswer(h, request);
      expect(moves(c), ['e2e4'], reason: 'cancel: nothing after resigning');
      expect(c.resign(), isFalse, reason: 'resign: once');
    });

    testWidgets('pause cancels; resume asks again', (tester) async {
      final (h, fakes, request) = await thinking(tester);
      final c = h.controller;
      expect(c.pause(), isTrue);
      expect(fakes.current.cancels, 1);
      expect(c.state.thinking, isFalse);
      await lateAnswer(h, request);
      expect(moves(c), ['e2e4']);
      expect(c.resume(), isTrue);
      expect(c.state.thinking, isTrue);
      await tester.pump();
      expect(fakes.current.requests, hasLength(2));
      fakes.current.last.move('c7c5');
      await h.clock.advance(minThinkTime);
      expect(moves(c), ['e2e4', 'c7c5']);
    });

    testWidgets('its flag falling while it thinks cancels', (tester) async {
      final (h, fakes, request) = await thinking(tester);
      final c = h.controller;
      await h.clock.advance(const Duration(minutes: 11));
      expect(c.game.status, const Win(Colour.white, GameEndReason.flag));
      expect(fakes.current.cancels, 1);
      expect(c.state.thinking, isFalse);
      await lateAnswer(h, request);
      expect(moves(c), ['e2e4']);
    });

    testWidgets('leaving the game cancels and stops the computer', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final fakes = FakeComputers();
      await pumpUnderScope(
        tester,
        GameScreen(
          options: const BoardOptions(),
          setup: vsComputerDefault,
          computerFactory: fakes.call,
        ),
      );
      await tap(tester, 'e2');
      await tap(tester, 'e4');
      final request = fakes.current.last;
      await tester.pumpWidget(const SizedBox());
      expect(fakes.current.cancels, 1, reason: 'cancel: leaving stops it');
      expect(fakes.current.disposed, isTrue);
      request.move('e7e5');
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull, reason: 'cancel: no late move');
    });
  });

  group('failures', () {
    testWidgets('a cancel nobody asked for re-requests once, then the chip', (
      tester,
    ) async {
      final (h, fakes) = await pumpVs(tester);
      final c = h.controller;
      await play(tester, c, 'e2e4');
      fakes.current.last.cancelled();
      await h.clock.advance(minThinkTime);
      expect(fakes.current.requests, hasLength(2), reason: 'retry: once');
      expect(c.state.computerFailed, isFalse);
      fakes.current.last.cancelled();
      await h.clock.advance(minThinkTime);
      expect(fakes.current.requests, hasLength(2), reason: 'retry: only once');
      expect(c.state.computerFailed, isTrue);
      expect(text(tester, 'status-text'), computerFailedText);
      expect(c.inputLocked, isTrue, reason: 'failed: still its turn');
      await tap(tester, 'd2');
      expect(c.state.selection, isNull);

      await tester.tap(find.byKey(const Key('status-chip')));
      await tester.pump();
      expect(fakes.current.requests, hasLength(3), reason: 'chip: asks again');
      expect(c.state.computerFailed, isFalse);
      expect(text(tester, 'status-text'), 'THINKING…');
      fakes.current.last.move('e7e5');
      await h.clock.advance(minThinkTime);
      expect(moves(c), ['e2e4', 'e7e5']);
    });

    testWidgets('a worker error retries once, then the chip; tap again', (
      tester,
    ) async {
      final (h, fakes) = await pumpVs(tester);
      final c = h.controller;
      await play(tester, c, 'e2e4');
      fakes.current.last.fail();
      await h.clock.advance(minThinkTime);
      fakes.current.last.fail();
      await h.clock.advance(minThinkTime);
      expect(fakes.current.requests, hasLength(2));
      expect(c.state.computerFailed, isTrue);
      expect(c.retryComputer(), isTrue);
      expect(c.retryComputer(), isFalse, reason: 'chip: one request at once');
      fakes.current.last.fail();
      await h.clock.advance(minThinkTime);
      fakes.current.last.fail();
      await h.clock.advance(minThinkTime);
      expect(c.state.computerFailed, isTrue, reason: 'chip: shown again');
      expect(c.retryComputer(), isTrue, reason: 'chip: any number of times');
      fakes.current.last.move();
      await h.clock.advance(minThinkTime);
      expect(c.game.moves, hasLength(2));
      expect(c.state.computerFailed, isFalse);
    });

    testWidgets('a takeback clears the chip', (tester) async {
      final (h, fakes) = await pumpVs(tester);
      final c = h.controller;
      await play(tester, c, 'e2e4');
      fakes.current.last.fail();
      await h.clock.advance(minThinkTime);
      fakes.current.last.fail();
      await h.clock.advance(minThinkTime);
      expect(c.state.computerFailed, isTrue);
      c.takeBack();
      await tester.pump();
      expect(c.state.computerFailed, isFalse);
      expect(text(tester, 'status-text'), 'WHITE TO MOVE');
    });
  });

  group('controller actions', () {
    testWidgets('takeback is refused with nothing to undo or turned off', (
      tester,
    ) async {
      final (h, _) = await pumpVs(tester);
      expect(h.controller.takeBack(), isFalse);
      final off = GameController(
        options: const BoardOptions(takebackAllowed: false),
      );
      addTearDown(off.dispose);
      off.move(Square.parse('e2'), Square.parse('e4'));
      expect(off.takeBack(), isFalse);
      expect(off.game.moves, hasLength(1));
    });

    testWidgets('two players: the side to move resigns', (tester) async {
      final h = await pumpGame(tester);
      await play(tester, h.controller, 'e2e4');
      expect(h.controller.resign(), isTrue);
      expect(
        h.controller.game.status,
        const Win(Colour.white, GameEndReason.resignation),
      );
    });
  });

  test('the real computer answers through the adapter', () async {
    final computer = ComputerPlayerOpponent(Strength.beginner, 7);
    addTearDown(computer.dispose);
    final game = Game.start(
      VsComputer(playerColour: Colour.black, step: Strength.beginner, seed: 7),
      const Untimed(),
    );
    final result = await computer.chooseMove(game);
    expect(result, isA<Moved>());
    expect(legalMoves(game.position), contains((result as Moved).move));
  });
}
