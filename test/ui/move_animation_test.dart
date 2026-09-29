import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:honest_chess/data/settings_store.dart';
import 'package:honest_chess/engine/engine.dart';
import 'package:honest_chess/ui/board/board_options.dart';
import 'package:honest_chess/ui/board/move_animation.dart';
import 'package:honest_chess/ui/game/computer_turns.dart';
import 'package:honest_chess/ui/game/game_controller.dart';
import 'package:honest_chess/ui/game/game_screen.dart';

import '../support/app_harness.dart';
import 'game/fake_computer.dart';

/// A frame past a slide's end: the controller completes on the first tick
/// after its duration.
const _frame = Duration(milliseconds: 16);

const _castleFen = 'r3k2r/pppppppp/8/8/8/8/PPPPPPPP/R3K2R w KQkq - 0 1';
const _captureFen = '4k3/8/8/3p4/4P3/8/8/4K3 w - - 0 1';
const _enPassantFen = '4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1';
const _promotionFen = '4k3/P7/8/8/8/8/8/4K3 w - - 0 1';

typedef _Rig = ({GameController controller, SettingsStore settings});

/// The play screen over [controller] (by default a two-player game from
/// [fen]) under the harness, with Piece animations at [animations].
Future<_Rig> _pump(
  WidgetTester tester, {
  String? fen,
  GameController? controller,
  BoardOptions options = const BoardOptions(),
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final c = controller ?? GameController(fen: fen, options: options);
  final settings = SettingsStore();
  settings.updateBoard((_) => options);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    settings.dispose();
  });
  await pumpUnderScope(
    tester,
    GameScreen(options: options, controller: c),
    controller: c,
    settings: settings,
  );
  return (controller: c, settings: settings);
}

Finder _key(String key) => find.byKey(Key(key));

Offset _centre(WidgetTester tester, String square) =>
    tester.getCenter(_key('sq-$square'));

Future<void> _tapMove(WidgetTester tester, String uci) async {
  await tester.tap(_key('cell-${uci.substring(0, 2)}'));
  await tester.pump();
  await tester.tap(_key('cell-${uci.substring(2, 4)}'));
  await tester.pump();
}

/// Whether the piece drawn on [square] of the board is hidden.
bool _hidden(WidgetTester tester, String square) => tester
    .widgetList<Opacity>(
      find.ancestor(of: _key('piece-$square'), matching: find.byType(Opacity)),
    )
    .any((o) => o.opacity == 0);

/// How far the slide to [to] has come from [from], 0 to 1, along the line
/// between the two squares' centres.
double _travelled(WidgetTester tester, String from, String to) {
  final a = _centre(tester, from);
  final b = _centre(tester, to);
  final at = tester.getCenter(_key('slide-$to'));
  return (at - a).distance / (b - a).distance;
}

Future<void> _slideOut(WidgetTester tester) async {
  await tester.pump(moveSlideDuration);
  await tester.pump(_frame);
}

void main() {
  group('moveMotion', () {
    Position at(String fen) => Position.fromFen(fen);

    test('a quiet move slides its piece and fades nothing', () {
      final before = Position.initial();
      final m = moveMotion(before, Move.fromUci(before, 'g1f3'));
      expect(m.slides, [
        (
          piece: before.pieceAt(Square.g1)!,
          from: Square.g1,
          to: Square.parse('f3'),
        ),
      ]);
      expect(m.fades, isEmpty);
      expect(m.hidden, {Square.parse('f3')});
    });

    test('castling slides king and rook together', () {
      final before = at(_castleFen);
      for (final (uci, rook) in [('e1g1', 'h1f1'), ('e1c1', 'a1d1')]) {
        final m = moveMotion(before, Move.fromUci(before, uci));
        expect(
          [for (final s in m.slides) '${s.from.name}${s.to.name}'],
          [uci, rook],
          reason: 'move-animation: $uci slides the king and its rook',
        );
      }
    });

    test('a capture fades the taken piece; en passant the passed pawn', () {
      final capture = at(_captureFen);
      expect(moveMotion(capture, Move.fromUci(capture, 'e4d5')).fades, [
        (
          piece: capture.pieceAt(Square.parse('d5'))!,
          square: Square.parse('d5'),
        ),
      ]);
      final ep = at(_enPassantFen);
      expect(moveMotion(ep, Move.fromUci(ep, 'e5d6')).fades, [
        (piece: ep.pieceAt(Square.parse('d5'))!, square: Square.parse('d5')),
      ], reason: 'move-animation: en passant fades the pawn it passed');
    });

    test('a promotion slides the pawn to the square the new piece takes', () {
      final before = at(_promotionFen);
      final m = moveMotion(before, Move.fromUci(before, 'a7a8q'));
      expect(m.slides.single.piece.kind, PieceKind.pawn);
      expect(m.hidden, {Square.a8});
    });

    test('a dropped move slides only a castling rook, and fades nothing', () {
      final castle = at(_castleFen);
      final m = moveMotion(castle, Move.fromUci(castle, 'e1g1'), dropped: true);
      expect(
        [for (final s in m.slides) '${s.from.name}${s.to.name}'],
        ['h1f1'],
        reason: 'move-animation: the dropped king lands without a slide',
      );
      final capture = at(_captureFen);
      expect(
        moveMotion(
          capture,
          Move.fromUci(capture, 'e4d5'),
          dropped: true,
        ).isEmpty,
        isTrue,
        reason: 'move-animation: a dropped capture vanishes at once',
      );
    });
  });

  group('lastMoveWasDrop', () {
    test('a drop says so; a tap, and a drop refused, do not', () {
      final c = GameController();
      addTearDown(c.dispose);
      c.pickUp(Square.parse('e2'));
      expect(c.drop(Square.parse('e2'), Square.parse('e4')), isTrue);
      expect(c.lastMoveWasDrop, isTrue);
      c.tapSquare(Square.parse('e7'));
      c.tapSquare(Square.parse('e5'));
      expect(c.lastMoveWasDrop, isFalse);
    });

    test('a promotion chosen after a drop was dropped', () {
      final c = GameController(fen: _promotionFen);
      addTearDown(c.dispose);
      c.pickUp(Square.parse('a7'));
      c.drop(Square.parse('a7'), Square.a8);
      expect(c.state.pendingPromotion, isNotNull);
      c.choosePromotion(PieceKind.knight);
      expect(c.lastMoveWasDrop, isTrue);
    });

    test('a promotion chosen after a tap was not', () {
      final c = GameController(fen: _promotionFen);
      addTearDown(c.dispose);
      c.tapSquare(Square.parse('a7'));
      c.tapSquare(Square.a8);
      c.choosePromotion(PieceKind.queen);
      expect(c.lastMoveWasDrop, isFalse);
    });
  });

  group('the slide', () {
    testWidgets('mid-slide the piece is between its squares, eased out; at '
        'the end it is on its target', (tester) async {
      await _pump(tester);
      await _tapMove(tester, 'e2e4');
      await tester.pump(moveSlideDuration ~/ 2);
      final half = _travelled(tester, 'e2', 'e4');
      expect(
        half,
        allOf(greaterThan(0.5), lessThan(1)),
        reason: 'move-animation: half the time, past halfway (ease-out)',
      );
      expect(
        tester.getCenter(_key('slide-e4')).dx,
        closeTo(_centre(tester, 'e2').dx, 0.01),
      );
      expect(
        _hidden(tester, 'e4'),
        isTrue,
        reason: 'move-animation: the target shows its piece only at the end',
      );
      await _slideOut(tester);
      expect(_key('slide-e4'), findsNothing);
      expect(_hidden(tester, 'e4'), isFalse);
      expect(
        tester.getCenter(_key('piece-e4')),
        _centre(tester, 'e4'),
        reason: 'move-animation: the piece ends on its target',
      );
    });

    testWidgets('castling slides king and rook together', (tester) async {
      await _pump(tester, fen: _castleFen);
      await _tapMove(tester, 'e1g1');
      await tester.pump(moveSlideDuration ~/ 2);
      expect(_travelled(tester, 'e1', 'g1'), inExclusiveRange(0, 1));
      expect(_travelled(tester, 'h1', 'f1'), inExclusiveRange(0, 1));
      await _slideOut(tester);
      expect(_key('slide-g1'), findsNothing);
      expect(_key('slide-f1'), findsNothing);
    });

    testWidgets('a capture fades the taken piece over the slide', (
      tester,
    ) async {
      await _pump(tester, fen: _captureFen);
      await _tapMove(tester, 'e4d5');
      await tester.pump(moveSlideDuration ~/ 2);
      final fade = tester.widget<Opacity>(
        find.descendant(of: _key('fade-d5'), matching: find.byType(Opacity)),
      );
      expect(fade.opacity, inExclusiveRange(0, 1));
      await _slideOut(tester);
      expect(_key('fade-d5'), findsNothing);
    });

    testWidgets('en passant fades the passed pawn', (tester) async {
      await _pump(tester, fen: _enPassantFen);
      await _tapMove(tester, 'e5d6');
      await tester.pump(moveSlideDuration ~/ 2);
      expect(_key('fade-d5'), findsOneWidget);
      expect(_key('piece-d5'), findsNothing);
      await _slideOut(tester);
      expect(_key('fade-d5'), findsNothing);
    });

    testWidgets('a promotion waits on its square, then slides after the '
        'choice and shows the new piece', (tester) async {
      final rig = await _pump(tester, fen: _promotionFen);
      await _tapMove(tester, 'a7a8');
      await tester.pump(moveSlideDuration);
      expect(
        _key('slide-a8'),
        findsNothing,
        reason: 'move-animation: nothing slides while the card is open',
      );
      expect(_key('piece-a7'), findsOneWidget);
      rig.controller.choosePromotion(PieceKind.queen);
      await tester.pump();
      await tester.pump(moveSlideDuration ~/ 2);
      expect(_travelled(tester, 'a7', 'a8'), inExclusiveRange(0, 1));
      expect(
        tester
            .widget<Text>(
              find.descendant(
                of: _key('slide-a8'),
                matching: find.byType(Text),
              ),
            )
            .data,
        startsWith('♟'),
        reason: 'move-animation: the pawn slides, not the queen',
      );
      await _slideOut(tester);
      expect(tester.widget<Text>(_key('piece-a8')).data, startsWith('♛'));
      expect(_hidden(tester, 'a8'), isFalse);
    });

    testWidgets('a dropped move lands without a second slide; a castling '
        'rook still slides', (tester) async {
      await _pump(tester, fen: _castleFen);
      await tester.drag(
        _key('piece-e1'),
        _centre(tester, 'g1') - _centre(tester, 'e1'),
      );
      await tester.pump();
      expect(
        _key('slide-g1'),
        findsNothing,
        reason: 'move-animation: the dropped king does not slide again',
      );
      expect(_hidden(tester, 'g1'), isFalse);
      expect(_key('slide-f1'), findsOneWidget);
      await _slideOut(tester);
    });

    testWidgets("the computer's move slides the same way", (tester) async {
      final computers = FakeComputers();
      final c = GameController(
        mode: const VsComputer(
          playerColour: Colour.black,
          step: Strength.club,
          seed: 1,
        ),
        computer: computers.call,
      );
      await _pump(tester, controller: c);
      computers.current.last.move('e2e4');
      await tester.pump(minThinkTime);
      await tester.pump();
      await tester.pump(moveSlideDuration ~/ 2);
      expect(_travelled(tester, 'e2', 'e4'), inExclusiveRange(0, 1));
      await _slideOut(tester);
      expect(_key('slide-e4'), findsNothing);
    });

    testWidgets('a tap during a slide acts on the position after it', (
      tester,
    ) async {
      final rig = await _pump(tester);
      await _tapMove(tester, 'e2e4');
      await tester.pump(moveSlideDuration ~/ 3);
      await tester.tap(_key('cell-e7'));
      await tester.pump();
      expect(rig.controller.state.selection, Square.parse('e7'));
      await tester.tap(_key('cell-e5'));
      await tester.pump();
      expect(rig.controller.game.moves.map((m) => m.toUci()), [
        'e2e4',
        'e7e5',
      ], reason: 'move-animation: no move is lost to a slide');
      expect(
        _key('slide-e4'),
        findsNothing,
        reason: 'move-animation: a new move ends the running slide',
      );
      expect(_key('slide-e5'), findsOneWidget);
      await _slideOut(tester);
    });

    testWidgets('a pause ends a running slide', (tester) async {
      final rig = await _pump(tester);
      await _tapMove(tester, 'e2e4');
      await tester.pump(moveSlideDuration ~/ 3);
      rig.controller.pause();
      await tester.pump();
      expect(_key('slide-e4'), findsNothing);
      expect(_hidden(tester, 'e4'), isFalse);
    });

    testWidgets('a turning board turns once the slide has ended', (
      tester,
    ) async {
      await _pump(tester, options: const BoardOptions(rotateEachTurn: true));
      final whiteBelow = _centre(tester, 'a1').dy > _centre(tester, 'a8').dy;
      expect(whiteBelow, isTrue);
      await _tapMove(tester, 'e2e4');
      await tester.pump(moveSlideDuration ~/ 2);
      expect(
        _centre(tester, 'a1').dy > _centre(tester, 'a8').dy,
        isTrue,
        reason: 'move-animation: the board holds still while the move slides',
      );
      await _slideOut(tester);
      expect(
        _centre(tester, 'a1').dy < _centre(tester, 'a8').dy,
        isTrue,
        reason: 'move-animation: then it faces Black',
      );
    });
  });

  group('no replayed motion', () {
    testWidgets('a takeback shows no in-between frame', (tester) async {
      final rig = await _pump(tester);
      await _tapMove(tester, 'e2e4');
      await _slideOut(tester);
      expect(rig.controller.takeBack(), isTrue);
      await tester.pump();
      expect(_key('slide-e2'), findsNothing);
      expect(_key('slide-e4'), findsNothing);
      expect(_key('piece-e2'), findsOneWidget);
      expect(_hidden(tester, 'e2'), isFalse);
    });

    testWidgets('a takeback mid-slide ends it at once', (tester) async {
      final rig = await _pump(tester);
      await _tapMove(tester, 'e2e4');
      await tester.pump(moveSlideDuration ~/ 3);
      rig.controller.takeBack();
      await tester.pump();
      expect(_key('slide-e4'), findsNothing);
      expect(_hidden(tester, 'e2'), isFalse);
    });

    testWidgets('restart and a restored game place the pieces at once', (
      tester,
    ) async {
      final rig = await _pump(tester);
      final c = rig.controller;
      await _tapMove(tester, 'e2e4');
      await tester.pump(moveSlideDuration ~/ 3);
      await c.restart();
      await tester.pump();
      expect(_key('slide-e4'), findsNothing);
      expect(_key('piece-e2'), findsOneWidget);
      final saved = c.game.play(Move.fromUci(c.game.position, 'd2d4'));
      expect(c.restore(saved), isTrue);
      await tester.pump();
      expect(_key('slide-d4'), findsNothing);
      expect(_hidden(tester, 'd4'), isFalse);
    });
  });

  group('with motion off', () {
    testWidgets('Piece animations off: the piece is on its target on the '
        'next frame', (tester) async {
      await _pump(tester, options: const BoardOptions(animations: false));
      await _tapMove(tester, 'e2e4');
      expect(_key('slide-e4'), findsNothing);
      expect(_hidden(tester, 'e4'), isFalse);
    });

    testWidgets("the phone's remove-animations: the same, with the switch "
        'on', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await _pump(tester);
      await _tapMove(tester, 'e2e4');
      expect(_key('slide-e4'), findsNothing);
      expect(_hidden(tester, 'e4'), isFalse);
    });

    testWidgets('turning motion off mid-slide ends the slide', (tester) async {
      final rig = await _pump(tester);
      await _tapMove(tester, 'e2e4');
      await tester.pump(moveSlideDuration ~/ 3);
      rig.settings.updateBoard((o) => o.copyWith(animations: false));
      await tester.pump();
      await tester.pump();
      expect(_key('slide-e4'), findsNothing);
      expect(_hidden(tester, 'e4'), isFalse);
    });
  });
}
