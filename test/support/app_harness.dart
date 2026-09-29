import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:honest_chess/data/app_store.dart';
import 'package:honest_chess/data/game_saves.dart';
import 'package:honest_chess/data/recorded_state.dart';
import 'package:honest_chess/data/settings_store.dart';
import 'package:honest_chess/data/stats.dart';
import 'package:honest_chess/main.dart' show appTheme;
import 'package:honest_chess/engine/engine.dart';
import 'package:honest_chess/ui/app_scope.dart';
import 'package:honest_chess/ui/game/computer_turns.dart';
import 'package:honest_chess/ui/game/defaults.dart';
import 'package:honest_chess/ui/game/game_controller.dart';
import 'package:honest_chess/ui/navigation.dart';

import 'fake_platform_channel.dart';

export 'fake_platform_channel.dart';

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
  );

  final AppStore store;
  final FakePlatformChannel platform;
  final GameController controller;
  final GameSaves saves;
  final StatsRecorder stats;
  final SettingsStore settings;
  final NavigationGuard navigation;
  final Random random;
}

/// Pumps [child] as the home of a `MaterialApp` with the app's theme, under
/// an [AppScope] holding [store] (a fresh memory store by default),
/// [platform] (a fresh fake by default), [controller] (by default an idle
/// one whose computer never moves) and [saves] (by default over the store,
/// attached to the controller, as the root builds them) and [stats] (by
/// default a recorder over the store, with no listener wiring it to the
/// controller, so nothing is recorded) and [settings] (by default on the
/// defaults, not loaded from the store) and [random] (by default a seeded
/// source), with a fresh [NavigationGuard] registered ahead of [observers],
/// as the root registers its own. What the harness
/// builds it also disposes; what the test passes, the test disposes.
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
  final harness = AppHarness(
    theStore,
    platform ?? FakePlatformChannel(),
    theController,
    theSaves,
    theStats,
    theSettings,
    NavigationGuard(),
    random ?? Random(85),
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
      child: MaterialApp(
        theme: appTheme(),
        navigatorObservers: [harness.navigation, ...observers],
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
