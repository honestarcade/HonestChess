import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:honest_chess/data/app_store.dart';
import 'package:honest_chess/data/game_saves.dart';
import 'package:honest_chess/main.dart' show appTheme;
import 'package:honest_chess/ui/app_scope.dart';
import 'package:honest_chess/ui/game/game_controller.dart';

import 'fake_platform_channel.dart';

export 'fake_platform_channel.dart';

/// What [pumpUnderScope] put in the scope.
class AppHarness {
  const AppHarness(this.store, this.platform, this.controller, this.saves);

  final AppStore store;
  final FakePlatformChannel platform;
  final GameController controller;
  final GameSaves saves;
}

/// Pumps [child] as the home of a `MaterialApp` with the app's theme, under
/// an [AppScope] holding [store] (a fresh memory store by default),
/// [platform] (a fresh fake by default), [controller] (by default an idle
/// one whose computer never moves) and [saves] (by default over the store,
/// attached to the controller, as the root builds them). What the harness
/// builds it also disposes; what the test passes, the test disposes.
Future<AppHarness> pumpUnderScope(
  WidgetTester tester,
  Widget child, {
  AppStore? store,
  FakePlatformChannel? platform,
  GameController? controller,
  GameSaves? saves,
  List<NavigatorObserver> observers = const [],
}) async {
  final theStore = store ?? AppStore.memory();
  final theController = controller ?? GameController.idle();
  final theSaves = saves ?? (GameSaves(theStore)..attach(theController.events));
  if (saves == null || controller == null) {
    addTearDown(() async {
      // Nothing may still be listening when they go.
      await tester.pumpWidget(const SizedBox());
      if (saves == null) theSaves.dispose();
      if (controller == null) theController.dispose();
    });
  }
  final harness = AppHarness(
    theStore,
    platform ?? FakePlatformChannel(),
    theController,
    theSaves,
  );
  await tester.pumpWidget(
    AppScope(
      store: harness.store,
      platform: harness.platform,
      controller: harness.controller,
      saves: harness.saves,
      child: MaterialApp(
        theme: appTheme(),
        navigatorObservers: observers,
        home: child,
      ),
    ),
  );
  return harness;
}
