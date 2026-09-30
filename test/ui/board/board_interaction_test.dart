// The playable board (#72): taps and drags on real engine positions, the
// highlight layers as the design draws them, and spring-back on a drop
// that cannot be played.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:honest_chess/engine/engine.dart';
import 'package:honest_chess/ui/board/board_interaction.dart';
import 'package:honest_chess/ui/board/board_options.dart';
import 'package:honest_chess/ui/game/game_controller.dart';
import 'package:honest_chess/ui/theme/palette.dart';

Square sq(String name) => Square.parse(name);

Future<GameController> pumpPlayable(
  WidgetTester tester, {
  String? fen,
  GameMode mode = const TwoPlayer(),
  BoardOptions options = const BoardOptions(),
  Colour bottom = Colour.white,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final controller = GameController(fen: fen, mode: mode, options: options);
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: BoardInteraction(controller: controller, bottom: bottom),
      ),
    ),
  );
  return controller;
}

Offset centre(WidgetTester tester, String square) =>
    tester.getCenter(find.byKey(Key('cell-$square')));

Future<void> tap(WidgetTester tester, String square) async {
  await tester.tap(find.byKey(Key('cell-$square')));
  await tester.pump();
}

/// Presses on [from], drags in steps to [to] and lets go there.
Future<void> dragTo(WidgetTester tester, String from, Offset to) async {
  final start = centre(tester, from);
  final gesture = await tester.startGesture(start);
  await tester.pump();
  for (var i = 1; i <= 5; i++) {
    await gesture.moveTo(Offset.lerp(start, to, i / 5)!);
    await tester.pump();
  }
  await gesture.up();
  await tester.pump();
}

Set<String> keyed(WidgetTester tester, String prefix) => {
  for (final e in find.byWidgetPredicate((w) {
    final key = w.key;
    return key is ValueKey<String> && key.value.startsWith(prefix);
  }).evaluate())
    (e.widget.key! as ValueKey<String>).value.substring(prefix.length),
};

void main() {
  group('taps', () {
    testWidgets('the Demo: e2 shows e3 and e4, e4 moves and tints both', (
      tester,
    ) async {
      final c = await pumpPlayable(tester);
      await tap(tester, 'e2');
      expect(keyed(tester, 'dot-'), {'e3', 'e4'});
      expect(keyed(tester, 'ring-selected-'), {'e2'}, reason: 'tap: teal ring');
      final tint = tester.widget<ColoredBox>(find.byKey(const Key('tint-e2')));
      expect(tint.color, Palette.selectedTint, reason: 'tap: teal tint');
      await tap(tester, 'e4');
      expect(c.game.moves.single.toUci(), 'e2e4');
      expect(keyed(tester, 'dot-'), isEmpty, reason: 'move: dots gone');
      expect(keyed(tester, 'tint-'), {'e2', 'e4'});
      for (final name in ['e2', 'e4']) {
        expect(
          tester.widget<ColoredBox>(find.byKey(Key('tint-$name'))).color,
          Palette.lastMoveTint,
          reason: 'last move: $name tinted',
        );
      }
      expect(find.byKey(const Key('piece-e4')), findsOneWidget);
      expect(find.byKey(const Key('piece-e2')), findsNothing);
    });

    testWidgets('tap again puts down; a non-target clears; switch works', (
      tester,
    ) async {
      final c = await pumpPlayable(tester);
      await tap(tester, 'g1');
      await tap(tester, 'g1');
      expect(c.state.selection, isNull);
      expect(keyed(tester, 'dot-'), isEmpty);
      await tap(tester, 'g1');
      await tap(tester, 'b1');
      expect(c.state.selection, sq('b1'), reason: 'tap: switched');
      expect(keyed(tester, 'dot-'), {'a3', 'c3'});
      await tap(tester, 'b5');
      expect(c.state.selection, isNull, reason: 'tap: non-target clears');
      expect(keyed(tester, 'tint-'), isEmpty);
      expect(c.game.moves, isEmpty, reason: 'tap: no move was made');
    });

    testWidgets('castling by tapping the king, then two squares along', (
      tester,
    ) async {
      final c = await pumpPlayable(
        tester,
        fen: 'r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1',
      );
      await tap(tester, 'e1');
      await tap(tester, 'g1');
      expect(c.game.moves.single.toUci(), 'e1g1');
      expect(find.byKey(const Key('piece-f1')), findsOneWidget);
      expect(find.byKey(const Key('piece-h1')), findsNothing);
    });

    testWidgets('a tap during the opponent\'s turn changes nothing', (
      tester,
    ) async {
      final c = await pumpPlayable(
        tester,
        mode: const VsComputer(
          playerColour: Colour.white,
          step: Strength.club,
          seed: 1,
        ),
        fen: 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1',
      );
      await tap(tester, 'e7');
      await tap(tester, 'e5');
      await dragTo(tester, 'g8', centre(tester, 'f6'));
      expect(c.state.selection, isNull);
      expect(keyed(tester, 'tint-'), isEmpty);
      expect(keyed(tester, 'dot-'), isEmpty);
      expect(c.game.moves, isEmpty);
      expect(find.byKey(const Key('spring-back')), findsNothing);
    });
  });

  group('dots and rings', () {
    testWidgets('dots on quiet targets and rings on captures, and only', (
      tester,
    ) async {
      const fen =
          'r1bqkb1r/pppp1ppp/2n2n2/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR w KQkq - 4 4';
      await pumpPlayable(tester, fen: fen);
      await tap(tester, 'h5');
      final moves = legalMoves(Position.fromFen(fen))
          .where((m) => m.from == sq('h5'));
      expect(keyed(tester, 'dot-'), {
        for (final m in moves.where((m) => !m.isCapture)) m.to.name,
      });
      expect(keyed(tester, 'ring-capture-'), {
        for (final m in moves.where((m) => m.isCapture)) m.to.name,
      });
      expect(keyed(tester, 'ring-capture-'), {'e5', 'f7', 'h7'});
      expect(keyed(tester, 'dot-'), isNot(contains('h8')));
      final ring = tester.widget<DecoratedBox>(
        find.byKey(const Key('ring-capture-f7')),
      );
      final side = (ring.decoration as BoxDecoration).border!.top;
      expect(
        side.color,
        shapeInk(BoardShape.captureRing, onLight: true, theme: BoardTheme.navy),
        reason: 'ring: f7 is light, so its ring is the light ink',
      );
      final dot = tester.getSize(find.byKey(const Key('dot-h6')));
      expect(dot, const Size(14, 14), reason: 'dot: round(46 × 0.3)');
    });

    testWidgets('with dots off none show, and a tap still moves', (
      tester,
    ) async {
      final c = await pumpPlayable(
        tester,
        options: const BoardOptions(legalMoveDots: false),
      );
      await tap(tester, 'e2');
      expect(keyed(tester, 'dot-'), isEmpty);
      expect(keyed(tester, 'ring-capture-'), isEmpty);
      expect(keyed(tester, 'ring-selected-'), {'e2'});
      await tap(tester, 'e4');
      expect(c.game.moves.single.toUci(), 'e2e4');
    });
  });

  group('drags', () {
    testWidgets('drag g1 to f3 plays it', (tester) async {
      final c = await pumpPlayable(tester);
      await dragTo(tester, 'g1', centre(tester, 'f3'));
      expect(c.game.moves.single.toUci(), 'g1f3');
      expect(find.byKey(const Key('piece-f3')), findsOneWidget);
      expect(find.byKey(const Key('spring-back')), findsNothing);
    });

    testWidgets('mid-drag: dots show, the origin is faint, the piece big', (
      tester,
    ) async {
      await pumpPlayable(tester);
      final start = centre(tester, 'g1');
      final gesture = await tester.startGesture(start);
      await gesture.moveTo(start + const Offset(0, -40));
      await tester.pump();
      await gesture.moveTo(start + const Offset(0, -60));
      await tester.pump();
      expect(keyed(tester, 'dot-'), {'f3', 'h3'});
      final feedback = find.byKey(const Key('drag-feedback'));
      expect(feedback, findsOneWidget);
      final rect = tester.getRect(feedback);
      expect(rect.size, const Size(46, 46));
      expect(
        rect.center,
        start + const Offset(0, -60 - dragLift),
        reason: 'drag: lifted above the finger',
      );
      // The outermost: the glyph inside has a Transform of its own.
      final scale = tester.widget<Transform>(
        find.descendant(of: feedback, matching: find.byType(Transform)).first,
      );
      expect(scale.transform.getMaxScaleOnAxis(), closeTo(dragScale, 1e-9));
      expect(
        find.ancestor(
          of: find.byKey(const Key('piece-g1')),
          matching: find.byWidgetPredicate(
            (w) => w is Opacity && w.opacity == 0.3,
          ),
        ),
        findsOneWidget,
        reason: 'drag: the origin shows the piece at 30%',
      );
      await gesture.up();
      await tester.pumpAndSettle();
    });

    for (final (name, target) in [
      ('an illegal square', 'g4'),
      ('its own side\'s piece', 'e2'),
    ]) {
      testWidgets('a drop on $name springs back and changes nothing', (
        tester,
      ) async {
        final c = await pumpPlayable(tester);
        final before = c.state.position.toFen();
        await dragTo(tester, 'g1', centre(tester, target));
        expect(find.byKey(const Key('spring-back')), findsOneWidget);
        await tester.pump(springBackDuration ~/ 2);
        final mid = tester.getTopLeft(find.byKey(const Key('spring-back')));
        final home = tester.getTopLeft(find.byKey(const Key('cell-g1')));
        expect(mid, isNot(home), reason: 'spring: still on its way');
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('spring-back')), findsNothing);
        expect(c.state.position.toFen(), before);
        expect(c.game.moves, isEmpty);
        expect(c.state.selection, isNull, reason: 'drop: clears selection');
        expect(find.byKey(const Key('piece-g1')), findsOneWidget);
      });
    }

    testWidgets('a drop off the board springs back and changes nothing', (
      tester,
    ) async {
      final c = await pumpPlayable(tester);
      await dragTo(tester, 'g1', const Offset(195, 800));
      expect(find.byKey(const Key('spring-back')), findsOneWidget);
      await tester.pumpAndSettle();
      expect(c.game.moves, isEmpty);
      expect(c.state.selection, isNull);
    });

    testWidgets('a drop on its own square keeps the selection', (tester) async {
      final c = await pumpPlayable(tester);
      final start = centre(tester, 'g1');
      final gesture = await tester.startGesture(start);
      await gesture.moveTo(start + const Offset(30, 0));
      await tester.pump();
      await gesture.moveTo(start);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(c.state.selection, sq('g1'));
      expect(c.game.moves, isEmpty);
      expect(find.byKey(const Key('spring-back')), findsNothing);
    });

    testWidgets('a position change mid-drag returns the piece unplayed', (
      tester,
    ) async {
      final c = await pumpPlayable(tester);
      final start = centre(tester, 'g1');
      final gesture = await tester.startGesture(start);
      await gesture.moveTo(start + const Offset(0, -40));
      await tester.pump();
      expect(c.state.selection, sq('g1'), reason: 'drag: picked up');
      c.move(sq('g1'), sq('h3'));
      await tester.pump();
      await gesture.moveTo(centre(tester, 'f3'));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(c.game.moves.map((m) => m.toUci()), [
        'g1h3',
      ], reason: 'drag: the stale drop played nothing');
      expect(c.state.selection, isNull);
    });

    testWidgets('castling by dropping the king two squares along', (
      tester,
    ) async {
      final c = await pumpPlayable(
        tester,
        fen: 'r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1',
      );
      await dragTo(tester, 'e1', centre(tester, 'c1'));
      expect(c.game.moves.single.toUci(), 'e1c1');
      expect(find.byKey(const Key('piece-d1')), findsOneWidget);
    });

    testWidgets('a promotion by drag opens pending with the pawn in place', (
      tester,
    ) async {
      final c = await pumpPlayable(
        tester,
        fen: '8/P7/8/8/8/8/7p/K6k w - - 0 60',
      );
      await dragTo(tester, 'a7', centre(tester, 'a8'));
      expect(c.state.pendingPromotion, (from: sq('a7'), to: sq('a8')));
      expect(find.byKey(const Key('piece-a7')), findsOneWidget);
      expect(find.byKey(const Key('spring-back')), findsNothing);
    });
  });

  group('tints', () {
    testWidgets('last-move highlight off: no tint after a move', (
      tester,
    ) async {
      await pumpPlayable(
        tester,
        options: const BoardOptions(lastMoveHighlight: false),
      );
      await tap(tester, 'e2');
      await tap(tester, 'e4');
      expect(keyed(tester, 'tint-'), isEmpty);
    });

    for (final flag in [true, false]) {
      testWidgets('the check flag ${flag ? 'reddens' : 'leaves'} the king', (
        tester,
      ) async {
        await pumpPlayable(
          tester,
          fen: '4k3/8/8/8/8/8/4r3/4K3 w - - 0 1',
          options: BoardOptions(flagCheck: flag),
        );
        if (flag) {
          expect(keyed(tester, 'tint-'), {'e1'});
          expect(
            tester.widget<ColoredBox>(find.byKey(const Key('tint-e1'))).color,
            Palette.checkTint,
          );
        } else {
          expect(keyed(tester, 'tint-'), isEmpty);
        }
      });
    }
  });

  testWidgets('squares name themselves and what stands on them', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpPlayable(tester);
    expect(find.bySemanticsLabel('g1, white knight'), findsOneWidget);
    expect(find.bySemanticsLabel('e8, black king'), findsOneWidget);
    expect(find.bySemanticsLabel('e4, empty'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('with Black at the bottom the taps land on the right squares', (
    tester,
  ) async {
    final c = await pumpPlayable(
      tester,
      bottom: Colour.black,
      fen: 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1',
    );
    await tap(tester, 'e7');
    await tap(tester, 'e5');
    expect(c.game.moves.single.toUci(), 'e7e5');
  });
}
