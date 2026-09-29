// The board's ways out (#92): the pause card's Rules, Settings and Main
// menu, the result card's See statistics and Main menu, New opening the
// setup screen for the game's kind, Restart's loss message and the board's
// own handling of Android's back. Each board is pushed over a stand-in
// first route, as the app pushes it over the menu, with a fake computer and
// a statistics listener over the harness's memory store. The complements:
// a screen opened from a card leaves the game paused with its clocks where
// they were; Main menu records nothing; New opens no bottom sheet; back on
// a live board never pops it; Restart before your first move says nothing.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:honest_chess/data/app_store.dart';
import 'package:honest_chess/data/play_mode.dart';
import 'package:honest_chess/data/stats_listener.dart';
import 'package:honest_chess/engine/engine.dart';
import 'package:honest_chess/ui/game/computer_turns.dart';
import 'package:honest_chess/ui/game/defaults.dart';
import 'package:honest_chess/ui/game/game_controller.dart';
import 'package:honest_chess/ui/game/game_screen.dart';
import 'package:honest_chess/ui/game/result_overlay.dart';
import 'package:honest_chess/ui/navigation.dart';
import 'package:honest_chess/ui/screens/computer_setup_screen.dart';
import 'package:honest_chess/ui/screens/how_to_play_screen.dart';
import 'package:honest_chess/ui/screens/settings_screen.dart';
import 'package:honest_chess/ui/screens/stats_screen.dart';
import 'package:honest_chess/ui/screens/two_player_setup_screen.dart';
import 'package:honest_chess/ui/widgets/segmented_tabs.dart';

import '../support/app_harness.dart';
import 'game/fake_computer.dart';

typedef _Rig = ({AppHarness h, FakeComputers fakes});

/// A board of [setup] over the stand-in menu, on a 390×844 phone, whose
/// finished and abandoned games the statistics record.
Future<_Rig> _board(
  WidgetTester tester, {
  GameSetup setup = vsComputerDefault,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final fakes = FakeComputers();
  final h = await pumpBoard(tester, setup: setup, computerFactory: fakes.call);
  await h.stats.load();
  final listener = StatsListener(
    controller: h.controller,
    recorder: h.stats,
    saves: h.saves,
  );
  addTearDown(listener.dispose);
  return (h: h, fakes: fakes);
}

Finder _key(String key) => find.byKey(Key(key));

/// Lets a route's transition, a card's fade or rise and any saves finish;
/// a running clock never lets `pumpAndSettle` end.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump();
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  await tester.tap(_key(key));
  await _settle(tester);
}

Future<void> _back(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await _settle(tester);
}

void _move(GameController c, String uci) {
  expect(
    c.move(Square.parse(uci.substring(0, 2)), Square.parse(uci.substring(2))),
    isTrue,
    reason: 'test: $uci is playable',
  );
}

/// Plays White's e2-e4 and the fake computer's e7-e5.
Future<void> _bothMoved(WidgetTester tester, _Rig r) async {
  _move(r.h.controller, 'e2e4');
  await tester.pump();
  r.fakes.current.last.move('e7e5');
  await tester.pump(minThinkTime);
  await tester.pump();
}

/// Fool's mate between two players: the card waits out [resultDelay].
Future<void> _foolsMate(WidgetTester tester, GameController c) async {
  for (final uci in ['f2f3', 'e7e5', 'g2g4', 'd8h4']) {
    _move(c, uci);
    await tester.pump();
  }
  expect(c.game.isOver, isTrue, reason: "test: fool's mate");
}

bool _onMenu() =>
    _key('stand-in').evaluate().isNotEmpty &&
    find.byType(GameScreen).evaluate().isEmpty;

int _played(AppHarness h) =>
    h.stats.document.computer.steps[Strength.club]!.played;

(Duration?, Duration?) _clocks(GameController c) =>
    (c.remaining(Colour.white), c.remaining(Colour.black));

T _tab<T extends Enum>(WidgetTester tester) =>
    tester.widget<SegmentedTabs<T>>(find.byType(SegmentedTabs<T>)).selected;

void main() {
  group('the pause card', () {
    testWidgets('Rules opens The rules; back returns to the same card', (
      tester,
    ) async {
      final r = await _board(tester);
      final c = r.h.controller;
      await _bothMoved(tester, r);
      await _tapKey(tester, 'pause-pill');
      final clocks = _clocks(c);
      await _tapKey(tester, 'pause-rules');
      expect(find.byType(HowToPlayScreen), findsOneWidget);
      expect(_tab<HowToTab>(tester), HowToTab.rules);
      expect(c.state.paused, isTrue, reason: 'rules: the game resumed');
      await _back(tester);
      expect(find.byType(HowToPlayScreen), findsNothing);
      expect(_key('pause-card'), findsOneWidget, reason: 'rules: no card');
      expect(c.state.paused, isTrue, reason: 'rules: back resumed the game');
      expect(_clocks(c), clocks, reason: 'rules: the clocks moved');
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'pause-rules',
        reason: 'rules: focus did not come back to Rules',
      );
    });

    testWidgets('Settings opens Settings; ‹ returns to the same card', (
      tester,
    ) async {
      final r = await _board(tester);
      final c = r.h.controller;
      await _bothMoved(tester, r);
      await _tapKey(tester, 'pause-pill');
      final clocks = _clocks(c);
      await _tapKey(tester, 'pause-settings');
      expect(find.byType(SettingsScreen), findsOneWidget);
      await _tapKey(tester, 'settings-back');
      expect(find.byType(SettingsScreen), findsNothing);
      expect(_key('pause-card'), findsOneWidget);
      expect(c.state.paused, isTrue, reason: 'settings: ‹ resumed the game');
      expect(_clocks(c), clocks, reason: 'settings: the clocks moved');
    });

    testWidgets('during a decline message the buttons are live and clear it', (
      tester,
    ) async {
      final r = await _board(tester);
      final c = r.h.controller;
      await _bothMoved(tester, r);
      await _tapKey(tester, 'pause-pill');
      await tester.tap(_key('pause-draw'));
      await tester.pump();
      r.fakes.current.draws.single.decline();
      await tester.pump();
      expect(_key('pause-declined'), findsOneWidget, reason: 'test: declined');
      await _tapKey(tester, 'pause-rules');
      await tester.pump(drawDeclineShown * 2);
      await _back(tester);
      expect(c.state.paused, isTrue, reason: 'decline: its timer resumed');
      expect(_key('pause-card'), findsOneWidget);
      expect(_key('pause-declined'), findsNothing, reason: 'decline: kept');
      expect(c.drawOffer, DrawOffer.afterNextMove);
    });

    testWidgets('while the computer answers a draw, they are shut', (
      tester,
    ) async {
      final r = await _board(tester);
      await _bothMoved(tester, r);
      await _tapKey(tester, 'pause-pill');
      await tester.tap(_key('pause-draw'));
      await tester.pump();
      for (final key in ['pause-rules', 'pause-settings', 'pause-main-menu']) {
        expect(
          tester.widget<InkWell>(_key(key)).onTap,
          isNull,
          reason: 'asking: $key is live',
        );
      }
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(r.h.controller.state.drawAsking, isTrue, reason: 'asking: back');
      r.fakes.current.draws.single.decline();
      await tester.pump(drawDeclineShown);
    });

    testWidgets('Main menu keeps the game saved, paused and resumable, and '
        'records nothing', (tester) async {
      final r = await _board(tester);
      final c = r.h.controller;
      _move(c, 'e2e4');
      await tester.pump();
      await _tapKey(tester, 'pause-pill');
      await _tapKey(tester, 'pause-main-menu');
      expect(_onMenu(), isTrue, reason: 'main menu: still on the board');
      final first = r.fakes.current;
      expect(first.disposed, isTrue, reason: 'main menu: computer kept');
      expect(c.state.paused, isTrue, reason: 'main menu: the game resumed');
      expect(r.h.store.rawText(StoreDoc.gameComputer), isNotNull);
      expect(r.h.saves.offered?.mode, PlayMode.computer);
      expect(
        [for (final m in r.h.saves.load(PlayMode.computer)!.moves) m.toUci()],
        ['e2e4'],
      );
      expect(_played(r.h), 0, reason: 'main menu: recorded a game');
      expect(r.h.store.rawText(StoreDoc.stats), isNull);

      expect(
        await continueGame(tester.element(_key('stand-in'))),
        isTrue,
        reason: 'main menu: Continue refused the game',
      );
      await _settle(tester);
      expect(find.byType(GameScreen), findsOneWidget);
      expect(_key('pause-card'), findsOneWidget);
      expect(r.fakes.built, hasLength(2), reason: 'continue: a new computer');
      expect(
        (r.fakes.current.strength, r.fakes.current.seed),
        (first.strength, first.seed),
      );
    });

    testWidgets('Main menu holds the navigating flag: back does not resume', (
      tester,
    ) async {
      final r = await _board(tester);
      await _tapKey(tester, 'pause-pill');
      await tester.tap(_key('pause-main-menu'));
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.binding.handlePopRoute();
      await _settle(tester);
      expect(_onMenu(), isTrue);
      expect(r.h.controller.state.paused, isTrue, reason: 'leaving: resumed');
    });

    testWidgets('its hit areas are 48 dp and do not overlap', (tester) async {
      await _board(tester);
      await _tapKey(tester, 'pause-pill');
      expect(tester.getSize(_key('pause-rules-box')).height, 41);
      expect(tester.getSize(_key('pause-settings-box')).height, 41);
      expect(tester.getSize(_key('pause-main-menu-box')).height, 39);
      for (final key in ['pause-rules', 'pause-settings', 'pause-main-menu']) {
        expect(tester.getSize(_key(key)).height, greaterThanOrEqualTo(48));
      }
      final resign = tester.getRect(_key('pause-resign'));
      final rules = tester.getRect(_key('pause-rules'));
      final menu = tester.getRect(_key('pause-main-menu'));
      expect(rules.top, greaterThanOrEqualTo(resign.bottom));
      expect(menu.top, closeTo(rules.bottom, 0.01));
      expect(
        tester.getRect(_key('pause-rules-box')).top - resign.bottom,
        closeTo(9, 0.01),
        reason: 'pause: the drawn gap moved',
      );
    });
  });

  group('the result card', () {
    testWidgets('See statistics opens this mode\'s tab; back returns to the '
        'card without a new entry', (tester) async {
      final r = await _board(tester, setup: twoPlayerDefault);
      await _foolsMate(tester, r.h.controller);
      await tester.pump(resultDelay);
      await _settle(tester);
      await _tapKey(tester, 'result-see-statistics');
      expect(find.byType(StatsScreen), findsOneWidget);
      expect(_tab<PlayMode>(tester), PlayMode.two);
      await _back(tester);
      expect(find.byType(StatsScreen), findsNothing);
      expect(r.h.controller.state.resultView, ResultView.card);
      expect(_key('result-card'), findsOneWidget);
      expect(
        tester.widget<FadeTransition>(_key('result-overlay')).opacity.value,
        1,
        reason: 'result: the card entered again',
      );
    });

    testWidgets('Main menu from the card records nothing more', (tester) async {
      final r = await _board(tester);
      final c = r.h.controller;
      _move(c, 'e2e4');
      await tester.pump();
      expect(c.resign(), isTrue);
      await _settle(tester);
      await r.h.saves.flush();
      expect(_played(r.h), 1, reason: 'test: the resignation is counted');
      await _tapKey(tester, 'result-main-menu');
      expect(_onMenu(), isTrue);
      await r.h.saves.flush();
      expect(_played(r.h), 1, reason: 'main menu: counted again');
      expect(r.h.stats.document.recentIds, hasLength(1));
      expect(r.h.saves.offered, isNull, reason: 'main menu: a finished game');
    });

    testWidgets('the resignation text makes no claim about statistics', (
      tester,
    ) async {
      final r = await _board(tester);
      _move(r.h.controller, 'e2e4');
      await tester.pump();
      r.h.controller.resign();
      await _settle(tester);
      final body = tester.widget<Text>(_key('result-body')).data!;
      expect(body, 'Resignation ends the game at once.');
      expect(body.toLowerCase(), isNot(contains('statistics')));
    });

    testWidgets('2 dp either side of the midpoint between See statistics and '
        'Main menu reach each', (tester) async {
      final r = await _board(tester);
      r.h.controller.resign();
      await _settle(tester);
      final stats = tester.getRect(_key('result-see-statistics-box'));
      final menu = tester.getRect(_key('result-main-menu-box'));
      expect(stats.height, 41.5);
      expect(menu.height, 37);
      expect(menu.top - stats.bottom, closeTo(9, 0.01));
      for (final key in ['result-see-statistics', 'result-main-menu']) {
        expect(tester.getSize(_key(key)).height, greaterThanOrEqualTo(48));
      }
      final mid = (stats.bottom + menu.top) / 2;
      await tester.tapAt(Offset(stats.center.dx, mid - 2));
      await _settle(tester);
      expect(find.byType(StatsScreen), findsOneWidget, reason: 'above: stats');
      await _back(tester);
      await tester.tapAt(Offset(stats.center.dx, mid + 2));
      await _settle(tester);
      expect(_onMenu(), isTrue, reason: 'below: Main menu');
    });
  });

  group('New', () {
    testWidgets('vs Computer: pauses and opens its setup, no sheet; back '
        'shows the pause card', (tester) async {
      final r = await _board(tester);
      final c = r.h.controller;
      await _bothMoved(tester, r);
      await _tapKey(tester, 'tool-new');
      expect(find.byType(ComputerSetupScreen), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing, reason: 'new: a sheet');
      expect(c.state.paused, isTrue, reason: 'new: the game goes on');
      final clocks = _clocks(c);
      await _back(tester);
      expect(find.byType(ComputerSetupScreen), findsNothing);
      expect(_key('pause-card'), findsOneWidget);
      expect(_clocks(c), clocks);
      expect([for (final m in c.game.moves) m.toUci()], ['e2e4', 'e7e5']);
    });

    testWidgets('Two players: opens its setup, no sheet', (tester) async {
      final r = await _board(tester, setup: twoPlayerDefault);
      _move(r.h.controller, 'e2e4');
      await tester.pump();
      await _tapKey(tester, 'tool-new');
      expect(find.byType(TwoPlayerSetupScreen), findsOneWidget);
      expect(find.byType(ComputerSetupScreen), findsNothing);
      expect(find.byType(BottomSheet), findsNothing, reason: 'new: a sheet');
      await _tapKey(tester, 'psetup-back');
      expect(_key('pause-card'), findsOneWidget);
    });

    testWidgets('in view-board mode: the result card is there on return', (
      tester,
    ) async {
      final r = await _board(tester, setup: twoPlayerDefault);
      await _foolsMate(tester, r.h.controller);
      await tester.pump(resultDelay);
      await _settle(tester);
      await _tapKey(tester, 'result-view-board');
      expect(r.h.controller.state.resultView, ResultView.board);
      await _tapKey(tester, 'tool-new');
      expect(find.byType(TwoPlayerSetupScreen), findsOneWidget);
      await _back(tester);
      expect(r.h.controller.state.resultView, ResultView.card);
      expect(_key('result-card'), findsOneWidget);
    });

    testWidgets('during the result delay: the card is there on return', (
      tester,
    ) async {
      final r = await _board(tester, setup: twoPlayerDefault);
      await _foolsMate(tester, r.h.controller);
      await tester.pump(resultDelay ~/ 4);
      expect(_key('result-card'), findsNothing, reason: 'test: still waiting');
      await _tapKey(tester, 'tool-new');
      expect(find.byType(TwoPlayerSetupScreen), findsOneWidget);
      await _back(tester);
      expect(_key('result-card'), findsOneWidget);
    });
  });

  group('back on the board', () {
    testWidgets('a live game: the pause card, then back resumes; never a pop', (
      tester,
    ) async {
      final r = await _board(tester);
      final c = r.h.controller;
      _move(c, 'e2e4');
      await tester.pump();
      await _back(tester);
      expect(find.byType(GameScreen), findsOneWidget, reason: 'back: popped');
      expect(_key('pause-card'), findsOneWidget);
      expect(c.state.paused, isTrue);
      await _back(tester);
      expect(find.byType(GameScreen), findsOneWidget, reason: 'back: popped');
      expect(c.state.paused, isFalse, reason: 'back: the card stayed');
      expect(_key('pause-card'), findsNothing);
    });

    testWidgets('a finished game: View board, then the menu, counted once', (
      tester,
    ) async {
      final r = await _board(tester);
      final c = r.h.controller;
      _move(c, 'e2e4');
      await tester.pump();
      c.resign();
      await _settle(tester);
      await _back(tester);
      expect(c.state.resultView, ResultView.board);
      expect(find.byType(GameScreen), findsOneWidget);
      await _back(tester);
      expect(_onMenu(), isTrue, reason: 'back: not the menu from the board');
      await r.h.saves.flush();
      expect(_played(r.h), 1);
      expect(r.h.stats.document.recentIds, hasLength(1));
    });

    testWidgets('during the result delay: the card at once, then View board, '
        'then the menu', (tester) async {
      final r = await _board(tester, setup: twoPlayerDefault);
      final c = r.h.controller;
      await _foolsMate(tester, c);
      await tester.pump(resultDelay ~/ 4);
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(resultRiseDuration);
      expect(_key('result-card'), findsOneWidget, reason: 'back: no card');
      expect(c.state.resultView, ResultView.card);
      await _back(tester);
      expect(c.state.resultView, ResultView.board);
      await tester.tap(_key('result-bar-show'));
      await _settle(tester);
      expect(c.state.resultView, ResultView.card, reason: 'bar: no card');
      await _back(tester);
      await _back(tester);
      expect(_onMenu(), isTrue);
    });
  });

  group('Restart', () {
    testWidgets('after your move: counted as a loss, and it says so for 3 s', (
      tester,
    ) async {
      final r = await _board(tester);
      _move(r.h.controller, 'e2e4');
      await tester.pump();
      await tester.tap(_key('tool-restart'));
      await tester.pump();
      await r.h.saves.flush();
      await tester.pump();
      expect(_played(r.h), 1, reason: 'restart: the loss was not counted');
      expect(find.text(restartLossText), findsOneWidget);
      await tester.pump(restartLossShown);
      expect(find.text(restartLossText), findsNothing, reason: 'restart: 3 s');
    });

    testWidgets('before your first move: nothing counted, nothing said', (
      tester,
    ) async {
      final r = await _board(tester);
      await tester.tap(_key('tool-restart'));
      await tester.pump();
      await r.h.saves.flush();
      await tester.pump();
      expect(r.h.controller.game.moves, isEmpty);
      expect(_played(r.h), 0);
      expect(find.text(restartLossText), findsNothing);
    });

    testWidgets('a reopened, already-counted game: nothing said', (
      tester,
    ) async {
      final r = await _board(tester);
      final c = r.h.controller;
      _move(c, 'e2e4');
      await tester.pump();
      c.resign();
      await _settle(tester);
      await r.h.saves.flush();
      await _tapKey(tester, 'result-view-board');
      await _tapKey(tester, 'tool-takeback');
      expect(c.game.isOver, isFalse, reason: 'test: reopened');
      await tester.tap(_key('tool-restart'));
      await tester.pump();
      await r.h.saves.flush();
      await tester.pump();
      expect(_played(r.h), 1);
      expect(find.text(restartLossText), findsNothing);
    });
  });

  test('the temporary picker is gone from the source tree', () {
    expect(File('lib/ui/game/temporary_new_game.dart').existsSync(), isFalse);
    final naming = [
      for (final file in Directory('lib').listSync(recursive: true))
        if (file is File &&
            file.path.endsWith('.dart') &&
            file.readAsStringSync().contains('TemporaryNewGamePicker'))
          file.path,
    ];
    expect(naming, isEmpty);
  });
}
