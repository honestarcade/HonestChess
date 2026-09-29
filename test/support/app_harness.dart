import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:honest_chess/a11y/announcer.dart';
import 'package:honest_chess/data/app_store.dart';
import 'package:honest_chess/data/game_saves.dart';
import 'package:honest_chess/data/recorded_state.dart';
import 'package:honest_chess/data/settings_store.dart';
import 'package:honest_chess/data/stats.dart';
import 'package:honest_chess/feedback/music_controller.dart';
import 'package:honest_chess/main.dart' show appTheme;
import 'package:honest_chess/engine/engine.dart';
import 'package:honest_chess/ui/app_builder.dart';
import 'package:honest_chess/ui/app_scope.dart';
import 'package:honest_chess/ui/game/computer_turns.dart';
import 'package:honest_chess/ui/game/defaults.dart';
import 'package:honest_chess/ui/game/game_controller.dart';
import 'package:honest_chess/ui/navigation.dart';

import 'fake_haptics.dart';
import 'fake_platform_channel.dart';
import 'fake_sound_player.dart';

export 'fake_haptics.dart';
export 'fake_platform_channel.dart';
export 'fake_sound_player.dart';

/// What [pumpUnderScope] put in the scope.
class AppHarness {
  const AppHarness(
    this.store,
    this.platform,
    this.controller,
    this.saves,
    this.stats,
    this.settings,
    this.navigation,
    this.random,
    this.sound,
    this.music,
    this.boardRoutes,
    this.foreground,
    this.haptics,
    this.announcer,
  );

  final AppStore store;
  final FakePlatformChannel platform;
  final GameController controller;
  final GameSaves saves;
  final StatsRecorder stats;
  final SettingsStore settings;
  final NavigationGuard navigation;
  final Random random;
  final FakeSoundPlayer sound;
  final MusicController music;
  final BoardRouteObserver boardRoutes;

  /// The music's foreground flag; the harness has no lifecycle listener, so
  /// a test sets it.
  final ValueNotifier<bool> foreground;
  final FakeHaptics haptics;

  /// What the screen reader would have heard.
  final RecordingAnnouncer announcer;
}

/// Pumps [child] as the home of a `MaterialApp` with the app's theme, under
/// an [AppScope] holding [store] (a fresh memory store by default),
/// [platform] (a fresh fake by default), [controller] (by default an idle
/// one whose computer never moves) and [saves] (by default over the store,
/// attached to the controller, as the root builds them) and [stats] (by
/// default a recorder over the store, with no listener wiring it to the
/// controller, so nothing is recorded) and [settings] (by default on the
/// defaults, not loaded from the store) and [random] (by default a seeded
/// source) and [sound], [haptics] and [announcer] (by default recording
/// fakes), with a
/// fresh [NavigationGuard] and a [BoardRouteObserver] registered ahead of
/// [observers], and a [MusicController] over them, as the root registers its
/// own. What the harness builds it also disposes; what the test passes, the
/// test disposes.
Future<AppHarness> pumpUnderScope(
  WidgetTester tester,
  Widget child, {
  AppStore? store,
  FakePlatformChannel? platform,
  GameController? controller,
  GameSaves? saves,
  StatsRecorder? stats,
  SettingsStore? settings,
  Random? random,
  FakeSoundPlayer? sound,
  FakeHaptics? haptics,
  RecordingAnnouncer? announcer,
  List<NavigatorObserver> observers = const [],
}) async {
  final theStore = store ?? AppStore.memory();
  final theController = controller ?? GameController.idle();
  final theSaves = saves ?? (GameSaves(theStore)..attach(theController.events));
  final theStats = stats ?? StatsRecorder(store: theStore);
  final theSettings = settings ?? SettingsStore();
  if (saves == null ||
      controller == null ||
      stats == null ||
      settings == null) {
    addTearDown(() async {
      // Nothing may still be listening when they go.
      await tester.pumpWidget(const SizedBox());
      if (saves == null) theSaves.dispose();
      if (controller == null) theController.dispose();
      if (stats == null) theStats.dispose();
      if (settings == null) theSettings.dispose();
    });
  }
  final theSound = sound ?? FakeSoundPlayer();
  final boardRoutes = BoardRouteObserver();
  final foreground = ValueNotifier<bool>(true);
  final music = MusicController(
    controller: theController,
    board: theSettings.board,
    boardVisible: boardRoutes.visible,
    foreground: foreground,
    player: theSound,
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    music.dispose();
    boardRoutes.dispose();
    foreground.dispose();
  });
  final harness = AppHarness(
    theStore,
    platform ?? FakePlatformChannel(),
    theController,
    theSaves,
    theStats,
    theSettings,
    NavigationGuard(),
    random ?? Random(85),
    theSound,
    music,
    boardRoutes,
    foreground,
    haptics ?? FakeHaptics(),
    announcer ?? RecordingAnnouncer(),
  );
  await tester.pumpWidget(
    AppScope(
      store: harness.store,
      platform: harness.platform,
      controller: harness.controller,
      saves: harness.saves,
      stats: harness.stats,
      settings: harness.settings,
      navigation: harness.navigation,
      random: harness.random,
      sound: harness.sound,
      music: harness.music,
      haptics: harness.haptics,
      announcer: harness.announcer,
      child: MaterialApp(
        theme: appTheme(),
        navigatorObservers: [
          harness.navigation,
          harness.boardRoutes,
          ...observers,
        ],
        builder: appBuilder(harness.settings.board),
        home: child,
      ),
    ),
  );
  return harness;
}

/// The board of a new game from [setup], pushed over a stand-in first
/// route under the harness's scope the way the app shows a board: the
/// controller starts the game, then `navigation.dart`'s board route is
/// pushed. The harness's [SettingsStore] is wired to the controller's board
/// options as the app root wires its own. [computerFactory] builds the
/// computer (by default none, so it never moves).
Future<AppHarness> pumpBoard(
  WidgetTester tester, {
  GameSetup setup = vsComputerDefault,
  ComputerFactory? computerFactory,
  AppStore? store,
  FakePlatformChannel? platform,
}) async {
  final controller = GameController.idle(computerFactory: computerFactory);
  final settings = SettingsStore();
  void boardChanged() => controller.options = settings.board.value;
  settings.board.addListener(boardChanged);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    settings.board.removeListener(boardChanged);
    settings.dispose();
    controller.dispose();
  });
  final harness = await pumpUnderScope(
    tester,
    const Scaffold(body: SizedBox.expand(key: Key('stand-in'))),
    store: store,
    platform: platform,
    controller: controller,
    settings: settings,
  );
  await controller.newGame(setup);
  openBoard(tester.element(find.byKey(const Key('stand-in'))));
  // A running clock never lets the transition settle; the route's own
  // duration does.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  return harness;
}

/// Writes [game] to [store] as the app saves it — through [GameSaves]' own
/// save path, so its document and `meta.lastPlayed` are the real format —
/// with a fresh `recorded` state unless [recorded] is given.
Future<void> seedSavedGame(
  AppStore store,
  Game game, {
  Map<String, Object?>? recorded,
}) async {
  final saves = GameSaves(store);
  await saves.save(game, recorded ?? RecordedState.fresh().toJson());
  await saves.flush();
  saves.dispose();
}

/// Pumps in [step]s until [finder] matches, failing with the finder named
/// once [timeout] of test time has passed without it.
Future<void> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 5),
  Duration step = const Duration(milliseconds: 50),
}) async {
  var waited = Duration.zero;
  while (finder.evaluate().isEmpty) {
    if (waited >= timeout) {
      fail('pumpUntilFound: $finder not found within $timeout');
    }
    await tester.pump(step);
    waited += step;
  }
}
