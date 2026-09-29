import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:honest_chess/data/app_store.dart';
import 'package:honest_chess/main.dart' show appTheme;
import 'package:honest_chess/ui/app_scope.dart';

import 'fake_platform_channel.dart';

export 'fake_platform_channel.dart';

/// What [pumpUnderScope] put in the scope.
class AppHarness {
  const AppHarness(this.store, this.platform);

  final AppStore store;
  final FakePlatformChannel platform;
}

/// Pumps [child] as the home of a `MaterialApp` with the app's theme, under
/// an [AppScope] holding [store] (a fresh memory store by default) and
/// [platform] (a fresh fake by default).
Future<AppHarness> pumpUnderScope(
  WidgetTester tester,
  Widget child, {
  AppStore? store,
  FakePlatformChannel? platform,
  List<NavigatorObserver> observers = const [],
}) async {
  final harness = AppHarness(
    store ?? AppStore.memory(),
    platform ?? FakePlatformChannel(),
  );
  await tester.pumpWidget(
    AppScope(
      store: harness.store,
      platform: harness.platform,
      child: MaterialApp(
        theme: appTheme(),
        navigatorObservers: observers,
        home: child,
      ),
    ),
  );
  return harness;
}
