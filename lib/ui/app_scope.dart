import 'dart:math';

import 'package:flutter/widgets.dart';

import '../data/app_store.dart';
import '../data/game_saves.dart';
import '../data/settings_store.dart';
import '../data/stats.dart';
import '../platform/platform_channel.dart';
import 'game/game_controller.dart';
import 'navigation.dart';

/// What the whole app shares, above the `MaterialApp` so every route, dialog
/// and overlay sees it: the store and the platform bridge (#80), the game
/// controller and the saved games (#81), the statistics (#82) and the
/// settings (#83), the navigating flag and the random source for
/// Random's colour (#85). Later stories add their own fields. The root creates each object once, and live
/// changes reach widgets through those objects' own listenables.
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.store,
    required this.platform,
    required this.controller,
    required this.saves,
    required this.stats,
    required this.settings,
    required this.navigation,
    required this.random,
    required super.child,
  });

  final AppStore store;
  final PlatformChannel platform;

  /// The one game controller: the board shows its game, and it outlives
  /// every screen.
  final GameController controller;

  /// The two saved games, kept current from [controller]'s events.
  final GameSaves saves;

  /// The statistics, recorded from [controller]'s games (#82).
  final StatsRecorder stats;

  /// The board options and the setup screens' last choices (#83).
  final SettingsStore settings;

  /// The navigating flag, registered as the app's navigator observer:
  /// forward buttons run through it (#85).
  final NavigationGuard navigation;

  /// Draws Random's colour when a game starts; tests pass a scripted one.
  final Random random;

  /// The nearest scope. It does not register a dependency, so it works in
  /// `initState` and callbacks; there is no `maybeOf`, because a widget
  /// outside the scope is a wiring mistake.
  static AppScope of(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<AppScope>();
    if (scope == null) {
      throw FlutterError(
        'AppScope.of() was called with a context that has no AppScope '
        'above it.',
      );
    }
    return scope;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      !identical(store, oldWidget.store) ||
      !identical(platform, oldWidget.platform) ||
      !identical(controller, oldWidget.controller) ||
      !identical(saves, oldWidget.saves) ||
      !identical(stats, oldWidget.stats) ||
      !identical(settings, oldWidget.settings) ||
      !identical(navigation, oldWidget.navigation) ||
      !identical(random, oldWidget.random);
}
