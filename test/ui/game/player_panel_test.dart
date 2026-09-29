// The play screen's frame (#74): the top bar, the two player panels and
// their live clocks, driven by a fake time source. The complements matter
// as much as the counting: the idle clock never moves, nothing ticks
// untimed or paused, a paused flag never falls, and the board is not
// rebuilt as the seconds pass.
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:honest_chess/engine/engine.dart';
import 'package:honest_chess/ui/board/board_options.dart';
import 'package:honest_chess/ui/board/board_view.dart';
import 'package:honest_chess/ui/board/promotion_sheet.dart';
import 'package:honest_chess/ui/game/computer_turns.dart';
import 'package:honest_chess/ui/game/game_controller.dart';
import 'package:honest_chess/ui/game/game_screen.dart';
import 'package:honest_chess/ui/game/result_overlay.dart';
import 'package:honest_chess/ui/theme/palette.dart';

import 'fake_computer.dart';

/// The game's time source and the test's frame clock, moved together.
class FakeClock {
  FakeClock(this.tester);

  final WidgetTester tester;
  int ms = 0;

  int now() => ms;

  Future<void> advance(Duration d) async {
    ms += d.inMilliseconds;
    await tester.pump(d);
  }
}

typedef Harness = ({GameController controller, FakeClock clock});

Future<Harness> pumpGame(
  WidgetTester tester, {
  GameMode mode = const TwoPlayer(),
  TimeControl timeControl = const Untimed(),
  String? fen,
  bool thinking = false,
  BoardOptions options = const BoardOptions(),
  FakeComputers? computer,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final clock = FakeClock(tester);
  final controller = GameController(
    mode: mode,
    timeControl: timeControl,
    fen: fen,
    options: options,
    now: clock.now,
    // A computer that never answers keeps thinking once it is its turn.
    computer: (computer ?? (thinking ? FakeComputers() : null))?.call,
  );
  await tester.pumpWidget(
    MaterialApp(
      home: GameScreen(options: options, controller: controller),
    ),
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
  return (controller: controller, clock: clock);
}

String text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data!;

Color? textColour(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).style!.color;

String clockOf(WidgetTester tester, Colour side) =>
    text(tester, 'clock-${side.name}');

bool isLit(WidgetTester tester, Colour side) {
  final box = tester.widget<Container>(find.byKey(Key('panel-${side.name}')));
  return (box.decoration! as BoxDecoration).color == Palette.panelLit;
}

String spoken(WidgetTester tester, Colour side) => tester
    .widget<Semantics>(find.byKey(Key('clock-semantics-${side.name}')))
    .properties
    .label!;

double top(WidgetTester tester, String key) =>
    tester.getTopLeft(find.byKey(Key(key))).dy;

int get tickers => SchedulerBinding.instance.transientCallbackCount;

Future<void> play(WidgetTester tester, GameController c, String uci) async {
  final from = Square.parse(uci.substring(0, 2));
  final to = Square.parse(uci.substring(2, 4));
  expect(c.move(from, to), isTrue, reason: 'test: $uci is playable');
  await tester.pump();
}

void main() {
  group('labels', () {
    testWidgets('vs the computer as White: you below, Club above', (
      tester,
    ) async {
      await pumpGame(
        tester,
        mode: const VsComputer(
          playerColour: Colour.white,
          step: Strength.club,
          seed: 1,
        ),
        timeControl: Timed.rapid,
      );
      expect(find.text('❚❚ vs Club'), findsOneWidget);
      expect(text(tester, 'status-text'), 'WHITE TO MOVE');
      expect(text(tester, 'name-white'), 'You');
      expect(text(tester, 'sub-white'), 'YOU · WHITE · RAPID 10+5');
      expect(text(tester, 'name-black'), 'Club');
      expect(text(tester, 'sub-black'), 'COMPUTER · BLACK · RAPID 10+5');
      expect(clockOf(tester, Colour.white), '10:00');
      expect(clockOf(tester, Colour.black), '10:00');
      expect(
        top(tester, 'panel-black'),
        lessThan(top(tester, 'board')),
        reason: 'panels: the opponent sits above the board',
      );
      expect(
        top(tester, 'panel-white'),
        greaterThan(top(tester, 'board')),
        reason: 'panels: your panel sits below the board',
      );
      final chip = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const Key('chip-white')),
          matching: find.byType(Text),
        ),
      );
      expect(chip.data, '♔\u{FE0E}');
      expect(chip.style!.fontFamily, Fonts.pieces);
    });

    testWidgets('vs the computer as Black: the panels follow orientation', (
      tester,
    ) async {
      await pumpGame(
        tester,
        mode: const VsComputer(
          playerColour: Colour.black,
          step: Strength.casual,
          seed: 1,
        ),
        timeControl: Timed(15, 10),
      );
      expect(find.text('❚❚ vs Casual'), findsOneWidget);
      expect(text(tester, 'name-black'), 'You');
      expect(text(tester, 'sub-black'), 'YOU · BLACK · CUSTOM 15+10');
      expect(text(tester, 'name-white'), 'Casual');
      expect(text(tester, 'sub-white'), 'COMPUTER · WHITE · CUSTOM 15+10');
      expect(
        top(tester, 'panel-white'),
        lessThan(top(tester, 'board')),
        reason: 'panels: with Black at the bottom, White is above',
      );
      expect(top(tester, 'panel-black'), greaterThan(top(tester, 'board')));
      expect(clockOf(tester, Colour.black), '15:00');
    });

    testWidgets('two players, untimed: ∞ and nothing ticks', (tester) async {
      final h = await pumpGame(tester);
      expect(find.text('❚❚ Two players'), findsOneWidget);
      expect(text(tester, 'name-white'), 'White');
      expect(text(tester, 'sub-white'), 'PLAYER ONE · WHITE · UNTIMED');
      expect(text(tester, 'name-black'), 'Black');
      expect(text(tester, 'sub-black'), 'PLAYER TWO · BLACK · UNTIMED');
      await play(tester, h.controller, 'e2e4');
      await h.clock.advance(const Duration(seconds: 5));
      expect(clockOf(tester, Colour.white), '∞');
      expect(clockOf(tester, Colour.black), '∞');
      expect(tickers, 0, reason: 'clock-tick: an untimed game runs no ticker');
      expect(spoken(tester, Colour.black), 'Black, no clock');
    });

    testWidgets('long names ellipsize and the clock keeps its size', (
      tester,
    ) async {
      await pumpGame(tester, timeControl: Timed.blitz);
      final name = tester.widget<Text>(find.byKey(const Key('name-white')));
      expect(name.overflow, TextOverflow.ellipsis);
      expect(name.maxLines, 1);
    });
  });

  group('clocks', () {
    testWidgets('neither clock runs before White\'s first move', (
      tester,
    ) async {
      final h = await pumpGame(tester, timeControl: Timed.blitz);
      await h.clock.advance(const Duration(seconds: 3));
      expect(clockOf(tester, Colour.white), '5:00');
      expect(h.controller.remaining(Colour.white), const Duration(minutes: 5));
      expect(tickers, 0, reason: 'clock-tick: no ticker before the first move');
      expect(isLit(tester, Colour.white), isTrue);
      expect(isLit(tester, Colour.black), isFalse);
    });

    testWidgets('the mover\'s clock falls by the elapsed time, the idle one '
        'does not', (tester) async {
      final h = await pumpGame(tester, timeControl: Timed.blitz);
      await play(tester, h.controller, 'e2e4');
      await h.clock.advance(const Duration(milliseconds: 2300));
      expect(
        h.controller.remaining(Colour.black),
        const Duration(milliseconds: 297700),
        reason: 'clock-run: Black\'s clock fell by exactly 2.3 s',
      );
      expect(clockOf(tester, Colour.black), '4:58');
      expect(
        h.controller.remaining(Colour.white),
        const Duration(minutes: 5),
        reason: 'clock-run: the idle clock does not move',
      );
      expect(clockOf(tester, Colour.white), '5:00');
      await h.clock.advance(const Duration(seconds: 7));
      expect(clockOf(tester, Colour.white), '5:00');
      expect(clockOf(tester, Colour.black), '4:51');
      expect(tickers, 1, reason: 'clock-tick: one ticker, the running clock');
    });

    testWidgets('Rapid 10+5: the mover gains 5 s after each move', (
      tester,
    ) async {
      final h = await pumpGame(tester, timeControl: Timed.rapid);
      await play(tester, h.controller, 'e2e4');
      await h.clock.advance(const Duration(seconds: 3));
      await play(tester, h.controller, 'e7e5');
      expect(
        h.controller.remaining(Colour.black),
        const Duration(seconds: 602),
        reason: 'clock-increment: 600 − 3 + 5',
      );
      expect(clockOf(tester, Colour.black), '10:02');
      await h.clock.advance(const Duration(seconds: 1));
      expect(
        h.controller.remaining(Colour.black),
        const Duration(seconds: 602),
      );
      expect(clockOf(tester, Colour.white), '9:59');
    });

    testWidgets('lit and dim swap after a move; none lit once over', (
      tester,
    ) async {
      final h = await pumpGame(tester, timeControl: Timed.blitz);
      expect(isLit(tester, Colour.white), isTrue);
      expect(textColour(tester, 'clock-white'), Palette.pieceWhite);
      expect(textColour(tester, 'sub-white'), Palette.teal);
      expect(textColour(tester, 'clock-black'), Palette.textDim);
      expect(textColour(tester, 'sub-black'), Palette.textDim);
      await play(tester, h.controller, 'e2e4');
      expect(isLit(tester, Colour.white), isFalse);
      expect(isLit(tester, Colour.black), isTrue);
      expect(textColour(tester, 'clock-white'), Palette.textDim);
      expect(textColour(tester, 'clock-black'), Palette.pieceWhite);
      await h.clock.advance(const Duration(minutes: 5));
      expect(h.controller.state.over, isTrue);
      expect(isLit(tester, Colour.white), isFalse);
      expect(
        isLit(tester, Colour.black),
        isFalse,
        reason: 'panels: no panel is lit once the game is over',
      );
    });

    testWidgets('red at 29.9 s and not at 30.0 s', (tester) async {
      final h = await pumpGame(tester, timeControl: Timed(1, 0));
      await play(tester, h.controller, 'e2e4');
      await h.clock.advance(const Duration(seconds: 30));
      expect(clockOf(tester, Colour.black), '0:30');
      expect(
        textColour(tester, 'clock-black'),
        Palette.pieceWhite,
        reason: 'clock-red: 30.0 s is not red',
      );
      await h.clock.advance(const Duration(milliseconds: 100));
      expect(clockOf(tester, Colour.black), '0:30');
      expect(
        textColour(tester, 'clock-black'),
        Palette.dangerText,
        reason: 'clock-red: 29.9 s is red',
      );
      expect(textColour(tester, 'clock-white'), isNot(Palette.dangerText));
      await h.clock.advance(const Duration(milliseconds: 20500));
      expect(clockOf(tester, Colour.black), '0:09.4');
    });

    testWidgets('the ticking clock never rebuilds the board', (tester) async {
      final h = await pumpGame(tester, timeControl: Timed.blitz);
      await play(tester, h.controller, 'e2e4');
      final board = tester.widget<BoardView>(find.byType(BoardView));
      for (var i = 0; i < 5; i++) {
        await h.clock.advance(const Duration(seconds: 1));
      }
      expect(clockOf(tester, Colour.black), '4:55');
      expect(
        identical(tester.widget<BoardView>(find.byType(BoardView)), board),
        isTrue,
        reason: 'clock-tick: five seconds of ticking left the board unbuilt',
      );
      expect(
        find.ancestor(
          of: find.byType(BoardView),
          matching: find.byType(RepaintBoundary),
        ),
        findsWidgets,
      );
    });

    testWidgets('the spoken label follows at most every 10 s', (tester) async {
      final h = await pumpGame(tester, timeControl: Timed.blitz);
      expect(spoken(tester, Colour.white), 'White, 5 minutes');
      await play(tester, h.controller, 'e2e4');
      expect(spoken(tester, Colour.black), 'Black, 5 minutes');
      await h.clock.advance(const Duration(seconds: 1));
      expect(clockOf(tester, Colour.black), '4:59');
      expect(
        spoken(tester, Colour.black),
        'Black, 5 minutes',
        reason: 'clock-speech: one second later the label has not moved',
      );
      for (var i = 0; i < 9; i++) {
        await h.clock.advance(const Duration(seconds: 1));
      }
      expect(spoken(tester, Colour.black), 'Black, 4 minutes 50 seconds');
      await h.clock.advance(const Duration(seconds: 1));
      expect(spoken(tester, Colour.black), 'Black, 4 minutes 50 seconds');
      await play(tester, h.controller, 'e7e5');
      expect(
        spoken(tester, Colour.black),
        'Black, 4 minutes 49 seconds',
        reason: 'clock-speech: a clock that stops speaks at once',
      );
    });
  });

  group('flag', () {
    testWidgets('a clock at zero ends the game: FLAG FALL', (tester) async {
      final h = await pumpGame(tester, timeControl: Timed(1, 0));
      await play(tester, h.controller, 'e2e4');
      await h.clock.advance(const Duration(milliseconds: 59900));
      expect(h.controller.state.over, isFalse);
      expect(clockOf(tester, Colour.black), '0:00.1');
      await h.clock.advance(const Duration(milliseconds: 100));
      expect(h.controller.state.over, isTrue, reason: 'flag: 0 ends the game');
      expect(
        h.controller.game.status,
        const Win(Colour.white, GameEndReason.flag),
      );
      expect(text(tester, 'status-text'), 'FLAG FALL');
      expect(textColour(tester, 'status-text'), Palette.teal);
      // Resign turning disabled at the flag gives up its focus, which asks
      // for one more frame, and the result card (#78) rises in, ending a
      // frame after its length; neither is the clock's tick.
      await tester.pump();
      await tester.pump(resultRiseDuration + const Duration(milliseconds: 16));
      await tester.pump();
      expect(tickers, 0, reason: 'clock-tick: an ended game ticks no more');
    });

    testWidgets('a flag against a side that cannot be mated: DRAWN', (
      tester,
    ) async {
      final h = await pumpGame(
        tester,
        timeControl: Timed(1, 0),
        fen: 'k7/p7/8/8/8/8/8/K7 w - - 0 1',
      );
      await play(tester, h.controller, 'a1b1');
      await h.clock.advance(const Duration(minutes: 1));
      expect(
        h.controller.game.status,
        const Draw(GameEndReason.flagNoMatingMaterial),
      );
      expect(text(tester, 'status-text'), 'DRAWN');
    });

    testWidgets('no flag falls while paused', (tester) async {
      final h = await pumpGame(tester, timeControl: Timed(1, 0));
      await play(tester, h.controller, 'e2e4');
      await h.clock.advance(const Duration(seconds: 10));
      expect(h.controller.pause(), isTrue);
      await tester.pump();
      await h.clock.advance(const Duration(minutes: 2));
      expect(
        h.controller.state.over,
        isFalse,
        reason: 'flag: a paused clock never falls',
      );
      expect(h.controller.remaining(Colour.black), const Duration(seconds: 50));
      expect(clockOf(tester, Colour.black), '0:50');
      expect(tickers, 0, reason: 'clock-tick: a paused game ticks no more');
      expect(text(tester, 'status-text'), 'BLACK TO MOVE');
      expect(h.controller.resume(), isTrue);
      await tester.pump();
      await h.clock.advance(const Duration(seconds: 50));
      expect(h.controller.state.over, isTrue);
    });

    testWidgets('a flag while the promotion card is open closes it', (
      tester,
    ) async {
      final h = await pumpGame(
        tester,
        timeControl: Timed(1, 0),
        fen: '3r3k/4P3/8/8/8/8/8/K7 b - - 0 1',
      );
      await play(tester, h.controller, 'h8h7');
      await tester.tap(find.byKey(const Key('cell-e7')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('cell-e8')));
      await h.clock.advance(promotionEnterDuration);
      expect(find.byKey(const Key('promo-card')), findsOneWidget);
      await h.clock.advance(const Duration(minutes: 1));
      await tester.pump(promotionExitDuration);
      expect(h.controller.state.pendingPromotion, isNull);
      expect(
        find.byKey(const Key('promo-card')),
        findsNothing,
        reason: 'flag: the flag closes the promotion card',
      );
      expect(
        h.controller.game.status,
        const Win(Colour.black, GameEndReason.flag),
      );
      expect(text(tester, 'status-text'), 'FLAG FALL');
    });
  });

  group('status', () {
    testWidgets('thinking shows on the computer\'s panel and the chip', (
      tester,
    ) async {
      const mode = VsComputer(
        playerColour: Colour.black,
        step: Strength.club,
        seed: 1,
      );
      await pumpGame(tester, mode: mode, thinking: true);
      expect(text(tester, 'name-white'), 'Club is thinking');
      expect(text(tester, 'name-black'), 'You');
      expect(text(tester, 'status-text'), 'THINKING…');
      // Past the think-time floor, the unanswered computer is still thinking
      // and no timer is left behind.
      await tester.pump(minThinkTime);
      expect(text(tester, 'status-text'), 'THINKING…');
    });

    testWidgets('not thinking: the plain name and whose move', (tester) async {
      const mode = VsComputer(
        playerColour: Colour.black,
        step: Strength.club,
        seed: 1,
      );
      await pumpGame(tester, mode: mode);
      expect(
        text(tester, 'name-white'),
        'Club',
        reason: 'thinking: no "is thinking" while the computer is idle',
      );
      expect(text(tester, 'status-text'), 'WHITE TO MOVE');
    });

    testWidgets('in check reads red; the move after reads plain', (
      tester,
    ) async {
      final h = await pumpGame(tester, fen: '4k3/8/8/8/8/8/3r4/R3K3 b - - 0 1');
      await play(tester, h.controller, 'd2e2');
      expect(text(tester, 'status-text'), 'WHITE IN CHECK');
      expect(textColour(tester, 'status-text'), Palette.dangerText);
      await play(tester, h.controller, 'e1e2');
      expect(text(tester, 'status-text'), 'BLACK TO MOVE');
      expect(textColour(tester, 'status-text'), Palette.textBody);
    });

    testWidgets('checkmate reads CHECKMATE', (tester) async {
      final h = await pumpGame(tester);
      for (final m in ['f2f3', 'e7e5', 'g2g4', 'd8h4']) {
        await play(tester, h.controller, m);
      }
      expect(text(tester, 'status-text'), 'CHECKMATE');
    });
  });
}
