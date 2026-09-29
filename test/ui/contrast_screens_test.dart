// Every screen's text passes a computed contrast check (#99, #141): each
// text reaches its ratio against the fills it is drawn over, and each text
// colour drawn is a Palette.textPairs row that
// test/guards/contrast_test.dart proves by arithmetic. Every screen at 390 × 844 on the navy theme,
// scrolled end to end; the board bare and with each card; Settings with
// its sound and motion switches shown. The complement: a colour no row
// proves fails the check (the last test).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:honest_chess/data/app_loader.dart';
import 'package:honest_chess/data/app_store.dart';
import 'package:honest_chess/data/game_saves.dart';
import 'package:honest_chess/data/settings_store.dart';
import 'package:honest_chess/data/stats.dart';
import 'package:honest_chess/engine/engine.dart';
import 'package:honest_chess/ui/game/defaults.dart';
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
import '../support/checked_text_guideline.dart';
import 'game/fake_computer.dart';
import 'promotion_sheet_test.dart' show pumpScreen, tapMove;

Finder _key(String key) => find.byKey(Key(key));

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _check(WidgetTester tester) =>
    expectLater(tester, meetsGuideline(const CheckedTextGuideline()));

/// Checks the screen, then again after each scroll until every scrollable
/// on it has reached its end, so text below the fold is measured too.
Future<void> _checkScrolled(WidgetTester tester) async {
  await _check(tester);
  final scrollables = find.byType(Scrollable);
  for (var i = 0; i < scrollables.evaluate().length; i++) {
    final state = tester.state<ScrollableState>(scrollables.at(i));
    if (state.position.axis != Axis.vertical) continue;
    while (state.position.pixels < state.position.maxScrollExtent) {
      state.position.jumpTo(
        (state.position.pixels + 300).clamp(0, state.position.maxScrollExtent),
      );
      await tester.pump();
      await _check(tester);
    }
  }
}

Future<void> _screen(WidgetTester tester, Widget screen) async {
  _phone(tester);
  await pumpUnderScope(tester, screen);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await _checkScrolled(tester);
}

void main() {
  testWidgets('the menu, with Continue and the damaged-data banner', (
    tester,
  ) async {
    _phone(tester);
    final store = AppStore.memory();
    await seedSavedGame(
      store,
      Game.start(
        const VsComputer(
          playerColour: Colour.white,
          step: Strength.club,
          seed: 7,
        ),
        const Untimed(),
      ),
    );
    final saves = GameSaves(store);
    addTearDown(saves.dispose);
    await saves.loadAll();
    await pumpUnderScope(
      tester,
      const MenuScreen(),
      store: store,
      saves: saves,
    );
    await tester.pump();
    await _checkScrolled(tester);
    store.corruptionNotices.value = {StoreDoc.settings};
    await tester.pump();
    expect(_key('menu-banner'), findsOneWidget);
    await _checkScrolled(tester);
  });

  testWidgets('the vs-computer setup', (tester) async {
    await _screen(tester, const ComputerSetupScreen());
  });

  testWidgets('the two-player setup', (tester) async {
    await _screen(tester, const TwoPlayerSetupScreen());
  });

  testWidgets('Settings, with the sound and motion switches', (tester) async {
    await _screen(tester, const SettingsScreen());
    for (final toggle in ['sfx', 'music', 'haptics', 'anim']) {
      expect(
        _key('settings-toggle-$toggle'),
        findsOneWidget,
        reason: 'contrast screens: Settings shows $toggle',
      );
    }
  });

  testWidgets('How to play, both tabs', (tester) async {
    await _screen(tester, const HowToPlayScreen());
    await _screen(tester, const HowToPlayScreen(initialTab: HowToTab.rules));
  });

  testWidgets('About the App', (tester) async {
    await _screen(tester, const AboutAppScreen());
  });

  testWidgets('About Honest Arcade', (tester) async {
    await _screen(tester, const AboutArcadeScreen());
  });

  testWidgets('Statistics, and its reset card', (tester) async {
    _phone(tester);
    final store = AppStore.memory();
    final stats = StatsRecorder(store: store);
    final saves = GameSaves(store);
    addTearDown(() {
      saves.dispose();
      stats.dispose();
    });
    await stats.load();
    await pumpUnderScope(
      tester,
      const StatsScreen(),
      store: store,
      stats: stats,
      saves: saves,
    );
    await tester.pump();
    await _checkScrolled(tester);
    await tester.tap(_key('stats-reset'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(_key('stats-reset-card'), findsOneWidget);
    await _check(tester);
  });

  testWidgets('the splash', (tester) async {
    _phone(tester);
    final store = AppStore.memory();
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
    expect(_key('splash-label'), findsOneWidget);
    await _check(tester);
    // The loader never starts, so the splash stays; its floor timer ends.
    await tester.pump(splashFloor);
  });

  testWidgets('the board, and its pause card', (tester) async {
    _phone(tester);
    final fakes = FakeComputers();
    await pumpBoard(tester, computerFactory: fakes.call);
    await _check(tester);
    await tester.tap(_key('pause-pill'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(_key('pause-card'), findsOneWidget);
    await _check(tester);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the board in check, and its promotion card', (tester) async {
    await pumpScreen(tester, fen: '3r3k/4P3/8/8/8/8/8/K2r4 w - - 0 1');
    await tester.pump(const Duration(milliseconds: 300));
    await _check(tester);
    await tester.pumpWidget(const SizedBox());
    await pumpScreen(tester);
    await tapMove(tester, 'e7', 'e8');
    expect(_key('promo-card'), findsOneWidget);
    await _check(tester);
  });

  testWidgets('the result card, and the result bar', (tester) async {
    _phone(tester);
    final h = await pumpBoard(tester, setup: twoPlayerDefault);
    for (final uci in ['f2f3', 'e7e5', 'g2g4', 'd8h4']) {
      h.controller.move(
        Square.parse(uci.substring(0, 2)),
        Square.parse(uci.substring(2)),
      );
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 1500));
    expect(_key('result-card'), findsOneWidget);
    await _check(tester);
    await tester.tap(_key('result-view-board'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(_key('result-bar'), findsOneWidget);
    await _check(tester);
  });

  testWidgets('a proven colour on a fill it does not read on fails the '
      'check', (tester) async {
    _phone(tester);
    await pumpUnderScope(
      tester,
      const Center(
        child: ColoredBox(
          color: Color(0xFFAAAAAA),
          child: Text('Unread', style: TextStyle(color: Color(0xFFFFFFFF))),
        ),
      ),
    );
    final evaluation = const CheckedTextGuideline().evaluate(tester);
    expect(evaluation.passed, isFalse);
    expect(
      evaluation.reason,
      allOf(
        contains('"Unread" in #FFFFFFFF'),
        contains('is drawn on #FFAAAAAA: 2.32:1'),
      ),
    );
  });

  testWidgets('a colour no row proves fails the check', (tester) async {
    _phone(tester);
    await pumpUnderScope(
      tester,
      const Center(
        child: Text('Unproven', style: TextStyle(color: Color(0xFF123456))),
      ),
    );
    final evaluation = const CheckedTextGuideline().evaluate(tester);
    expect(evaluation.passed, isFalse);
    expect(evaluation.reason, contains('"Unproven" is drawn in #FF123456'));
  });
}
