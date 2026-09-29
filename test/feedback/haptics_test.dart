// The tick (#97): one light tick for each refused tap or drop and each
// capture, whoever made it, through the one haptic port while Haptics is on
// — and nothing else ticks.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:honest_chess/data/game_event.dart';
import 'package:honest_chess/engine/engine.dart';
import 'package:honest_chess/feedback/game_feedback.dart';
import 'package:honest_chess/feedback/haptics.dart';
import 'package:honest_chess/ui/board/board_interaction.dart';
import 'package:honest_chess/ui/board/board_options.dart';
import 'package:honest_chess/ui/game/computer_turns.dart';
import 'package:honest_chess/ui/game/game_controller.dart';
import 'package:honest_chess/ui/game/refusal.dart';

import '../support/app_harness.dart';
import '../ui/game/fake_computer.dart';

Square sq(String name) => Square.parse(name);

/// A controller, the hub over it with a counting port, and every refusal
/// the controller raised.
class _Rig {
  _Rig({
    GameController? controller,
    String? fen,
    BoardOptions options = const BoardOptions(),
  }) : controller = controller ?? GameController(fen: fen, options: options),
       board = ValueNotifier(options) {
    feedback = GameFeedback(
      events: this.controller.events,
      refusals: this.controller.refusals,
      board: board,
      foreground: foreground,
      player: FakeSoundPlayer(),
      haptics: haptics,
    );
    this.controller.refusals.listen(refusals.add);
  }

  final GameController controller;
  final ValueNotifier<BoardOptions> board;
  final foreground = ValueNotifier<bool>(true);
  final haptics = FakeHaptics();
  final refusals = <Refusal>[];
  late final GameFeedback feedback;

  int get ticks => haptics.ticks;

  void tap(String square) => controller.tapSquare(sq(square));

  void move(String uci) => expect(
    controller.move(sq(uci.substring(0, 2)), sq(uci.substring(2, 4))),
    isTrue,
    reason: 'test: $uci is playable',
  );

  void dispose() {
    feedback.dispose();
    controller.dispose();
    board.dispose();
    foreground.dispose();
  }
}

void main() {
  group('refusals', () {
    test('a tap on a square the piece cannot reach ticks once', () {
      final rig = _Rig();
      addTearDown(rig.dispose);
      rig.tap('g1');
      rig.tap('g4');
      expect(rig.ticks, 1, reason: 'haptics: an illegal tap ticks once');
      expect(rig.refusals, [
        Refusal(
          kind: PieceKind.knight,
          from: sq('g1'),
          to: sq('g4'),
          via: RefusalVia.tap,
        ),
      ]);
      rig.tap('g1');
      rig.tap('e7');
      expect(
        rig.ticks,
        2,
        reason: "haptics: a tap on the opponent's piece out of reach ticks",
      );
      rig.tap('g1');
      rig.tap('g4');
      expect(rig.ticks, 3, reason: 'haptics: identical refusals each tick');
    });

    test('selecting, switching, putting down and a quiet move do not tick', () {
      final rig = _Rig();
      addTearDown(rig.dispose);
      rig.tap('e4');
      rig.tap('e7');
      rig.tap('g1');
      rig.tap('b1');
      rig.tap('b1');
      rig.tap('g1');
      rig.tap('f3');
      expect(rig.controller.game.moves.map((m) => m.toUci()), ['g1f3']);
      rig.move('e7e5');
      expect(rig.controller.takeBack(), isTrue);
      expect(
        rig.ticks,
        0,
        reason:
            'haptics: an empty tap with nothing selected, a switch, a '
            'put-down, a quiet move and takeback tick nothing',
      );
      expect(rig.refusals, isEmpty);
    });

    test('drops: illegal or off the board tick; its own square and an '
        'abandoned drag do not', () {
      final rig = _Rig();
      addTearDown(rig.dispose);
      final c = rig.controller;
      expect(c.pickUp(sq('g1')), isTrue);
      c.drop(sq('g1'), sq('g4'));
      expect(rig.ticks, 1, reason: 'haptics: an illegal drop ticks');
      expect(c.pickUp(sq('g1')), isTrue);
      c.drop(sq('g1'), null);
      expect(rig.ticks, 2, reason: 'haptics: a drop off the board ticks');
      expect(rig.refusals.map((r) => (r.to, r.via)), [
        (sq('g4'), RefusalVia.drop),
        (null, RefusalVia.drop),
      ]);
      expect(c.pickUp(sq('g1')), isTrue);
      c.drop(sq('g1'), sq('g1'));
      c.abandonDrag(sq('g1'));
      expect(c.pickUp(sq('b1')), isTrue);
      c.move(sq('e2'), sq('e4'));
      // The drag from b1 outlived that position change.
      c.drop(sq('b1'), sq('b4'));
      expect(c.pickUp(sq('e7')), isTrue);
      expect(
        c.pickUp(sq('e2')),
        isFalse,
        reason: 'test: an empty square cannot be picked up',
      );
      expect(
        rig.ticks,
        2,
        reason:
            'haptics: a drop on its own square, an abandoned drag, a stale '
            'drop and a refused pickup tick nothing',
      );
    });

    test('taps while input is locked tick nothing', () {
      final rig = _Rig(fen: '4k3/1P6/8/8/8/8/8/4K3 w - - 0 1');
      addTearDown(rig.dispose);
      final c = rig.controller;
      rig.tap('b7');
      expect(c.pause(), isTrue);
      rig.tap('h5');
      expect(c.resume(), isTrue);
      rig.move('b7b8');
      expect(c.state.pendingPromotion, isNotNull);
      rig.tap('h5');
      c.drop(sq('b7'), sq('h5'));
      expect(c.cancelPromotion(), isTrue);
      expect(c.resign(), isTrue);
      rig.tap('e1');
      rig.tap('h5');
      expect(
        rig.ticks,
        0,
        reason:
            'haptics: nothing ticks while paused, with a promotion pending '
            'or once the game is over',
      );
    });
  });

  group('captures', () {
    test('a capture ticks; en passant too', () {
      final rig = _Rig();
      addTearDown(rig.dispose);
      rig.move('e2e4');
      rig.move('d7d5');
      rig.move('e4e5');
      expect(rig.ticks, 0, reason: 'haptics: quiet moves do not tick');
      rig.move('f7f5');
      rig.move('e5f6');
      expect(rig.ticks, 1, reason: 'haptics: en passant ticks');
      rig.move('g7f6');
      expect(rig.ticks, 2, reason: 'haptics: a capture ticks');
    });

    test('a capturing promotion ticks when the piece is chosen; a cancelled '
        'card gives nothing', () {
      final rig = _Rig(fen: '1r2k3/P7/8/8/8/8/8/4K3 w - - 0 1');
      addTearDown(rig.dispose);
      final c = rig.controller;
      rig.move('a7b8');
      expect(rig.ticks, 0, reason: 'haptics: the card opening is silent');
      expect(c.cancelPromotion(), isTrue);
      expect(rig.ticks, 0, reason: 'haptics: a cancelled card is silent');
      rig.move('a7b8');
      expect(c.choosePromotion(PieceKind.knight), isTrue);
      expect(rig.ticks, 1, reason: 'haptics: the capturing promotion ticks');
    });

    test('auto-queen: the capturing promotion ticks at once', () {
      final rig = _Rig(
        fen: '1r2k3/P7/8/8/8/8/8/4K3 w - - 0 1',
        options: const BoardOptions(autoQueen: true),
      );
      addTearDown(rig.dispose);
      rig.move('a7b8');
      expect(rig.ticks, 1);
    });

    testWidgets("the computer's capture ticks; its quiet move does not", (
      tester,
    ) async {
      final computers = FakeComputers();
      var ms = 0;
      Future<void> think() async {
        ms += minThinkTime.inMilliseconds;
        await tester.pump(minThinkTime);
      }

      final rig = _Rig(
        controller: GameController(
          mode: const VsComputer(
            playerColour: Colour.white,
            step: Strength.club,
            seed: 1,
          ),
          now: () => ms,
          computer: computers.call,
        ),
      );
      addTearDown(rig.dispose);
      rig.move('e2e4');
      await tester.pump();
      computers.current.last.move('d7d5');
      await think();
      expect(rig.ticks, 0, reason: "haptics: the computer's quiet move");
      rig.move('e4d5');
      await tester.pump();
      computers.current.last.move('d8d5');
      await think();
      expect(
        rig.ticks,
        2,
        reason: "haptics: the computer's capture ticks as yours does",
      );
    });

    test('ticksFor: only a capturing move', () {
      final start = Game.start(const TwoPlayer(), const Untimed());
      final quiet = start.play(Move.fromUci(start.position, 'e2e4'));
      expect(ticksFor(GameMoved(quiet, const {})), isFalse);
      expect(ticksFor(GameStarted(start, const {})), isFalse);
      expect(ticksFor(GameEnded(quiet, const {})), isFalse);
    });
  });

  group('the setting', () {
    test('with Haptics off nothing ticks, from the moment it is off', () {
      final rig = _Rig();
      addTearDown(rig.dispose);
      rig.board.value = const BoardOptions(haptics: false);
      rig.tap('g1');
      rig.tap('g4');
      rig.move('e2e4');
      rig.move('d7d5');
      rig.move('e4d5');
      expect(rig.ticks, 0, reason: 'haptics: Haptics off ticks nothing');
      rig.board.value = const BoardOptions();
      rig.move('d8d5');
      expect(rig.ticks, 1, reason: 'haptics: on again, the next capture');
    });

    test('nothing ticks while the app is not in the foreground', () {
      final rig = _Rig();
      addTearDown(rig.dispose);
      rig.foreground.value = false;
      rig.tap('g1');
      rig.tap('g4');
      expect(rig.ticks, 0);
    });
  });

  group('on the board', () {
    Future<_Rig> pumpBoardRig(WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final rig = _Rig();
      addTearDown(rig.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BoardInteraction(
              controller: rig.controller,
              bottom: Colour.white,
            ),
          ),
        ),
      );
      return rig;
    }

    Offset centre(WidgetTester tester, String square) =>
        tester.getCenter(find.byKey(Key('cell-$square')));

    Future<TestGesture> lift(
      WidgetTester tester,
      String from,
      Offset to,
    ) async {
      final start = centre(tester, from);
      final gesture = await tester.startGesture(start);
      await tester.pump();
      for (var i = 1; i <= 5; i++) {
        await gesture.moveTo(Offset.lerp(start, to, i / 5)!);
        await tester.pump();
      }
      return gesture;
    }

    testWidgets('an illegal drop ticks at release with its square', (
      tester,
    ) async {
      final rig = await pumpBoardRig(tester);
      final gesture = await lift(tester, 'g1', centre(tester, 'g4'));
      expect(rig.ticks, 0, reason: 'haptics: nothing while dragging');
      await gesture.up();
      await tester.pump();
      expect(rig.ticks, 1, reason: 'haptics: at release, not after');
      expect(rig.refusals.single.to, sq('g4'));
      expect(rig.refusals.single.via, RefusalVia.drop);
      await tester.pumpAndSettle();
      expect(rig.ticks, 1, reason: 'haptics: the spring-back adds none');
    });

    testWidgets('a drop off the board ticks with no square', (tester) async {
      final rig = await pumpBoardRig(tester);
      final gesture = await lift(tester, 'g1', const Offset(195, 800));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(rig.ticks, 1);
      expect(rig.refusals.single.to, isNull);
    });

    testWidgets('an illegal tap ticks; a legal drop does not', (tester) async {
      final rig = await pumpBoardRig(tester);
      await tester.tap(find.byKey(const Key('cell-g1')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('cell-g4')));
      await tester.pump();
      expect(rig.ticks, 1);
      final gesture = await lift(tester, 'g1', centre(tester, 'f3'));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(rig.controller.game.moves.map((m) => m.toUci()), ['g1f3']);
      expect(rig.ticks, 1, reason: 'haptics: a legal drop does not tick');
    });

    testWidgets('a cancelled pointer, a position change mid-drag and a drag '
        "of the opponent's piece tick nothing", (tester) async {
      final rig = await pumpBoardRig(tester);
      var gesture = await lift(tester, 'g1', centre(tester, 'g4'));
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(rig.controller.state.selection, isNull);
      gesture = await lift(tester, 'b1', centre(tester, 'b4'));
      rig.controller.move(sq('e2'), sq('e4'));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      rig.move('e7e5');
      await tester.tap(find.byKey(const Key('cell-g1')));
      await tester.pump();
      expect(
        rig.controller.state.selection,
        sq('g1'),
        reason: 'test: the board takes taps again after the stale drag',
      );
      await tester.tap(find.byKey(const Key('cell-g1')));
      await tester.pump();
      gesture = await lift(tester, 'd7', centre(tester, 'd4'));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(
        rig.ticks,
        0,
        reason:
            'haptics: a drag with no drop, a stale drop and a drag refused '
            'at pickup tick nothing',
      );
    });
  });

  group('FlutterHaptics', () {
    testWidgets('ticks with lightImpact; a failing platform logs once', (
      tester,
    ) async {
      final calls = <MethodCall>[];
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      final logs = <String>[];
      final port = FlutterHaptics(log: logs.add);
      await port.tick();
      expect(calls.map((c) => (c.method, c.arguments)), [
        ('HapticFeedback.vibrate', 'HapticFeedbackType.lightImpact'),
      ]);
      messenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async => throw PlatformException(code: 'x'),
      );
      await port.tick();
      await port.tick();
      expect(logs, hasLength(1), reason: 'haptics: logs once, stays quiet');
      await const NoHaptics().tick();
    });
  });
}
