// The tool row under the board (#76): Takeback, Restart, Resign and New,
// and New's temporary picker. The complements: a disabled tool does
// nothing when tapped, a cancelled picker leaves the game as it was, and a
// tool glyph is never left to a font the app does not bundle.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:honest_chess/engine/engine.dart' hide play;
import 'package:honest_chess/ui/board/board_options.dart';
import 'package:honest_chess/ui/game/computer_turns.dart';
import 'package:honest_chess/ui/game/tool_row.dart';
import 'package:honest_chess/ui/theme/palette.dart';

import '../../flutter_test_config.dart';
import '../board/board_interaction_test.dart' show centre, dragTo, tap;
import '../piece_font_test.dart' show cmapCodePoints;
import 'computer_turns_test.dart' show asWhite, moves, pumpVs;
import 'fake_computer.dart';
import 'player_panel_test.dart' show FakeClock, clockOf, play, pumpGame, text;

Future<void> press(WidgetTester tester, Tool tool) async {
  await tester.tap(find.byKey(tool.key));
  await tester.pump();
}

bool enabled(WidgetTester tester, Tool tool) =>
    tester.widget<InkWell>(find.byKey(tool.key)).onTap != null;

double opacity(WidgetTester tester, Tool tool) => tester
    .widget<Opacity>(
      find.ancestor(of: find.byKey(tool.key), matching: find.byType(Opacity)),
    )
    .opacity;

/// Waits out the picker's entry or exit: the frame that starts it, its
/// length, and the frame that removes it.
Future<void> sheetMotion(WidgetTester tester, FakeClock clock) async {
  await tester.pump();
  await clock.advance(const Duration(milliseconds: 400));
  await tester.pump();
}

/// Opens New's picker.
Future<void> openPicker(WidgetTester tester, FakeClock clock) async {
  await press(tester, Tool.newGame);
  await sheetMotion(tester, clock);
}

Future<void> choose(WidgetTester tester, FakeClock clock, String key) async {
  await tester.tap(find.byKey(Key(key)));
  await sheetMotion(tester, clock);
}

void main() {
  group('the row', () {
    testWidgets('four tools in the design\'s order, New accented', (
      tester,
    ) async {
      await pumpGame(tester);
      final lefts = [
        for (final tool in Tool.values)
          tester.getTopLeft(find.byKey(tool.key)).dx,
      ];
      expect(lefts, orderedEquals([...lefts]..sort()));
      for (final tool in Tool.values) {
        expect(find.text(tool.label), findsOneWidget);
        expect(
          tester.getSize(find.byKey(tool.key)).height,
          toolHeight,
          reason: 'tools: ${tool.name} is 50 dp high',
        );
      }
      final newMaterial = tester.widget<Material>(
        find
            .ancestor(
              of: find.byKey(Tool.newGame.key),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(newMaterial.color, Palette.accentFill);
      final restart = tester.widget<Material>(
        find
            .ancestor(
              of: find.byKey(Tool.restart.key),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(restart.color, Palette.toolFill);
      expect(
        tester.getBottomLeft(find.byKey(const Key('panel-white'))).dy,
        lessThan(tester.getTopLeft(find.byKey(Tool.takeback.key)).dy),
        reason: 'tools: the row sits under your panel',
      );
      expect(
        tester.getSize(find.byKey(const Key('board'))).width,
        368,
        reason: 'tools: a 390×844 phone keeps the eight whole squares',
      );
    });

    testWidgets('every glyph is drawn by a bundled font or a Material icon', (
      tester,
    ) async {
      final plex = cmapCodePoints(
        File(testFonts['PlexMono']![1]).readAsBytesSync(),
      );
      final outfit = cmapCodePoints(
        File(testFonts['Outfit']![2]).readAsBytesSync(),
      );
      await pumpGame(tester);
      for (final tool in Tool.values) {
        final code = tool.glyph.runes.single;
        final drawn = tester.widget(find.byKey(Key('tool-glyph-${tool.name}')));
        final fallback = tool.fallback;
        if (fallback == null) {
          expect(
            plex,
            contains(code),
            reason: 'tool-glyph: ${tool.name}\'s ${tool.glyph} is in PlexMono',
          );
          expect(
            (drawn as Text).style!.fontFamily,
            toolGlyphFamily,
            reason: 'tool-glyph: ${tool.name} is drawn in PlexMono',
          );
          expect(drawn.data, tool.glyph);
        } else {
          expect(
            plex.contains(code) || outfit.contains(code),
            isFalse,
            reason:
                'tool-glyph: ${tool.name} falls back only for a glyph the '
                'bundled fonts lack',
          );
          expect((drawn as Icon).icon, fallback);
        }
      }
    });

    testWidgets('screen readers hear the four tools', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpGame(tester);
      for (final label in ['Take back', 'Restart', 'Resign', 'New game']) {
        expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
      }
      expect(
        tester.getSemantics(find.bySemanticsLabel('Take back')),
        matchesSemantics(
          label: 'Take back',
          isButton: true,
          hasEnabledState: true,
        ),
        reason: 'tools: nothing to take back reads as disabled',
      );
      handle.dispose();
    });
  });

  group('takeback', () {
    testWidgets('disabled with nothing to undo: tapping changes nothing', (
      tester,
    ) async {
      final h = await pumpGame(tester, timeControl: Timed.rapid);
      final before = h.controller.game;
      expect(enabled(tester, Tool.takeback), isFalse);
      expect(opacity(tester, Tool.takeback), disabledToolOpacity);
      await press(tester, Tool.takeback);
      expect(
        identical(h.controller.game, before),
        isTrue,
        reason: 'takeback: a disabled tap changes nothing',
      );
    });

    testWidgets('disabled with the option off: the move stays', (tester) async {
      final h = await pumpGame(
        tester,
        options: const BoardOptions(takebackAllowed: false),
      );
      await play(tester, h.controller, 'e2e4');
      expect(enabled(tester, Tool.takeback), isFalse);
      expect(opacity(tester, Tool.takeback), disabledToolOpacity);
      await press(tester, Tool.takeback);
      expect(moves(h.controller), ['e2e4'], reason: 'takeback: turned off');
      expect(enabled(tester, Tool.restart), isTrue);
      expect(opacity(tester, Tool.restart), 1);
    });

    testWidgets('vs the computer: back to your turn, its reply undone too', (
      tester,
    ) async {
      final (h, fakes) = await pumpVs(tester);
      final c = h.controller;
      await play(tester, c, 'e2e4');
      fakes.current.last.move('e7e5');
      await h.clock.advance(minThinkTime);
      expect(moves(c), ['e2e4', 'e7e5']);
      await press(tester, Tool.takeback);
      expect(moves(c), isEmpty, reason: 'takeback: two plies vs computer');
      expect(c.game.sideToMove, Colour.white);
      expect(c.state.thinking, isFalse);
      expect(c.inputLocked, isFalse, reason: 'takeback: your turn again');
    });

    testWidgets('vs the computer while it thinks: your move only', (
      tester,
    ) async {
      final (h, fakes) = await pumpVs(tester);
      final c = h.controller;
      await play(tester, c, 'e2e4');
      expect(c.state.thinking, isTrue);
      expect(enabled(tester, Tool.takeback), isTrue);
      await press(tester, Tool.takeback);
      expect(moves(c), isEmpty);
      expect(fakes.current.cancels, 1, reason: 'takeback: search cancelled');
      await h.clock.advance(minThinkTime);
    });

    testWidgets('two players: one move at a time, either side, clocks held', (
      tester,
    ) async {
      final h = await pumpGame(tester, timeControl: Timed.rapid);
      final c = h.controller;
      await play(tester, c, 'e2e4');
      await play(tester, c, 'e7e5');
      await press(tester, Tool.takeback);
      expect(moves(c), ['e2e4'], reason: 'takeback: one ply in two-player');
      expect(c.game.sideToMove, Colour.black);
      final held = (c.remaining(Colour.white), c.remaining(Colour.black));
      await h.clock.advance(const Duration(seconds: 3));
      expect(
        (c.remaining(Colour.white), c.remaining(Colour.black)),
        held,
        reason: 'takeback: the clocks stay held until the next move',
      );
      await press(tester, Tool.takeback);
      expect(moves(c), isEmpty, reason: 'takeback: the other side too');
      expect(enabled(tester, Tool.takeback), isFalse);
    });

    testWidgets('clears the selection', (tester) async {
      final h = await pumpGame(tester);
      await play(tester, h.controller, 'e2e4');
      await tap(tester, 'e7');
      expect(h.controller.state.selection, Square.parse('e7'));
      await press(tester, Tool.takeback);
      expect(h.controller.state.selection, isNull);
    });
  });

  group('restart', () {
    testWidgets('resets the board and the clocks, same kind of game', (
      tester,
    ) async {
      final h = await pumpGame(tester, timeControl: Timed.rapid);
      final c = h.controller;
      await play(tester, c, 'e2e4');
      await h.clock.advance(const Duration(seconds: 7));
      await play(tester, c, 'e7e5');
      await tap(tester, 'g1');
      expect(clockOf(tester, Colour.black), isNot('10:00'));
      await press(tester, Tool.restart);
      expect(moves(c), isEmpty);
      expect(c.game.position.toFen(), Position.initialFen);
      expect(c.game.mode, const TwoPlayer());
      expect(c.game.clock.control, Timed.rapid);
      expect(clockOf(tester, Colour.white), '10:00');
      expect(clockOf(tester, Colour.black), '10:00');
      expect(c.state.selection, isNull, reason: 'restart: selection cleared');
    });

    testWidgets('vs the computer: a new computer with a fresh seed', (
      tester,
    ) async {
      final (h, fakes) = await pumpVs(tester);
      await play(tester, h.controller, 'e2e4');
      expect(enabled(tester, Tool.restart), isTrue, reason: 'while thinking');
      await press(tester, Tool.restart);
      expect(fakes.built, hasLength(2));
      expect(fakes.built.first.cancels, 1);
      final mode = h.controller.game.mode as VsComputer;
      expect((mode.playerColour, mode.step), (Colour.white, Strength.club));
      expect(mode.seed, isNot(asWhite.seed), reason: 'restart: a new seed');
      expect(moves(h.controller), isEmpty);
    });

    testWidgets('closes the promotion card', (tester) async {
      final h = await pumpGame(tester, fen: '8/4P3/8/8/8/8/k7/4K3 w - - 0 1');
      expect(h.controller.move(Square.parse('e7'), Square.parse('e8')), true);
      await tester.pump();
      expect(h.controller.state.pendingPromotion, isNotNull);
      h.controller.restart();
      await tester.pump();
      expect(h.controller.state.pendingPromotion, isNull);
    });
  });

  group('resign', () {
    testWidgets('two players: the side to move resigns at once', (
      tester,
    ) async {
      final h = await pumpGame(tester, timeControl: Timed.rapid);
      final c = h.controller;
      await play(tester, c, 'e2e4');
      await press(tester, Tool.resign);
      expect(
        c.game.status,
        const Win(Colour.white, GameEndReason.resignation),
        reason: 'resign: black was to move',
      );
      expect(text(tester, 'status-text'), 'RESIGNED');
      expect(enabled(tester, Tool.resign), isFalse, reason: 'resign: once');
      expect(opacity(tester, Tool.resign), disabledToolOpacity);
      final over = c.game;
      await press(tester, Tool.resign);
      expect(
        identical(c.game, over),
        isTrue,
        reason: 'resign: no-op once over',
      );
      expect(enabled(tester, Tool.restart), isTrue);
      expect(enabled(tester, Tool.newGame), isTrue);
      expect(enabled(tester, Tool.takeback), isTrue);
      await press(tester, Tool.takeback);
      expect(c.game.isOver, isFalse, reason: 'takeback: re-opens the game');
      expect(moves(c), ['e2e4']);
    });

    testWidgets('vs the computer: always you, even on its turn', (
      tester,
    ) async {
      final (h, fakes) = await pumpVs(tester);
      await play(tester, h.controller, 'e2e4');
      await press(tester, Tool.resign);
      expect(
        h.controller.game.status,
        const Win(Colour.black, GameEndReason.resignation),
      );
      expect(fakes.current.cancels, 1, reason: 'resign: search cancelled');
    });
  });

  group('new', () {
    testWidgets('the picker offers the two default games', (tester) async {
      final h = await pumpGame(tester);
      await openPicker(tester, h.clock);
      expect(find.text('New game'), findsOneWidget);
      expect(find.text('vs Computer'), findsOneWidget);
      expect(find.text('CLUB · WHITE · RAPID 10+5'), findsOneWidget);
      expect(find.text('Two players'), findsOneWidget);
      expect(find.text('RAPID 10+5'), findsOneWidget);
      expect(
        find.bySemanticsLabel('vs Computer — Club · White · Rapid 10+5'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Two players — Rapid 10+5'), findsOneWidget);
    });

    testWidgets('cancelling the picker changes nothing', (tester) async {
      final h = await pumpGame(tester);
      await play(tester, h.controller, 'e2e4');
      await tap(tester, 'e7');
      final before = h.controller.game;
      await openPicker(tester, h.clock);
      await tester.tapAt(const Offset(195, 60));
      await sheetMotion(tester, h.clock);
      expect(find.text('New game'), findsNothing, reason: 'picker: closed');
      expect(identical(h.controller.game, before), isTrue);
      expect(h.controller.state.selection, Square.parse('e7'));
      await openPicker(tester, h.clock);
      await tester.binding.handlePopRoute();
      await sheetMotion(tester, h.clock);
      expect(find.text('New game'), findsNothing, reason: 'picker: back');
      expect(identical(h.controller.game, before), isTrue);
    });

    testWidgets('the clocks keep running while the picker is open', (
      tester,
    ) async {
      final h = await pumpGame(tester, timeControl: Timed.rapid);
      await play(tester, h.controller, 'e2e4');
      await openPicker(tester, h.clock);
      await h.clock.advance(const Duration(seconds: 5));
      expect(
        h.controller.remaining(Colour.black),
        lessThan(const Duration(minutes: 10) - const Duration(seconds: 5)),
      );
    });

    testWidgets('a game ending while the picker is open leaves it open', (
      tester,
    ) async {
      final h = await pumpGame(tester, timeControl: Timed(1, 0));
      await play(tester, h.controller, 'e2e4');
      await openPicker(tester, h.clock);
      await h.clock.advance(const Duration(minutes: 1));
      await tester.pump();
      expect(h.controller.state.over, isTrue, reason: 'test: black flagged');
      expect(find.text('New game'), findsOneWidget, reason: 'picker: stays');
      await choose(tester, h.clock, 'new-two-players');
      expect(h.controller.state.over, isFalse, reason: 'new: a fresh game');
    });

    testWidgets('vs Computer starts Club, you White, Rapid 10+5', (
      tester,
    ) async {
      final fakes = FakeComputers();
      final h = await pumpGame(tester, computer: fakes);
      await play(tester, h.controller, 'e2e4');
      await openPicker(tester, h.clock);
      await choose(tester, h.clock, 'new-vs-computer');
      final c = h.controller;
      final mode = c.game.mode as VsComputer;
      expect((mode.playerColour, mode.step), (Colour.white, Strength.club));
      expect(c.game.clock.control, Timed.rapid);
      expect(moves(c), isEmpty);
      expect(fakes.built, hasLength(1), reason: 'new: its own computer');
      expect(fakes.current.seed, mode.seed);
      expect(find.text('❚❚ vs Club'), findsOneWidget);
      expect(text(tester, 'name-white'), 'You');
      expect(text(tester, 'name-black'), 'Club');
      expect(text(tester, 'sub-black'), 'COMPUTER · BLACK · RAPID 10+5');
      await play(tester, c, 'd2d4');
      fakes.current.last.move('d7d5');
      await h.clock.advance(minThinkTime);
      expect(moves(c), ['d2d4', 'd7d5'], reason: 'new: the computer answers');
    });

    testWidgets('Two players starts Rapid 10+5, fully playable', (
      tester,
    ) async {
      final (h, fakes) = await pumpVs(tester, timeControl: const Untimed());
      final c = h.controller;
      await play(tester, c, 'e2e4');
      await openPicker(tester, h.clock);
      await choose(tester, h.clock, 'new-two-players');
      expect(fakes.built.single.disposed, isTrue, reason: 'new: old computer');
      expect(c.game.mode, const TwoPlayer());
      expect(c.game.clock.control, Timed.rapid);
      expect(find.text('❚❚ Two players'), findsOneWidget);
      expect(text(tester, 'name-white'), 'White');
      expect(text(tester, 'name-black'), 'Black');
      expect(text(tester, 'sub-black'), 'PLAYER TWO · BLACK · RAPID 10+5');
      expect(c.options.rotateEachTurn, isFalse, reason: 'new: rotate off');

      // White by tap, Black by drag, and each side's clock runs in turn.
      await tap(tester, 'e2');
      await tap(tester, 'e4');
      await h.clock.advance(const Duration(seconds: 4));
      await dragTo(tester, 'e7', centre(tester, 'e5'));
      await h.clock.advance(const Duration(seconds: 2));
      await tap(tester, 'g1');
      await tap(tester, 'f3');
      expect(moves(c), ['e2e4', 'e7e5', 'g1f3']);
      expect(c.remaining(Colour.black), isNot(const Duration(minutes: 10)));
      expect(c.remaining(Colour.white), isNot(const Duration(minutes: 10)));
      expect(c.clockRunning(Colour.black), isTrue);
      expect(fakes.built, hasLength(1), reason: 'new: no computer here');
    });
  });
}
