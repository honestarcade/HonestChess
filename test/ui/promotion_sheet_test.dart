// The promotion sheet (#73) on the play screen: each of the four pieces,
// by tap and by drag, capturing or not; cancelling by the scrim and by
// Android's back leaves the position and the turn as they were; auto-queen
// never shows the sheet; and nothing under the card, on the board or in the
// tool row, responds while it is open.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:honest_chess/engine/engine.dart' hide play;
import 'package:honest_chess/ui/board/board_options.dart';
import 'package:honest_chess/ui/board/board_view.dart';
import 'package:honest_chess/ui/board/promotion_sheet.dart';
import 'package:honest_chess/ui/game/computer_turns.dart';
import 'package:honest_chess/ui/game/game_controller.dart';
import 'package:honest_chess/ui/game/game_screen.dart';
import 'package:honest_chess/ui/game/tool_row.dart';
import 'package:honest_chess/ui/theme/palette.dart';

import '../support/app_harness.dart';
import 'board/board_interaction_test.dart' show dragTo, centre, tap;
import 'game/computer_turns_test.dart' show asWhite, moves;
import 'game/fake_computer.dart';
import 'game/player_panel_test.dart' show play, pumpGame;

/// White pawn on e7, one step from promoting; a black rook on d8 to take.
const _white = '3r3k/4P3/8/8/8/8/8/K7 w - - 0 1';

/// Black pawn on e2, one step from promoting.
const _black = '7k/8/8/8/8/8/4p3/K7 b - - 0 1';

Future<GameController> pumpScreen(
  WidgetTester tester, {
  String fen = _white,
  BoardOptions options = const BoardOptions(),
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await pumpUnderScope(tester, GameScreen(options: options, fen: fen));
  return tester.state<GameScreenState>(find.byType(GameScreen)).controller;
}

/// Taps [from] then [to] and lets the sheet finish rising.
Future<void> tapMove(WidgetTester tester, String from, String to) async {
  await tap(tester, from);
  await tap(tester, to);
  await tester.pump(promotionEnterDuration);
}

Finder get card => find.byKey(const Key('promo-card'));

/// A point on the scrim clear of the card and of the top bar, whose pause
/// pill and status chip stay above the scrim.
const scrimSpot = Offset(20, topBarHeight + 20);

PieceKind? kindOn(GameController c, String square) =>
    c.state.position.pieceAt(Square.parse(square))?.kind;

void main() {
  const letters = {
    PieceKind.queen: 'q',
    PieceKind.rook: 'r',
    PieceKind.bishop: 'b',
    PieceKind.knight: 'n',
  };

  group('choosing', () {
    for (final MapEntry(key: kind, value: letter) in letters.entries) {
      testWidgets(
        'the Demo: e7-e8 offers four pieces, ${kind.name} is played',
        (tester) async {
          final c = await pumpScreen(tester);
          await tapMove(tester, 'e7', 'e8');
          expect(card, findsOneWidget, reason: 'promo: e7-e8 opens the sheet');
          expect(find.text('Promote to'), findsOneWidget);
          expect(find.text('PAWN TO E8'), findsOneWidget);
          for (final l in letters.values) {
            expect(find.byKey(Key('promo-$l')), findsOneWidget);
            final glyph = tester.widget<Text>(
              find.byKey(Key('promo-piece-$l')),
            );
            expect(
              glyph.style!.color,
              Palette.pieceWhite,
              reason: 'promo: a white pawn is offered white pieces',
            );
          }
          expect(
            kindOn(c, 'e7'),
            PieceKind.pawn,
            reason: 'promo: the pawn stays on e7 while the sheet is open',
          );
          expect(c.game.moves, isEmpty, reason: 'promo: nothing played yet');

          await tester.tap(find.byKey(Key('promo-$letter')));
          await tester.pumpAndSettle();
          expect(c.game.moves.single.toUci(), 'e7e8$letter');
          expect(
            kindOn(c, 'e8'),
            kind,
            reason: 'promo: e8 holds a ${kind.name}',
          );
          expect(kindOn(c, 'e7'), isNull, reason: 'promo: the pawn left e7');
          expect(card, findsNothing, reason: 'promo: the sheet has closed');
          expect(c.state.selection, isNull, reason: 'promo: nothing selected');
        },
      );
    }

    testWidgets('underpromotion by capture: exd8=N, dragged', (tester) async {
      final c = await pumpScreen(tester);
      await dragTo(tester, 'e7', centre(tester, 'd8'));
      await tester.pump(promotionEnterDuration);
      expect(find.text('PAWN TO D8'), findsOneWidget);
      expect(c.state.pendingPromotion, (
        from: Square.parse('e7'),
        to: Square.parse('d8'),
      ));
      await tester.tap(find.byKey(const Key('promo-n')));
      await tester.pumpAndSettle();
      expect(c.game.moves.single.toUci(), 'e7d8n');
      expect(c.game.moves.single.isCapture, isTrue);
      expect(kindOn(c, 'd8'), PieceKind.knight);
    });

    testWidgets('a black pawn is offered black pieces in the chosen style', (
      tester,
    ) async {
      final c = await pumpScreen(
        tester,
        fen: _black,
        options: const BoardOptions(pieceStyle: PieceStyle.outline),
      );
      await tapMove(tester, 'e2', 'e1');
      expect(find.text('PAWN TO E1'), findsOneWidget);
      final rook = tester.widget<Text>(find.byKey(const Key('promo-piece-r')));
      expect(rook.data, pieceGlyph(Piece.blackRook, PieceStyle.outline));
      expect(rook.style!.color, Palette.pieceBlack);
      await tester.tap(find.byKey(const Key('promo-r')));
      await tester.pumpAndSettle();
      expect(c.game.moves.single.toUci(), 'e2e1r');
      expect(c.state.position.pieceAt(Square.parse('e1')), Piece.blackRook);
    });

    testWidgets('a pressed choice shows the teal border only while held', (
      tester,
    ) async {
      await pumpScreen(tester);
      await tapMove(tester, 'e7', 'e8');
      Color edge() {
        final material = tester.widget<Material>(
          find
              .ancestor(
                of: find.byKey(const Key('promo-b')),
                matching: find.byType(Material),
              )
              .first,
        );
        return (material.shape! as RoundedRectangleBorder).side.color;
      }

      expect(edge(), Palette.choiceEdge, reason: 'promo: at rest, no teal');
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('promo-b'))),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(edge(), Palette.teal, reason: 'promo: pressed, teal border');
      await gesture.cancel();
      await tester.pump();
      expect(edge(), Palette.choiceEdge, reason: 'promo: released, no teal');
    });
  });

  group('cancelling', () {
    Future<void> expectUntouched(WidgetTester tester, GameController c) async {
      await tester.pumpAndSettle();
      expect(card, findsNothing, reason: 'cancel: the sheet has closed');
      expect(c.game.moves, isEmpty, reason: 'cancel: no move was played');
      expect(c.state.position.toFen(), _white, reason: 'cancel: unchanged');
      expect(c.game.sideToMove, Colour.white, reason: 'cancel: still White');
      expect(c.state.selection, isNull, reason: 'cancel: pawn put down');
      expect(c.inputLocked, isFalse, reason: 'cancel: the board is live');
      await tapMove(tester, 'e7', 'e8');
      expect(card, findsOneWidget, reason: 'cancel: the pawn can try again');
    }

    testWidgets('a tap on the scrim cancels', (tester) async {
      final c = await pumpScreen(tester);
      await tapMove(tester, 'e7', 'e8');
      await tester.tapAt(scrimSpot);
      await expectUntouched(tester, c);
    });

    testWidgets('a tap on the board under the scrim only cancels', (
      tester,
    ) async {
      final c = await pumpScreen(tester);
      await tapMove(tester, 'e7', 'e8');
      // A square under the scrim, clear of the card.
      final clear = tester.getRect(card);
      final square = [
        for (final rank in '18'.split(''))
          for (final file in 'ah'.split('')) '$file$rank',
      ].firstWhere((sq) => !clear.contains(centre(tester, sq)));
      await tester.tapAt(centre(tester, square));
      await expectUntouched(tester, c);
    });

    testWidgets('Android back cancels and stays on the play screen', (
      tester,
    ) async {
      final c = await pumpScreen(tester);
      await tapMove(tester, 'e7', 'e8');
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byType(GameScreen), findsOneWidget);
      await expectUntouched(tester, c);
    });

    testWidgets('a drag to e8, cancelled, leaves the pawn on e7', (
      tester,
    ) async {
      final c = await pumpScreen(tester);
      await dragTo(tester, 'e7', centre(tester, 'e8'));
      await tester.pump(promotionEnterDuration);
      expect(card, findsOneWidget);
      await tester.tapAt(scrimSpot);
      await expectUntouched(tester, c);
      expect(find.byKey(const Key('piece-e7')), findsOneWidget);
    });
  });

  group('the tool row under the card', () {
    // Against the computer, a move each already played, so every tool is
    // live: Takeback would undo two plies, Restart would reseed, Resign
    // would end the game and New would pause it for the setup screen.
    for (final tool in Tool.values) {
      testWidgets('${tool.name} under the scrim only cancels', (tester) async {
        final fakes = FakeComputers();
        final h = await pumpGame(
          tester,
          mode: asWhite,
          fen: _white,
          computer: fakes,
        );
        final c = h.controller;
        await play(tester, c, 'a1a2');
        fakes.current.last.move('h8h7');
        await h.clock.advance(minThinkTime);
        expect(moves(c), ['a1a2', 'h8h7'], reason: 'test: a move each');
        await tapMove(tester, 'e7', 'e8');
        expect(card, findsOneWidget, reason: 'test: the card is open');

        await tester.tap(find.byKey(tool.key), warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(
          c.state.pendingPromotion,
          isNull,
          reason: 'promo-tools: ${tool.name} under the scrim cancels',
        );
        expect(moves(c), [
          'a1a2',
          'h8h7',
        ], reason: 'promo-tools: ${tool.name} under the scrim plays nothing');
        expect(
          c.game.mode,
          asWhite,
          reason: 'promo-tools: ${tool.name} keeps the mode and the seed',
        );
        expect(
          c.game.isOver,
          isFalse,
          reason: 'promo-tools: ${tool.name} under the scrim ends nothing',
        );
        expect(
          c.state.paused,
          isFalse,
          reason: 'promo-tools: ${tool.name} under the scrim pauses nothing',
        );
        expect(kindOn(c, 'e7'), PieceKind.pawn);
        expect(find.byType(GameScreen), findsOneWidget);
      });
    }
  });

  testWidgets('auto-queen: no sheet, the pawn becomes a queen', (tester) async {
    final c = await pumpScreen(
      tester,
      options: const BoardOptions(autoQueen: true),
    );
    await tap(tester, 'e7');
    await tap(tester, 'e8');
    expect(card, findsNothing, reason: 'auto-queen: the sheet never opens');
    expect(c.state.pendingPromotion, isNull);
    await tester.pumpAndSettle();
    expect(card, findsNothing);
    expect(c.game.moves.single.toUci(), 'e7e8q');
    expect(kindOn(c, 'e8'), PieceKind.queen);
  });

  testWidgets('the choices: large, two by two, read queen to knight', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpScreen(tester);
    await tapMove(tester, 'e7', 'e8');
    Rect at(String letter) => tester.getRect(find.byKey(Key('promo-$letter')));
    final (q, r, b, n) = (at('q'), at('r'), at('b'), at('n'));
    expect(q.top, r.top, reason: 'promo: queen and rook are not one row');
    expect(b.top, n.top, reason: 'promo: bishop and knight are not one row');
    expect(
      b.top,
      greaterThanOrEqualTo(q.bottom),
      reason: 'promo: the four choices are not two rows',
    );
    expect(q.left, b.left, reason: 'promo: queen is not above bishop');
    expect(r.left, n.left, reason: 'promo: rook is not above knight');
    expect(r.left, greaterThanOrEqualTo(q.right), reason: 'promo: rook side');
    for (final choice in [q, r, b, n]) {
      expect(choice.size, q.size, reason: 'promo: the choices differ');
      expect(choice.shortestSide, greaterThanOrEqualTo(48));
    }
    for (final letter in ['q', 'r', 'b', 'n']) {
      final glyph = tester.widget<Text>(find.byKey(Key('promo-piece-$letter')));
      expect(
        glyph.style!.fontSize,
        promotionGlyphSize,
        reason: 'promo: the $letter glyph is not promotionGlyphSize',
      );
      final label = tester.widget<Text>(find.byKey(Key('promo-label-$letter')));
      expect(
        label.style!.fontSize,
        promotionLabelSize,
        reason: 'promo: the $letter label is not promotionLabelSize',
      );
    }
    expect(
      promotionGlyphSize,
      greaterThanOrEqualTo(40),
      reason: 'promo: glyphs smaller than 40 dp',
    );
    expect(
      promotionLabelSize,
      greaterThanOrEqualTo(12),
      reason: 'promo: labels smaller than 12 dp',
    );
    final order = <String>[];
    void walk(SemanticsNode node) {
      if (node.label.startsWith('Promote to ')) order.add(node.label);
      for (final child in node.debugListChildrenInOrder(
        DebugSemanticsDumpOrder.traversalOrder,
      )) {
        walk(child);
      }
    }

    walk(
      tester
          .binding
          .renderViews
          .first
          .owner!
          .semanticsOwner!
          .rootSemanticsNode!,
    );
    expect(order, [
      'Promote to queen',
      'Promote to rook',
      'Promote to bishop',
      'Promote to knight',
    ], reason: 'promo: read out of row order');
    semantics.dispose();
  });

  testWidgets('screen readers hear the card, the choices and the scrim', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpScreen(tester);
    await tapMove(tester, 'e7', 'e8');
    expect(find.bySemanticsLabel('Promote pawn on E8'), findsOneWidget);
    expect(find.bySemanticsLabel('Cancel promotion'), findsOneWidget);
    for (final name in ['queen', 'rook', 'bishop', 'knight']) {
      expect(find.bySemanticsLabel('Promote to $name'), findsOneWidget);
    }
    expect(
      tester.getSize(find.byKey(const Key('promo-n'))).height,
      greaterThanOrEqualTo(48),
      reason: 'promo: a choice is at least a 48 dp target',
    );
    semantics.dispose();
  });
}
