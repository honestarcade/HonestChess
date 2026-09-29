import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:honest_chess/data/app_store.dart';
import 'package:honest_chess/data/play_mode.dart';
import 'package:honest_chess/engine/engine.dart';
import 'package:honest_chess/feedback/clips.dart';
import 'package:honest_chess/main.dart';
import 'package:honest_chess/ui/app_scope.dart';
import 'package:honest_chess/ui/board/board_options.dart';
import 'package:honest_chess/ui/board/board_view.dart';
import 'package:honest_chess/ui/game/computer_turns.dart';
import 'package:honest_chess/ui/game/game_screen.dart';
import 'package:honest_chess/ui/screens/menu_screen.dart';
import 'package:honest_chess/ui/theme/palette.dart';

import 'support/app_harness.dart';
import 'ui/game/fake_computer.dart';
import 'ui/game/pause_overlay_test.dart' show comeBack, leave;
import 'ui/game/player_panel_test.dart' show text;

/// Pumps the app on [store] past its splash, on a 390 × 844 phone.
Future<HonestChessAppState> _launch(
  WidgetTester tester,
  AppStore store, {
  FakeComputers? fakes,
  int? seedOverride,
  FakePlatformChannel? platform,
  FakeSoundPlayer? sound,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    HonestChessApp(
      key: UniqueKey(),
      computerFactory: (fakes ?? FakeComputers()).call,
      seedOverride: seedOverride,
      store: store,
      platform: platform ?? FakePlatformChannel(),
      sound: sound ?? FakeSoundPlayer(),
    ),
  );
  // The splash shows while the launch load runs, then the menu fades in,
  // during which the navigating flag ignores taps.
  await pumpUntilFound(tester, find.byKey(const Key('menu-vs-computer')));
  await tester.pumpAndSettle();
  return tester.state<HonestChessAppState>(find.byType(HonestChessApp));
}

/// Taps [key], scrolled into view on a lazily built screen, and waits out
/// the awaited writes and the route transition, which a running clock never
/// lets settle.
Future<void> _tapThrough(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      300,
      scrollable: find.byType(Scrollable).last,
    );
  }
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  for (var i = 0; i < 5; i++) {
    await tester.pump();
  }
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  testWidgets('the app opens on the menu: the wordmark, the kicker, no '
      'Continue on an empty store, and every entry', (tester) async {
    final store = AppStore.memory();
    final platform = FakePlatformChannel();
    await _launch(tester, store, platform: platform);

    expect(
      find.byType(GameScreen, skipOffstage: false),
      findsNothing,
      reason: 'app: no board at launch',
    );
    expect(
      tester
          .widget<RichText>(
            find.descendant(
              of: find.byKey(const Key('menu-wordmark')),
              matching: find.byType(RichText),
            ),
          )
          .text
          .toPlainText(),
      'HonestChess',
      reason: 'app: the wordmark',
    );
    expect(find.text('BY HONEST ARCADE · NO ADS'), findsOneWidget);
    expect(
      find.byKey(const Key('menu-continue')),
      findsNothing,
      reason: 'app: nothing to continue on an empty store',
    );
    for (final key in [
      'menu-vs-computer',
      'menu-two-players',
      'menu-statistics',
      'menu-how-to-play',
      'menu-settings',
      'menu-about-app',
      'menu-about-arcade',
    ]) {
      expect(find.byKey(Key(key)), findsOneWidget, reason: 'app: $key');
    }

    final state = tester.state<HonestChessAppState>(
      find.byType(HonestChessApp),
    );
    expect(
      state.settings.board.value,
      const BoardOptions(),
      reason: 'app: the root holds the board options',
    );

    final scope = AppScope.of(tester.element(find.byType(MenuScreen)));
    expect(
      scope.store,
      same(store),
      reason: 'app: the injected store is the scope\'s',
    );
    expect(
      scope.platform,
      same(platform),
      reason: 'app: the injected platform is the scope\'s',
    );

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, const Color(0xFF05285F));

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.debugShowCheckedModeBanner, isFalse);
    expect(app.title, 'Honest Chess');
    expect(
      app.theme!.textTheme.bodyMedium!.fontFamily,
      'Outfit',
      reason: 'app: Outfit is the app-wide text face',
    );
    // One system-bar style at the root wraps every route, the same value
    // the board set for itself in M3.
    final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
      find.byType(AnnotatedRegion<SystemUiOverlayStyle>).first,
    );
    expect(region.value, appOverlayStyle);
    expect(
      appOverlayStyle,
      SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: const Color(0xFF05285F),
      ),
    );
  });

  testWidgets('menu → vs Computer → Start game: Club, you White, Rapid '
      '10+5 on the seed override; e2-e4 and the computer replies', (
    tester,
  ) async {
    final fakes = FakeComputers();
    final root = await _launch(
      tester,
      AppStore.memory(),
      fakes: fakes,
      seedOverride: 42,
    );
    await _tapThrough(tester, 'menu-vs-computer');
    await _tapThrough(tester, 'csetup-start');

    final board = tester.widget<BoardView>(find.byType(BoardView));
    expect(
      board.position.toFen(),
      'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
      reason: 'app: the play screen starts from the start position',
    );
    expect(board.bottom, Colour.white, reason: 'app: White at the bottom');
    expect(board.options, const BoardOptions(), reason: 'app: design defaults');

    final game = root.controller.game;
    final mode = game.mode as VsComputer;
    expect((mode.step, mode.playerColour), (Strength.club, Colour.white));
    expect(game.clock.control, Timed.rapid);
    expect(
      (fakes.current.strength, fakes.current.seed, mode.seed),
      (Strength.club, 42, 42),
      reason: 'app: the seed override is the game\'s seed',
    );
    expect(fakes.current.requests, isEmpty, reason: 'app: your move first');
    expect(text(tester, 'name-black'), 'Club');
    expect(text(tester, 'sub-white'), contains('YOU · WHITE'));
    expect(text(tester, 'sub-white'), contains('RAPID 10+5'));
    expect(text(tester, 'status-text'), 'WHITE TO MOVE');

    await tester.tap(find.byKey(const Key('cell-e2')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('cell-e4')));
    await tester.pump();
    fakes.current.last.move('e7e5');
    await tester.pump(minThinkTime);
    expect(root.controller.game.moves.map((m) => m.toUci()), [
      'e2e4',
      'e7e5',
    ], reason: 'app: the computer answers');
    // The running clock keeps a ticker alive; leaving stops it.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the root loads the clips once, sounds both sides\' moves, '
      'tracks the foreground and releases the player', (tester) async {
    final fakes = FakeComputers();
    final sound = FakeSoundPlayer();
    final root = await _launch(
      tester,
      AppStore.memory(),
      fakes: fakes,
      sound: sound,
    );
    expect(sound.loads, [clips], reason: 'sound: every clip loads once');
    await _tapThrough(tester, 'menu-vs-computer');
    await _tapThrough(tester, 'csetup-start');
    expect(sound.played, isEmpty, reason: 'sound: a new game is silent');

    await tester.tap(find.byKey(const Key('cell-e2')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('cell-e4')));
    await tester.pump();
    fakes.current.last.move('d7d5');
    await tester.pump(minThinkTime);
    expect(sound.played, [Clip.move, Clip.move]);

    await leave(tester, AppLifecycleState.inactive);
    expect(root.controller.state.paused, isTrue);
    expect(root.foreground.value, isFalse);
    await comeBack(tester);
    expect(root.foreground.value, isTrue);

    await tester.pumpWidget(const SizedBox());
    expect(sound.disposed, isTrue, reason: 'sound: released with the root');
  });

  group('saved games', () {
    testWidgets('leaving saves the paused game; the next launch offers it '
        'on the menu, and Continue opens it paused', (tester) async {
      final store = AppStore.memory();
      final fakes = FakeComputers();
      final first = await _launch(tester, store, fakes: fakes);
      await _tapThrough(tester, 'menu-vs-computer');
      await _tapThrough(tester, 'csetup-start');
      expect(
        store.rawText(StoreDoc.gameComputer),
        isNotNull,
        reason: 'app: the new game is saved at once',
      );
      await tester.tap(find.byKey(const Key('cell-e2')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('cell-e4')));
      await tester.pump();
      fakes.current.last.move('e7e5');
      await tester.pump(minThinkTime);
      final controller = first.controller;
      final seed = (controller.game.mode as VsComputer).seed;

      await leave(tester, AppLifecycleState.hidden);
      expect(controller.state.paused, isTrue, reason: 'app: leaving pauses');
      await first.saves.flush();
      expect(first.saves.load(PlayMode.computer)?.moves, controller.game.moves);
      await tester.pumpWidget(const SizedBox());
      await comeBack(tester);

      final again = FakeComputers();
      final second = await _launch(tester, store, fakes: again);
      expect(
        find.byType(GameScreen, skipOffstage: false),
        findsNothing,
        reason: 'app: the next launch opens on the menu',
      );
      expect(find.byKey(const Key('menu-continue')), findsOneWidget);
      await _tapThrough(tester, 'menu-continue');
      final resumed = second.controller;
      expect(resumed.game.moves.map((m) => m.toUci()), ['e2e4', 'e7e5']);
      expect(resumed.state.paused, isTrue, reason: 'app: restored paused');
      expect(find.byKey(const Key('pause-card')), findsOneWidget);
      expect((resumed.game.mode as VsComputer).seed, seed);
      expect(again.current.seed, seed, reason: 'app: same computer seed');
      await tester.pump(const Duration(seconds: 1));
      expect(
        again.current.requests,
        isEmpty,
        reason: 'app: nothing is asked of the computer while paused',
      );
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a finished game found at launch is counted by the root', (
      tester,
    ) async {
      var game = Game.start(
        const VsComputer(
          playerColour: Colour.black,
          step: Strength.club,
          seed: 4,
        ),
        const Untimed(),
      );
      for (final uci in ['f2f3', 'e7e5', 'g2g4', 'd8h4']) {
        game = game.play(
          Move.fromUci(game.position, uci),
          byComputer: game.sideToMove == Colour.white,
        );
      }
      final store = AppStore.memory()
        ..putRaw(
          StoreDoc.gameComputer,
          jsonEncode({
            'format': 1,
            'data': {
              'game': game.toJson(),
              'recorded': {'id': '0123456789abcdef', 'started': true},
            },
          }),
        );
      final root = await _launch(tester, store);
      await tester.pump();
      await root.saves.flush();
      await root.stats.idle;
      expect(root.stats.isLoaded, isTrue);
      expect(
        (root.stats.document.computer.played, root.stats.document.computer.won),
        (1, 1),
        reason: 'app: the listener is wired before the launch load',
      );
      expect(
        AppScope.of(tester.element(find.byType(MenuScreen))).stats,
        same(root.stats),
      );
      expect(
        find.byKey(const Key('menu-continue')),
        findsNothing,
        reason: 'app: a finished game is never offered',
      );
      await tester.pumpWidget(const SizedBox());
    });
  });

  test(
    'every bundled font licence is registered for the licence page',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      registerFontLicences();
      final entries = await LicenseRegistry.licenses.toList();
      final packages = <String>{for (final e in entries) ...e.packages};
      for (final family in fontLicences.keys) {
        expect(
          packages,
          contains(family),
          reason: 'licences: $family\'s OFL is on the licence page',
        );
      }
      final ofl = entries.where(
        (e) => e.packages.contains('Noto Sans Symbols 2'),
      );
      expect(
        ofl.single.paragraphs.map((p) => p.text).join(' '),
        contains('SIL Open Font License'),
        reason: 'licences: the registered text is the OFL itself',
      );
    },
  );
}
