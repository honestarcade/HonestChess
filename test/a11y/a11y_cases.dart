// Every screen and state the accessibility tests walk (#103's labels,
// #104's guidelines): one table, so a screen added later is added once and
// both suites cover it.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:honest_chess/data/app_loader.dart';
import 'package:honest_chess/data/app_store.dart';
import 'package:honest_chess/data/game_saves.dart';
import 'package:honest_chess/data/play_mode.dart';
import 'package:honest_chess/data/settings_store.dart';
import 'package:honest_chess/data/stats.dart';
import 'package:honest_chess/engine/engine.dart';
import 'package:honest_chess/ui/board/board_options.dart';
import 'package:honest_chess/ui/board/promotion_sheet.dart';
import 'package:honest_chess/ui/game/defaults.dart';
import 'package:honest_chess/ui/game/game_controller.dart';
import 'package:honest_chess/ui/game/game_screen.dart';
import 'package:honest_chess/ui/screens/about_app_screen.dart';
import 'package:honest_chess/ui/screens/about_arcade_screen.dart';
import 'package:honest_chess/ui/screens/computer_setup_screen.dart';
import 'package:honest_chess/ui/screens/how_to_play_screen.dart';
import 'package:honest_chess/ui/screens/menu_screen.dart';
import 'package:honest_chess/ui/screens/settings_screen.dart';
import 'package:honest_chess/ui/screens/splash_screen.dart';
import 'package:honest_chess/ui/screens/stats_screen.dart';
import 'package:honest_chess/ui/screens/two_player_setup_screen.dart';

import '../support/app_harness.dart';
import '../support/gated_store.dart';
import '../ui/game/fake_computer.dart';

/// One screen in one state: [pump] builds it from nothing under the
/// harness, at whatever view size the test set, and checks it arrived.
/// [controls] is how many controls the screen draws, the board's squares
/// aside: #104's guideline suite finds at least that many tappable nodes.
class A11yCase {
  const A11yCase(this.name, this.pump, {this.controls = 0});

  final String name;
  final Future<void> Function(WidgetTester tester) pump;
  final int controls;

  @override
  String toString() => name;
}

Finder _key(String key) => find.byKey(Key(key));

/// Past every route fade and card entrance the screens have.
Future<void> settleCase(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump();
}

Future<void> _screen(WidgetTester tester, Widget screen) async {
  await pumpUnderScope(tester, screen);
  await settleCase(tester);
}

/// Every counter set, so each statistic shows a value.
StatsDocument get _fullStats => StatsDocument(
  computer: ComputerStats(
    played: 120,
    won: 50,
    drawn: 20,
    lost: 50,
    streak: 3,
    longestMoves: 64,
    steps: {
      for (final step in Strength.values)
        step: const StepStats(played: 20, won: 8),
    },
  ),
  two: TwoPlayerStats(
    played: 40,
    whiteWins: 18,
    blackWins: 16,
    drawn: 6,
    longestMoves: 71,
    clocks: {for (final c in StatsClock.values) c: 8},
  ),
);

/// Setup choices with Custom picked on both setups; with [atLimits], its
/// minutes at their most and its increment at its least.
SettingsStore _customSettings({bool atLimits = false}) {
  final settings = SettingsStore();
  settings.updateSetup(
    (c) => SetupChoices(
      computer: c.computer.copyWith(time: TimeChoice.custom),
      two: c.two.copyWith(time: TimeChoice.custom),
      custom: atLimits
          ? const CustomTime(
              minutes: customMinutesMax,
              increment: customIncrementMin,
            )
          : c.custom,
    ),
  );
  return settings;
}

/// A started game of [mode], saved as the app saves it.
Game _started(GameMode mode) {
  final game = Game.start(mode, Timed.rapid);
  return game.play(Move.fromUci(game.position, 'e2e4'));
}

const _vsClub = VsComputer(
  playerColour: Colour.white,
  step: Strength.club,
  seed: 1,
);

/// The menu over [store], its saves loaded.
Future<void> _menu(WidgetTester tester, AppStore store) async {
  final saves = GameSaves(store);
  addTearDown(saves.dispose);
  await saves.loadAll();
  await pumpUnderScope(tester, const MenuScreen(), store: store, saves: saves);
  await settleCase(tester);
}

/// The play screen over [controller]'s game, as the app shows it.
Future<GameController> _board(
  WidgetTester tester,
  GameController controller,
) async {
  addTearDown(controller.dispose);
  await pumpUnderScope(
    tester,
    GameScreen(options: controller.options, controller: controller),
    controller: controller,
  );
  await settleCase(tester);
  return controller;
}

/// A game against the computer at Club, you White and to move, the
/// computer never answering unless the test answers through [computers].
GameController _vsComputer({String? fen, FakeComputers? computers}) =>
    GameController(
      fen: fen,
      mode: _vsClub,
      timeControl: Timed.rapid,
      computer: (computers ?? FakeComputers()).call,
    );

/// A result card over a game you ended: resigned against the computer
/// (a loss), or a draw agreed between two players.
Future<void> _ended(WidgetTester tester, {required bool draw}) async {
  final c = await _board(
    tester,
    draw
        ? GameController(mode: const TwoPlayer(), timeControl: Timed.rapid)
        : _vsComputer(),
  );
  if (draw) {
    for (final uci in ['e2e4', 'e7e5']) {
      final move = Move.fromUci(c.game.position, uci);
      c.move(move.from, move.to);
    }
    c.pause();
    await c.offerDraw();
    expect(c.game.status, const Draw(GameEndReason.agreement));
  } else {
    c.resign();
    expect(c.game.status, isA<Win>());
  }
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1500));
  expect(_key('result-card'), findsOneWidget);
}

/// A result card over a game White won on time.
Future<void> _result(WidgetTester tester, {required bool viewBoard}) async {
  var now = 0;
  final c = await _board(
    tester,
    GameController(
      fen: 'k7/8/8/8/8/8/1Q6/K7 w - - 0 1',
      timeControl: Timed.blitz,
      now: () => now,
    ),
  );
  c.move(Square.parse('a1'), Square.parse('a2'));
  now += Timed.blitz.initialMs + 1;
  c.checkFlag();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1500));
  expect(_key('result-card'), findsOneWidget);
  if (viewBoard) {
    await tester.tap(_key('result-view-board'));
    await settleCase(tester);
    expect(_key('result-bar'), findsOneWidget);
  }
}

/// Every screen and state, overlays included.
final a11yCases = <A11yCase>[
  A11yCase('the menu', (tester) async {
    await _menu(tester, AppStore.memory());
    expect(_key('menu-continue'), findsNothing);
  }, controls: 7),
  for (final mode in PlayMode.values)
    A11yCase('the menu, Continue ${mode.name} and the banner', (tester) async {
      final store = AppStore.memory();
      await seedSavedGame(
        store,
        _started(mode == PlayMode.computer ? _vsClub : const TwoPlayer()),
      );
      await _menu(tester, store);
      store.corruptionNotices.value = {StoreDoc.stats};
      await settleCase(tester);
      expect(_key('menu-continue'), findsOneWidget);
      expect(_key('menu-banner'), findsOneWidget);
    }, controls: 9),
  A11yCase('the vs-computer setup, Custom, Keep playing and the loss warning', (
    tester,
  ) async {
    final store = AppStore.memory();
    await seedSavedGame(
      store,
      _started(_vsClub),
      recorded: {'id': '00000000000000c0', 'started': true, 'outcome': false},
    );
    final saves = GameSaves(store);
    final settings = _customSettings();
    addTearDown(() {
      saves.dispose();
      settings.dispose();
    });
    await saves.loadAll();
    await pumpUnderScope(
      tester,
      const ComputerSetupScreen(),
      store: store,
      saves: saves,
      settings: settings,
    );
    await settleCase(tester);
    // Built only once scrolled to, on a short screen: seen, then back to
    // the top where the case starts.
    final scroll = find.descendant(
      of: _key('csetup-scroll'),
      matching: find.byType(Scrollable),
    );
    for (final key in [
      'csetup-minutes-value',
      'csetup-loss-warning',
      'csetup-keep-playing',
    ]) {
      await tester.scrollUntilVisible(_key(key), 100, scrollable: scroll);
      expect(_key(key), findsOneWidget);
    }
    tester.state<ScrollableState>(scroll).position.jumpTo(0);
    await settleCase(tester);
  }, controls: 20),
  A11yCase('the two-player setup, Custom', (tester) async {
    final settings = _customSettings();
    addTearDown(settings.dispose);
    await pumpUnderScope(
      tester,
      const TwoPlayerSetupScreen(),
      settings: settings,
    );
    await settleCase(tester);
    expect(_key('psetup-minutes-value'), findsOneWidget);
  }, controls: 12),
  A11yCase('the two-player setup, Custom, its steppers at their limits', (
    tester,
  ) async {
    final settings = _customSettings(atLimits: true);
    addTearDown(settings.dispose);
    await pumpUnderScope(
      tester,
      const TwoPlayerSetupScreen(),
      settings: settings,
    );
    await settleCase(tester);
    expect(_key('psetup-minutes-value'), findsOneWidget);
  }, controls: 10),
  A11yCase('Settings, a game in progress', (tester) async {
    final controller = _vsComputer();
    addTearDown(controller.dispose);
    await pumpUnderScope(
      tester,
      const SettingsScreen(),
      controller: controller,
    );
    await settleCase(tester);
  }, controls: 21),
  A11yCase(
    'How to play, the pieces',
    (tester) => _screen(tester, const HowToPlayScreen()),
    controls: 3,
  ),
  A11yCase(
    'How to play, the rules',
    (tester) =>
        _screen(tester, const HowToPlayScreen(initialTab: HowToTab.rules)),
    controls: 3,
  ),
  A11yCase(
    'About the app',
    (tester) => _screen(tester, const AboutAppScreen()),
    controls: 4,
  ),
  A11yCase(
    'About Honest Arcade',
    (tester) => _screen(tester, const AboutArcadeScreen()),
    controls: 4,
  ),
  for (final mode in PlayMode.values)
    A11yCase('Statistics, ${mode.name}', (tester) async {
      final store = AppStore.memory();
      await store.write(StoreDoc.stats, _fullStats.toJson());
      final stats = StatsRecorder(store: store);
      addTearDown(stats.dispose);
      await stats.load();
      await pumpUnderScope(
        tester,
        StatsScreen(openOn: mode),
        store: store,
        stats: stats,
      );
      await settleCase(tester);
    }, controls: 4),
  A11yCase('Statistics, nothing played yet', (tester) async {
    await pumpUnderScope(tester, const StatsScreen());
    await settleCase(tester);
    expect(_key('stats-scroll'), findsOneWidget);
  }, controls: 4),
  A11yCase('Statistics, its reset card', (tester) async {
    await pumpUnderScope(tester, const StatsScreen());
    await settleCase(tester);
    final reset = _key('stats-reset');
    await tester.scrollUntilVisible(
      reset,
      100,
      scrollable: find.descendant(
        of: _key('stats-scroll'),
        matching: find.byType(Scrollable),
      ),
    );
    // At its top, so nothing drawn at the screen's foot covers it.
    await tester.ensureVisible(reset);
    await tester.pump();
    await tester.tap(reset);
    await settleCase(tester);
    expect(_key('stats-reset-card'), findsOneWidget);
  }, controls: 3),
  A11yCase('the splash, its store never answering', (tester) async {
    final store = GatedStore();
    final settings = SettingsStore();
    final stats = StatsRecorder(store: store);
    final saves = GameSaves(store);
    final loader = AppLoader(
      store: store,
      settings: settings,
      stats: stats,
      saves: saves,
    );
    addTearDown(() {
      loader.dispose();
      saves.dispose();
      stats.dispose();
      settings.dispose();
    });
    await pumpUnderScope(tester, SplashScreen(loader: loader));
    await tester.pump(const Duration(milliseconds: 200));
    expect(_key('splash'), findsOneWidget);
  }),
  A11yCase('the board, you to move', (tester) async {
    final c = await _board(tester, _vsComputer());
    expect(c.game.position.sideToMove, Colour.white);
  }, controls: 4),
  A11yCase('the board, a piece selected', (tester) async {
    await _board(tester, _vsComputer());
    await tester.tap(_key('cell-e2'));
    await settleCase(tester);
    expect(_key('ring-selected-e2'), findsOneWidget);
  }, controls: 4),
  A11yCase('the board, two players', (tester) async {
    await _board(
      tester,
      GameController(mode: const TwoPlayer(), timeControl: Timed.blitz),
    );
  }, controls: 4),
  A11yCase('the board, two players, turned round with Black at the bottom', (
    tester,
  ) async {
    final c = await _board(
      tester,
      GameController(
        mode: const TwoPlayer(),
        timeControl: Timed.blitz,
        options: const BoardOptions(rotateEachTurn: true),
      ),
    );
    c.move(Square.parse('e2'), Square.parse('e4'));
    await settleCase(tester);
    expect(c.game.position.sideToMove, Colour.black);
    expect(
      tester.getTopLeft(_key('cell-h1')).dy,
      lessThan(tester.getTopLeft(_key('cell-h8')).dy),
      reason: 'a11y cases: Black is at the bottom',
    );
  }, controls: 5),
  A11yCase('the board in check', (tester) async {
    final c = await _board(
      tester,
      GameController(
        fen: 'k7/8/8/8/8/8/8/K6r w - - 0 1',
        timeControl: Timed.rapid,
      ),
    );
    expect(c.state.inCheck, isNotNull);
  }, controls: 4),
  A11yCase('the board, its promotion card', (tester) async {
    final c = await _board(
      tester,
      GameController(
        fen: '3r3k/4P3/8/8/8/8/8/K7 w - - 0 1',
        timeControl: Timed.rapid,
      ),
    );
    c.move(Square.parse('e7'), Square.parse('e8'));
    await tester.pump();
    await tester.pump(promotionEnterDuration);
    await tester.pump();
    expect(_key('promo-card'), findsOneWidget);
  }, controls: 9),
  A11yCase('the board, its pause card', (tester) async {
    await _board(tester, _vsComputer());
    await tester.tap(_key('pause-pill'));
    await settleCase(tester);
    expect(_key('pause-card'), findsOneWidget);
  }, controls: 8),
  A11yCase('the board, its pause card after a declined draw', (tester) async {
    final fakes = FakeComputers();
    final c = await _board(tester, _vsComputer(computers: fakes));
    c.move(Square.parse('e2'), Square.parse('e4'));
    await tester.pump();
    fakes.current.last.move('e7e5');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(c.game.position.sideToMove, Colour.white);
    await tester.tap(_key('pause-pill'));
    await settleCase(tester);
    final offer = c.offerDraw();
    await tester.pump();
    fakes.current.draws.single.decline();
    await offer;
    // Held, as leaving the app holds it, so the message outlasts the test.
    c.autoPause();
    await settleCase(tester);
    expect(_key('pause-declined'), findsOneWidget);
  }, controls: 9),
  A11yCase('the board, the computer could not move', (tester) async {
    final fakes = FakeComputers();
    final c = GameController(
      mode: const VsComputer(
        playerColour: Colour.black,
        step: Strength.club,
        seed: 1,
      ),
      timeControl: Timed.rapid,
      computer: fakes.call,
    );
    await _board(tester, c);
    fakes.current.last.fail();
    await tester.pump();
    fakes.current.last.fail();
    await settleCase(tester);
    expect(c.state.computerFailed, isTrue);
  }, controls: 5),
  A11yCase(
    'the board, its result card',
    (tester) => _result(tester, viewBoard: false),
    controls: 7,
  ),
  A11yCase(
    'the board, its result card after a loss',
    (tester) => _ended(tester, draw: false),
    controls: 7,
  ),
  A11yCase(
    'the board, its result card after a draw',
    (tester) => _ended(tester, draw: true),
    controls: 7,
  ),
  A11yCase(
    'the board, View board',
    (tester) => _result(tester, viewBoard: true),
    controls: 5,
  ),
];
