// The menu (#91): the app opens on it, Continue shows only for a saved game
// in progress, every entry opens its screen, ‹ and the phone's back return,
// back on the menu leaves the app, and #80's damaged-data banner.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:honest_chess/data/app_store.dart';
import 'package:honest_chess/data/play_mode.dart';
import 'package:honest_chess/engine/engine.dart';
import 'package:honest_chess/main.dart';
import 'package:honest_chess/ui/app_scope.dart';
import 'package:honest_chess/ui/game/defaults.dart';
import 'package:honest_chess/ui/game/game_screen.dart';
import 'package:honest_chess/ui/screens/how_to_play_screen.dart';
import 'package:honest_chess/ui/screens/menu_screen.dart';
import 'package:honest_chess/ui/theme/palette.dart';
import 'package:honest_chess/ui/widgets/segmented_tabs.dart';

import '../flutter_test_config.dart';
import '../support/app_harness.dart';
import 'game/fake_computer.dart';
import 'piece_font_test.dart' show cmapCodePoints;

Finder _key(String key, {bool skipOffstage = true}) =>
    find.byKey(Key(key), skipOffstage: skipOffstage);

/// Every menu entry but Continue, with the key its screen's back carries.
const _entries = [
  (entry: 'menu-vs-computer', back: 'csetup-back'),
  (entry: 'menu-two-players', back: 'psetup-back'),
  (entry: 'menu-statistics', back: 'stats-back'),
  (entry: 'menu-how-to-play', back: 'howto-back'),
  (entry: 'menu-settings', back: 'settings-back'),
  (entry: 'menu-about-app', back: 'aboutapp-back'),
  (entry: 'menu-about-arcade', back: 'aboutstudio-back'),
];

/// The app on [store], past its launch load, on a 390 × 844 phone: through
/// the splash when [splash], otherwise straight onto the menu.
Future<HonestChessAppState> _launch(
  WidgetTester tester,
  AppStore store, {
  bool splash = false,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    HonestChessApp(
      key: UniqueKey(),
      computerFactory: FakeComputers().call,
      store: store,
      platform: FakePlatformChannel(),
      skipSplash: !splash,
    ),
  );
  if (splash) {
    await pumpUntilFound(tester, _key('menu-vs-computer'));
    // The menu's fade in, during which the navigating flag ignores taps.
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump();
  }
  return tester.state<HonestChessAppState>(find.byType(HonestChessApp));
}

/// Whether the menu is the route on screen.
bool _onMenu() =>
    _key('menu-vs-computer').evaluate().length == 1 &&
    _entries.every((e) => _key(e.back).evaluate().isEmpty) &&
    find.byType(GameScreen).evaluate().isEmpty;

Game _play(Game game, List<String> ucis) {
  for (final uci in ucis) {
    game = game.play(
      Move.fromUci(game.position, uci),
      byComputer:
          game.mode is VsComputer &&
          game.sideToMove != (game.mode as VsComputer).playerColour,
    );
  }
  return game;
}

/// A game against Club, you White, after [ucis].
Game _computerGame(List<String> ucis) => _play(
  Game.start(
    const VsComputer(playerColour: Colour.white, step: Strength.club, seed: 7),
    const Untimed(),
  ),
  ucis,
);

Game _twoPlayerGame(List<String> ucis) =>
    _play(Game.start(const TwoPlayer(), const Untimed()), ucis);

String _text(String key) =>
    (find.byKey(Key(key)).evaluate().single.widget as Text).data!;

/// Records the platform channel's calls, answering none.
List<MethodCall> _platformCalls(WidgetTester tester) {
  final calls = <MethodCall>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      calls.add(call);
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return calls;
}

/// Back on a live board opens the pause card (#92); its Main menu leaves.
Future<void> _backToMenu(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
  await tester.tap(_key('pause-main-menu'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the app opens on the menu: the header, every entry, no '
      'Continue and no banner on a fresh install', (tester) async {
    final handle = tester.ensureSemantics();
    final root = await _launch(tester, AppStore.memory(), splash: true);
    expect(_onMenu(), isTrue, reason: 'menu: the app opens on the menu');
    expect(root.controller.isIdle, isTrue, reason: 'menu: no game started');
    expect(
      find.byType(GameScreen, skipOffstage: false),
      findsNothing,
      reason: 'menu: M3\'s launch board is gone',
    );
    for (final e in _entries) {
      expect(_key(e.entry), findsOneWidget, reason: 'menu: ${e.entry}');
    }
    expect(
      _key('menu-continue'),
      findsNothing,
      reason: 'menu: no Continue without a saved game',
    );
    expect(
      _key('menu-banner'),
      findsNothing,
      reason: 'menu: no banner without a notice',
    );
    expect(_key('menu-mark'), findsOneWidget);
    expect(
      tester.getSemantics(_key('menu-wordmark')),
      isSemantics(label: 'Honest Chess', isHeader: true),
      reason: 'menu: the wordmark is one header node',
    );
    expect(find.text(menuKickerText), findsOneWidget);
    expect(
      tester.getSemantics(_key('menu-two-players')),
      isSemantics(
        label: '$twoCardTitle, $twoCardSubtitle',
        isButton: true,
        hasTapAction: true,
      ),
      reason: 'menu: a card is one button reading its text',
    );
    // The About Honest Arcade bar sits at the bottom of the screen.
    final bar = tester.getRect(_key('menu-about-arcade-box'));
    expect(bar.bottom, moreOrLessEquals(844 - 24, epsilon: 0.5));
    handle.dispose();
  });

  test('› is drawn in Outfit, which has it', () {
    for (final file in testFonts['Outfit']!) {
      expect(
        cmapCodePoints(File(file).readAsBytesSync()),
        contains('›'.runes.single),
        reason: 'menu: $file has U+203A, so › needs no fallback',
      );
    }
  });

  testWidgets('Continue shows for a saved game, with its label and meta, '
      'for each mode', (tester) async {
    final store = AppStore.memory();
    await seedSavedGame(store, _computerGame(['e2e4', 'e7e5', 'g1f3', 'b8c6']));
    await _launch(tester, store);
    expect(_key('menu-continue'), findsOneWidget);
    expect(_text('menu-continue-label'), 'Continue vs Club');
    expect(_text('menu-continue-meta'), 'MOVE 3 · WHITE');

    // The two-player game saved last is the one offered.
    await seedSavedGame(store, _twoPlayerGame(['d2d4', 'd7d5', 'c2c4']));
    await _launch(tester, store);
    expect(_text('menu-continue-label'), 'Continue two-player');
    expect(
      _text('menu-continue-meta'),
      'MOVE 2 · BLACK',
      reason: 'menu: the fullmove number and the side to move',
    );
    expect(
      tester.getSemantics(_key('menu-continue')),
      isSemantics(
        label: 'Continue two-player, move 2, Black to move',
        isButton: true,
      ),
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Continue restores the saved game, paused, with its id', (
    tester,
  ) async {
    final store = AppStore.memory();
    final saved = _computerGame(['e2e4', 'e7e5']);
    await seedSavedGame(store, saved, recorded: {'id': '0123456789abcdef'});
    final root = await _launch(tester, store);
    await tester.tap(_key('menu-continue'));
    await tester.pumpAndSettle();
    expect(find.byType(GameScreen), findsOneWidget);
    expect(_key('sq-e4'), findsOneWidget);
    expect(
      _key('pause-card'),
      findsOneWidget,
      reason: 'menu: Continue opens the game paused',
    );
    expect(root.controller.game.moves, saved.moves);
    expect(root.controller.state.paused, isTrue);
    expect(
      root.controller.recorded['id'],
      '0123456789abcdef',
      reason: 'menu: the resumed game keeps its statistics id',
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a finished game on the board, nothing saved: no Continue', (
    tester,
  ) async {
    final root = await _launch(tester, AppStore.memory());
    await root.controller.newGame((
      mode: GameKind.twoPlayers,
      strength: null,
      colour: null,
      timeControl: const Untimed(),
    ));
    for (final uci in ['f2f3', 'e7e5', 'g2g4', 'd8h4']) {
      root.controller.move(
        Square.parse(uci.substring(0, 2)),
        Square.parse(uci.substring(2)),
      );
    }
    await root.saves.flush();
    await tester.pump();
    expect(root.controller.game.isOver, isTrue);
    expect(
      _key('menu-continue'),
      findsNothing,
      reason: 'menu: a finished game is never continued',
    );
  });

  testWidgets('every entry opens its screen; ‹ and the phone\'s back both '
      'return to the menu', (tester) async {
    await _launch(tester, AppStore.memory());
    for (final e in _entries) {
      for (final viaSystemBack in [false, true]) {
        await tester.tap(_key(e.entry));
        await tester.pumpAndSettle();
        expect(
          _key(e.back),
          findsOneWidget,
          reason: 'menu: ${e.entry} opens its screen',
        );
        if (e.entry == 'menu-how-to-play') {
          expect(
            tester
                .widget<SegmentedTabs<HowToTab>>(
                  find.byType(SegmentedTabs<HowToTab>),
                )
                .selected,
            HowToTab.pieces,
            reason: 'menu: How to play opens on The pieces',
          );
        }
        if (viaSystemBack) {
          await tester.binding.handlePopRoute();
        } else {
          await tester.tap(_key(e.back));
        }
        await tester.pumpAndSettle();
        expect(
          _onMenu(),
          isTrue,
          reason:
              'menu: ${viaSystemBack ? 'back' : '‹'} from ${e.entry} '
              'returns to the menu',
        );
      }
    }
  });

  testWidgets('a game started from the menu leaves the menu and one board', (
    tester,
  ) async {
    final root = await _launch(tester, AppStore.memory());
    await tester.tap(_key('menu-two-players'));
    await tester.pumpAndSettle();
    await tester.tap(_key('psetup-time-untimed'));
    await tester.pump();
    await tester.ensureVisible(_key('psetup-start'));
    await tester.tap(_key('psetup-start'));
    await tester.pumpAndSettle();
    expect(find.byType(GameScreen), findsOneWidget);
    expect(
      _key('psetup-back', skipOffstage: false),
      findsNothing,
      reason: 'menu: the setup screen is gone from the stack',
    );
    expect(_key('menu-vs-computer', skipOffstage: false), findsOneWidget);
    root.controller.move(Square.parse('e2'), Square.parse('e4'));
    await _backToMenu(tester);
    expect(_onMenu(), isTrue, reason: 'menu: Main menu from the board');
    await root.saves.flush();
    await tester.pump();
    expect(_text('menu-continue-meta'), 'MOVE 1 · BLACK');
  });

  testWidgets('back on the menu leaves the app, and the saved game '
      'survives', (tester) async {
    final store = AppStore.memory();
    await seedSavedGame(store, _computerGame(['e2e4', 'e7e5']));
    final root = await _launch(tester, store);
    await tester.tap(_key('menu-continue'));
    await tester.pumpAndSettle();
    root.controller.resume();
    root.controller.move(Square.parse('g1'), Square.parse('f3'));
    await tester.pump();

    final calls = _platformCalls(tester);
    await _backToMenu(tester);
    expect(_onMenu(), isTrue, reason: 'menu: Main menu from the board');
    expect(
      calls.where((c) => c.method == 'SystemNavigator.pop'),
      isEmpty,
      reason: 'menu: back from a screen does not leave the app',
    );
    final label = _text('menu-continue-label');
    final meta = _text('menu-continue-meta');
    expect(meta, 'MOVE 2 · BLACK');

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(
      calls.map((c) => c.method),
      contains('SystemNavigator.pop'),
      reason: 'menu: back on the menu leaves the app',
    );
    await root.saves.flush();

    await _launch(tester, store);
    expect(_text('menu-continue-label'), label);
    expect(
      _text('menu-continue-meta'),
      meta,
      reason: 'menu: the next launch offers the same game',
    );
    await tester.pumpWidget(const SizedBox());
  });

  group('a second tap during a transition opens nothing extra', () {
    Future<void> doubleTap(
      WidgetTester tester, {
      required String first,
      required String second,
      required String firstBack,
      required String secondBack,
      required bool viaHandlers,
    }) async {
      if (viaHandlers) {
        // Both handlers in one frame, before the navigator can absorb
        // the second pointer.
        tester.widget<GestureDetector>(_key(first)).onTap!();
        tester.widget<GestureDetector>(_key(second)).onTap!();
      } else {
        await tester.tap(_key(first));
        await tester.tap(_key(second), warnIfMissed: false);
      }
      await tester.pumpAndSettle();
      expect(
        _key(firstBack, skipOffstage: false),
        findsOneWidget,
        reason: 'menu: $first opened once',
      );
      if (secondBack != firstBack) {
        expect(
          _key(secondBack, skipOffstage: false),
          findsNothing,
          reason: 'menu: $second opened nothing',
        );
      }
      // The board's back is #92's; for a screen one ‹ lands on the menu.
      if (firstBack == 'sq-e4') return;
      await tester.tap(_key(firstBack));
      await tester.pumpAndSettle();
      expect(_onMenu(), isTrue, reason: 'menu: one back lands on the menu');
    }

    for (final viaHandlers in [false, true]) {
      final how = viaHandlers ? 'both handlers' : 'two taps';
      testWidgets('Statistics twice ($how)', (tester) async {
        await _launch(tester, AppStore.memory());
        await doubleTap(
          tester,
          first: 'menu-statistics',
          second: 'menu-statistics',
          firstBack: 'stats-back',
          secondBack: 'stats-back',
          viaHandlers: viaHandlers,
        );
      });

      testWidgets('vs Computer, then Settings ($how)', (tester) async {
        await _launch(tester, AppStore.memory());
        await doubleTap(
          tester,
          first: 'menu-vs-computer',
          second: 'menu-settings',
          firstBack: 'csetup-back',
          secondBack: 'settings-back',
          viaHandlers: viaHandlers,
        );
      });

      testWidgets('Continue, then How to play ($how)', (tester) async {
        final store = AppStore.memory();
        await seedSavedGame(store, _computerGame(['e2e4']));
        await _launch(tester, store);
        await doubleTap(
          tester,
          first: 'menu-continue',
          second: 'menu-how-to-play',
          firstBack: 'sq-e4',
          secondBack: 'howto-back',
          viaHandlers: viaHandlers,
        );
        await tester.pumpWidget(const SizedBox());
      });
    }
  });

  testWidgets('the banner shows for a damaged document, announced, and '
      'stays dismissed', (tester) async {
    final handle = tester.ensureSemantics();
    final store = AppStore.memory()..putRaw(StoreDoc.settings, '{not json');
    await _launch(tester, store);
    expect(_key('menu-banner'), findsOneWidget);
    expect(find.text(damagedDataText), findsOneWidget);
    expect(
      tester.getSemantics(_key('menu-banner-text')),
      isSemantics(label: damagedDataText, isLiveRegion: true),
      reason: 'menu: the banner is a live region, announced when it shows',
    );
    expect(
      tester.getSemantics(_key('menu-banner-dismiss')),
      isSemantics(label: dismissText, isButton: true, hasTapAction: true),
    );
    expect(
      tester.getSize(_key('menu-banner-dismiss')).height,
      greaterThanOrEqualTo(48),
    );
    expect(
      tester.getTopLeft(_key('menu-banner')).dy,
      lessThan(tester.getTopLeft(_key('menu-vs-computer')).dy),
    );

    // Still up after another screen.
    await tester.tap(_key('menu-settings'));
    await tester.pumpAndSettle();
    await tester.tap(_key('settings-back'));
    await tester.pumpAndSettle();
    expect(_key('menu-banner'), findsOneWidget);

    await tester.tap(_key('menu-banner-dismiss'));
    await tester.pump();
    expect(_key('menu-banner'), findsNothing, reason: 'menu: Dismiss');
    expect(store.corruptionNotices.value, isEmpty);
    await tester.tap(_key('menu-statistics'));
    await tester.pumpAndSettle();
    await tester.tap(_key('stats-back'));
    await tester.pumpAndSettle();
    expect(
      _key('menu-banner'),
      findsNothing,
      reason: 'menu: once dismissed it stays dismissed',
    );
    handle.dispose();
  });

  testWidgets('the banner sits above Continue', (tester) async {
    final store = AppStore.memory();
    await seedSavedGame(store, _computerGame(['e2e4']));
    store.putRaw(StoreDoc.stats, '{not json');
    await _launch(tester, store);
    expect(
      tester.getBottomLeft(_key('menu-banner-box')).dy,
      lessThan(tester.getTopLeft(_key('menu-continue-box')).dy),
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('pressed looks: Continue lightens, the Two players card '
      'presses violet, the bar deepens', (tester) async {
    final store = AppStore.memory();
    await seedSavedGame(store, _computerGame(['e2e4']));
    await _launch(tester, store);
    Color fill(String key) =>
        (tester.widget<Container>(_key(key)).decoration! as BoxDecoration)
            .color!;
    Color? edge(Finder f) =>
        ((tester.widget<Container>(f).decoration! as BoxDecoration).border!
                as Border)
            .top
            .color;
    final twoBox = find
        .descendant(
          of: _key('menu-two-players'),
          matching: find.byType(Container),
        )
        .first;

    expect(fill('menu-continue-box'), Palette.teal);
    var gesture = await tester.startGesture(
      tester.getCenter(_key('menu-continue')),
    );
    await tester.pump();
    expect(fill('menu-continue-box'), Palette.tealPressed);
    await gesture.cancel();
    await tester.pump();

    expect(edge(twoBox), Palette.borderStrong);
    gesture = await tester.startGesture(
      tester.getCenter(_key('menu-two-players')),
    );
    await tester.pump();
    expect(edge(twoBox), Palette.violet);
    await gesture.cancel();
    await tester.pump();

    expect(fill('menu-about-arcade-box'), Palette.tealPanelFill);
    gesture = await tester.startGesture(
      tester.getCenter(_key('menu-about-arcade')),
    );
    await tester.pump();
    expect(fill('menu-about-arcade-box'), Palette.tealBarPressed);
    await gesture.cancel();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('every menu tappable is at least 48 dp to touch', (tester) async {
    final store = AppStore.memory()..putRaw(StoreDoc.stats, '{not json');
    await seedSavedGame(store, _computerGame(['e2e4']));
    await _launch(tester, store);
    for (final key in [
      'menu-continue',
      'menu-banner-dismiss',
      for (final e in _entries) e.entry,
    ]) {
      final size = tester.getSize(_key(key));
      expect(
        (size.width >= 48, size.height >= 48),
        (true, true),
        reason: 'menu: $key is $size',
      );
    }
    // The four buttons are drawn 44 dp high, 10 dp apart, as designed.
    final stats = tester.getRect(_key('menu-statistics'));
    final settings = tester.getRect(_key('menu-settings'));
    expect(settings.top - stats.bottom, moreOrLessEquals(10 - 4));
    expect(
      AppScope.of(tester.element(_key('menu-scroll'))).saves.offered?.mode,
      PlayMode.computer,
    );
    await tester.pumpWidget(const SizedBox());
  });
}
