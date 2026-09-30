// The result card and bar (#78), over real finished games played on the
// screen, with a fake time source. The complements: no result shows while
// the game goes on, the card waits after a game-ending move and not after
// a resignation, agreement or flag, a takeback during that wait cancels
// it, and the frozen board takes no input. Where See statistics, Main
// menu and back in view-board mode lead is tested in
// test/ui/game_cards_navigation_test.dart (#92).
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:honest_chess/engine/engine.dart' hide play;
import 'package:honest_chess/ui/game/game_controller.dart';
import 'package:honest_chess/ui/game/result_overlay.dart';
import 'package:honest_chess/ui/game/tool_row.dart';
import 'package:honest_chess/ui/theme/palette.dart';

import '../board/board_interaction_test.dart' show tap;
import 'computer_turns_test.dart' show asWhite, pumpVs;
import 'pause_overlay_test.dart' show pausePill, pressCard;
import 'player_panel_test.dart' show Harness, play, pumpGame, text, textColour;
import 'tool_row_test.dart' show press;

final _card = find.byKey(const Key('result-card'));
final _bar = find.byKey(const Key('result-bar'));
final _topBar = find.byKey(const Key('pause-pill'));

Future<void> playAll(WidgetTester tester, Harness h, List<String> ucis) async {
  for (final uci in ucis) {
    await play(tester, h.controller, uci);
  }
}

/// Waits out the delay after a game-ending move and the card's rise.
Future<void> cardIn(WidgetTester tester) async {
  await tester.pump(resultDelay);
  await tester.pump(resultRiseDuration);
}

/// The tag leads the card (#161): at [resultTagSize], bold, above the
/// title, and centred across the card. The size it had before (10 dp,
/// left-aligned) fails every one of these.
void expectTagProminent(WidgetTester tester) {
  final tag = find.byKey(const Key('result-tag'));
  final style = tester.widget<Text>(tag).style!;
  expect(
    style.fontSize,
    resultTagSize,
    reason: 'result-tag: not drawn at resultTagSize',
  );
  expect(
    style.fontSize,
    greaterThanOrEqualTo(20),
    reason: 'result-tag: smaller than 20 dp',
  );
  expect(style.fontWeight, FontWeight.w700, reason: 'result-tag: not bold');
  final card = tester.getRect(_card);
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: tag, matching: find.byType(RichText)),
  );
  // Where the glyphs are drawn, not the width the Text was given.
  final line = paragraph.getBoxesForSelection(
    TextSelection(
      baseOffset: 0,
      extentOffset: text(tester, 'result-tag').length,
    ),
  );
  final origin = paragraph.localToGlobal(Offset.zero);
  final left = origin.dx + line.map((b) => b.left).reduce(math.min);
  final right = origin.dx + line.map((b) => b.right).reduce(math.max);
  expect(
    (left + right) / 2,
    moreOrLessEquals(card.center.dx, epsilon: 1),
    reason: 'result-tag: not centred across the card',
  );
  final top = tester.getRect(tag).top;
  expect(
    top,
    lessThan(tester.getRect(find.byKey(const Key('result-title'))).top),
    reason: 'result-tag: not above the title',
  );
  expect(
    top - card.top,
    lessThanOrEqualTo(24 + 1),
    reason: 'result-tag: not at the top of the card',
  );
}

/// The card's tag, title, body and four stats as the screen shows them;
/// the tag is checked with [expectTagProminent] on every call.
({String tag, String title, String body, List<String> stats}) shown(
  WidgetTester tester,
) => (
  tag: (() {
    expectTagProminent(tester);
    return text(tester, 'result-tag');
  })(),
  title: text(tester, 'result-title'),
  body: text(tester, 'result-body'),
  stats: [
    for (var i = 0; i < 4; i++)
      '${text(tester, 'result-stat-label-$i')} '
          '${text(tester, 'result-stat-value-$i')}',
  ],
);

Future<void> back(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pump();
}

const _foolsMate = ['f2f3', 'e7e5', 'g2g4', 'd8h4'];

void main() {
  group('every ending', () {
    testWidgets("checkmate, two players: fool's mate", (tester) async {
      final h = await pumpGame(tester);
      await playAll(tester, h, _foolsMate);
      await cardIn(tester);
      final s = shown(tester);
      expect(s.tag, 'BLACK WINS');
      expect(s.title, 'Black delivers checkmate');
      expect(s.body, startsWith('The king has no legal square'));
      expect(s.stats, [
        'MOVES 2',
        'CAPTURES 0',
        'CLOCK Untimed',
        'TIME LEFT —',
      ]);
      expect(
        textColour(tester, 'result-tag'),
        Palette.teal,
        reason: 'result-card: a two-player win is teal',
      );
    });

    testWidgets('checkmate vs the computer: YOU WIN, LEVEL, your clock', (
      tester,
    ) async {
      final h = await pumpGame(
        tester,
        mode: asWhite,
        timeControl: Timed(1, 0),
        fen: '6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1',
      );
      await play(tester, h.controller, 'a1a8');
      await cardIn(tester);
      final s = shown(tester);
      expect(s.tag, 'YOU WIN');
      expect(s.title, 'White delivers checkmate');
      expect(s.stats, [
        'MOVES 1',
        'CAPTURES 0',
        'LEVEL Club',
        'TIME LEFT 1:00',
      ]);
      expect(textColour(tester, 'result-tag'), Palette.teal);
    });

    testWidgets('resignation vs the computer: YOU LOSE in red, at once', (
      tester,
    ) async {
      final h = await pumpGame(tester, mode: asWhite);
      await play(tester, h.controller, 'e2e4');
      await press(tester, Tool.resign);
      expect(_card, findsOneWidget, reason: 'result-card: no delay');
      await tester.pump(resultRiseDuration);
      final s = shown(tester);
      expect(s.tag, 'YOU LOSE');
      expect(s.title, 'White resigned');
      expect(s.body, 'Resignation ends the game at once.');
      expect(
        textColour(tester, 'result-tag'),
        Palette.dangerText,
        reason: 'result-card: the kicker is red when you lose',
      );
    });

    testWidgets('flag fall: the winner\'s clock, the loser at 0:00', (
      tester,
    ) async {
      final h = await pumpGame(tester, timeControl: Timed(1, 0));
      await play(tester, h.controller, 'e2e4');
      await h.clock.advance(const Duration(seconds: 60));
      expect(_card, findsOneWidget, reason: 'result-card: no delay on time');
      await tester.pump(resultRiseDuration);
      final s = shown(tester);
      expect(s.tag, 'WHITE WINS');
      expect(s.title, 'Black ran out of time');
      expect(s.body, contains('mating material still on the board'));
      expect(s.stats, ['MOVES 1', 'CAPTURES 0', 'CLOCK 1+0', 'TIME LEFT 1:00']);
    });

    testWidgets('flag with no mating material: DRAWN, White\'s 0:00', (
      tester,
    ) async {
      final h = await pumpGame(
        tester,
        timeControl: Timed(1, 0),
        fen: '4k3/8/8/8/8/8/4P3/4K3 w - - 0 1',
      );
      await playAll(tester, h, ['e2e3', 'e8d8']);
      await h.clock.advance(const Duration(seconds: 60));
      await tester.pump(resultRiseDuration);
      final s = shown(tester);
      expect(s.tag, 'DRAWN');
      expect(s.title, 'Flag fell, but no mating material');
      expect(s.stats.last, 'TIME LEFT 0:00');
    });

    testWidgets('stalemate', (tester) async {
      final h = await pumpGame(tester, fen: 'k7/8/8/1Q6/8/8/8/K7 w - - 0 1');
      await play(tester, h.controller, 'b5b6');
      await cardIn(tester);
      final s = shown(tester);
      expect(s.tag, 'DRAWN');
      expect(s.title, 'Stalemate — no legal move');
      expect(s.body, endsWith('That is a draw, not a win.'));
    });

    testWidgets('insufficient material: the last capture counts', (
      tester,
    ) async {
      final h = await pumpGame(tester, fen: 'k7/8/8/8/8/8/1r6/K7 w - - 0 1');
      await play(tester, h.controller, 'a1b2');
      await cardIn(tester);
      final s = shown(tester);
      expect(s.title, 'Draw — not enough material');
      expect(s.stats.take(2), ['MOVES 1', 'CAPTURES 1']);
    });

    testWidgets('threefold repetition', (tester) async {
      final h = await pumpGame(tester);
      await playAll(tester, h, [
        for (var i = 0; i < 2; i++) ...['g1f3', 'g8f6', 'f3g1', 'f6g8'],
      ]);
      await cardIn(tester);
      final s = shown(tester);
      expect(s.title, 'Draw by repetition');
      expect(s.body, 'The same position came up three times.');
      expect(s.stats.first, 'MOVES 4');
    });

    testWidgets('fifty-move rule, in this app\'s words', (tester) async {
      final h = await pumpGame(tester, fen: 'k7/8/8/8/8/8/8/KR6 w - - 99 60');
      await play(tester, h.controller, 'b1b2');
      await cardIn(tester);
      final s = shown(tester);
      expect(s.title, 'Draw by the fifty-move rule');
      expect(
        s.body,
        'Fifty moves each with no capture or pawn move — the game is drawn '
        'automatically.',
      );
    });

    testWidgets('agreed draw from the pause card, at once', (tester) async {
      final h = await pumpGame(tester);
      await playAll(tester, h, ['e2e4', 'e7e5']);
      await pausePill(tester, h.clock);
      await pressCard(tester, 'pause-draw');
      expect(_card, findsOneWidget, reason: 'result-card: no delay');
      await tester.pump(resultRiseDuration);
      expect(shown(tester).title, 'Draw agreed');
      expect(shown(tester).body, 'Both players agreed to split the point.');
    });

    testWidgets('resignation with no mating material: drawn', (tester) async {
      await pumpGame(tester, fen: '4k3/8/8/8/8/8/4P3/4K3 w - - 0 1');
      await press(tester, Tool.resign);
      await tester.pump(resultRiseDuration);
      final s = shown(tester);
      expect(s.tag, 'DRAWN');
      expect(s.title, 'White resigned — drawn');
    });
  });

  group('never while the game goes on', () {
    testWidgets('no card or bar through moves and a check', (tester) async {
      final h = await pumpGame(tester);
      for (final uci in ['e2e4', 'd7d5']) {
        await play(tester, h.controller, uci);
        await tester.pump(resultDelay + resultRiseDuration);
        expect(h.controller.state.resultView, isNull);
        expect(_card, findsNothing, reason: 'result-card: shown mid-game');
        expect(_bar, findsNothing, reason: 'result-card: bar mid-game');
      }
      await play(tester, h.controller, 'f1b5');
      expect(h.controller.game.status, const Ongoing(inCheck: true));
      await tester.pump(resultDelay + resultRiseDuration);
      expect(_card, findsNothing, reason: 'result-card: a check is no ending');
    });

    testWidgets('the card waits 600 ms after a game-ending move', (
      tester,
    ) async {
      final h = await pumpGame(tester);
      await playAll(tester, h, _foolsMate);
      expect(h.controller.state.resultView, ResultView.card);
      await tester.pump(resultDelay - const Duration(milliseconds: 1));
      expect(_card, findsNothing, reason: 'result-card: shown too soon');
      await tester.pump(const Duration(milliseconds: 1));
      expect(_card, findsOneWidget);
    });

    testWidgets('a takeback during the wait cancels the card', (tester) async {
      final h = await pumpGame(tester);
      await playAll(tester, h, _foolsMate);
      await tester.pump(const Duration(milliseconds: 300));
      await press(tester, Tool.takeback);
      expect(h.controller.game.isOver, isFalse);
      await tester.pump(resultDelay + resultRiseDuration);
      expect(_card, findsNothing, reason: 'result-card: a cancelled card');
    });

    testWidgets('with system animations off, the same wait and no rise', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final h = await pumpGame(tester);
      await playAll(tester, h, _foolsMate);
      await tester.pump(resultDelay - const Duration(milliseconds: 1));
      expect(
        _card,
        findsNothing,
        reason: 'result-card: motion off keeps the pacing delay',
      );
      await tester.pump(const Duration(milliseconds: 1));
      expect(_card, findsOneWidget, reason: 'result-card: in after the wait');
      final fade = tester.widget<FadeTransition>(
        find.byKey(const Key('result-overlay')),
      );
      expect(fade.opacity.value, 1, reason: 'result-card: animated anyway');
    });
  });

  group('view board', () {
    Future<Harness> mated(WidgetTester tester) async {
      final h = await pumpGame(tester);
      await playAll(tester, h, _foolsMate);
      await cardIn(tester);
      return h;
    }

    testWidgets('View board leaves the bar over the frozen final board', (
      tester,
    ) async {
      final h = await mated(tester);
      final c = h.controller;
      await pressCard(tester, 'result-view-board');
      expect(c.state.resultView, ResultView.board);
      // The fade, a frame's slack, and the frame that removes the card.
      await tester.pump(resultFadeDuration + const Duration(milliseconds: 16));
      await tester.pump();
      expect(_card, findsNothing);
      expect(_bar, findsOneWidget);
      expect(_topBar, findsNothing, reason: 'result-bar: takes its place');
      expect(text(tester, 'result-bar-tag'), 'BLACK WINS');
      expect(text(tester, 'result-bar-title'), 'Black delivers checkmate');
      expect(c.state.lastMove?.toUci(), 'd8h4');
      expect(
        c.state.tintAt(Square.parse('e1')),
        SquareTint.check,
        reason: 'result-bar: the check flag stays',
      );
      await tap(tester, 'e2');
      expect(
        c.state.selection,
        isNull,
        reason: 'result-bar: the final board takes no input',
      );

      // The bar brings the card back at once, rising, with no wait.
      await tester.tap(find.byKey(const Key('result-bar-show')));
      await tester.pump();
      expect(c.state.resultView, ResultView.card);
      expect(_card, findsOneWidget, reason: 'result-bar: tap shows the card');
      expect(_bar, findsNothing);

      // A tap on the scrim, like View board.
      await tester.pump(resultRiseDuration);
      await tester.tapAt(const Offset(195, 20));
      await tester.pump();
      expect(c.state.resultView, ResultView.board);
    });

    testWidgets('Android back does what View board does', (tester) async {
      final h = await mated(tester);
      await back(tester);
      expect(h.controller.state.resultView, ResultView.board);
    });

    testWidgets('Rematch from the bar starts the same game again', (
      tester,
    ) async {
      final h = await mated(tester);
      await pressCard(tester, 'result-view-board');
      await tester.pump(resultFadeDuration);
      await tester.tap(find.byKey(const Key('result-bar-rematch')));
      await tester.pump();
      final c = h.controller;
      expect(c.game.isOver, isFalse);
      expect(c.game.moves, isEmpty);
      expect(c.state.resultView, isNull);
      expect(_bar, findsNothing);
      expect(_card, findsNothing);
      expect(_topBar, findsOneWidget);
    });

    testWidgets('Takeback hides the bar and re-opens the game', (tester) async {
      final h = await mated(tester);
      await pressCard(tester, 'result-view-board');
      await tester.pump(resultFadeDuration);
      await press(tester, Tool.takeback);
      expect(h.controller.game.isOver, isFalse);
      expect(_bar, findsNothing, reason: 'result-bar: survived a takeback');
      expect(_topBar, findsOneWidget);
      await play(tester, h.controller, 'd8h4');
      await cardIn(tester);
      expect(_card, findsOneWidget, reason: 'result-card: a new ending');
    });
  });

  group('rematch', () {
    testWidgets('the same mode, level, colour and time control', (
      tester,
    ) async {
      final (h, _) = await pumpVs(tester);
      await play(tester, h.controller, 'e2e4');
      await press(tester, Tool.resign);
      await tester.pump(resultRiseDuration);
      await pressCard(tester, 'result-rematch');
      final game = h.controller.game;
      expect(game.isOver, isFalse);
      expect(game.moves, isEmpty);
      final mode = game.mode as VsComputer;
      expect(mode.playerColour, Colour.white);
      expect(mode.step, Strength.club);
      expect(game.clock.control, Timed.rapid);
      expect(_card, findsNothing);
      await tester.pump(resultRiseDuration);
    });
  });

  group('the card', () {
    testWidgets('Rematch, View board, See statistics and Main menu', (
      tester,
    ) async {
      final h = await pumpGame(tester);
      await playAll(tester, h, _foolsMate);
      await cardIn(tester);
      final labels = ['Rematch', 'View board', 'See statistics', 'Main menu'];
      final tops = [
        for (final label in labels) tester.getTopLeft(find.text(label)).dy,
      ];
      for (var i = 1; i < tops.length; i++) {
        expect(
          tops[i],
          greaterThan(tops[i - 1]),
          reason: 'card: ${labels[i]} is not below ${labels[i - 1]}',
        );
      }
    });

    testWidgets('a header, not a live region (the hub speaks the result, '
        '#102); stats read "Moves, 2"', (tester) async {
      final semantics = tester.ensureSemantics();
      final h = await pumpGame(tester);
      await playAll(tester, h, _foolsMate);
      await cardIn(tester);
      final heading = find.bySemanticsLabel(
        'Black wins, Black delivers checkmate',
      );
      expect(heading, findsOneWidget);
      expect(
        tester.getSemantics(heading),
        isSemantics(isLiveRegion: false, isHeader: true),
        reason: 'result-card: the card would read the result a second time',
      );
      expect(find.bySemanticsLabel('Moves, 2'), findsOneWidget);
      expect(find.bySemanticsLabel('Time left, no clock'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('26 dp inset, no wider than 440 dp', (tester) async {
      final h = await pumpGame(tester);
      tester.view.physicalSize = const Size(900, 844);
      await tester.pump();
      await playAll(tester, h, _foolsMate);
      await cardIn(tester);
      expect(tester.getSize(_card).width, resultMaxWidth);
      tester.view.physicalSize = const Size(390, 844);
      await tester.pump();
      expect(tester.getSize(_card).width, 390 - 2 * resultInset);
    });

    testWidgets('scrolls on a short screen', (tester) async {
      final h = await pumpGame(tester);
      await playAll(tester, h, _foolsMate);
      tester.view.physicalSize = const Size(390, 420);
      await cardIn(tester);
      expect(tester.takeException(), isNull);
      await tester.drag(_card, const Offset(0, -300));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const Key('result-view-board')).hitTestable(),
        findsOne,
      );
    });

    testWidgets('a game ending while promoting closes the sheet', (
      tester,
    ) async {
      final h = await pumpGame(
        tester,
        timeControl: Timed(1, 0),
        fen: 'k7/4P3/8/8/8/8/8/K7 w - - 0 1',
      );
      await playAll(tester, h, ['a1b1', 'a8b8']);
      await tap(tester, 'e7');
      await tap(tester, 'e8');
      expect(h.controller.state.pendingPromotion, isNotNull);
      await h.clock.advance(const Duration(seconds: 60));
      expect(h.controller.state.pendingPromotion, isNull);
      await tester.pump(resultRiseDuration);
      expect(find.byKey(const Key('promo-card')), findsNothing);
      expect(shown(tester).title, 'Flag fell, but no mating material');
    });
  });
}
