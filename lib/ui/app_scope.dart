import 'package:flutter/widgets.dart';

import '../data/app_store.dart';
import '../platform/platform_channel.dart';

/// What the whole app shares, above the `MaterialApp` so every route, dialog
/// and overlay sees it: the store and the platform bridge (#80). Later
/// stories add their own fields. The root creates each object once, and live
/// changes reach widgets through those objects' own listenables.
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.store,
    required this.platform,
    required super.child,
  });

  final AppStore store;
  final PlatformChannel platform;

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
      !identical(platform, oldWidget.platform);
}
