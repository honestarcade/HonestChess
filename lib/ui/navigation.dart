import 'dart:async';

import 'package:flutter/material.dart';

import 'app_scope.dart';
import 'board/board_options.dart';
import 'game/defaults.dart';
import 'game/game_screen.dart';

/// The board route's name: every board is pushed by [openBoard] under it.
const boardRouteName = 'board';

/// How long a route transition may hold [NavigationGuard.busy] when its
/// animation never reports that it finished.
const navigationFallback = Duration(seconds: 1);

/// The app-wide "navigating" flag. The app root creates one, registers it
/// in `navigatorObservers` and shares it as [AppScope.navigation].
///
/// It is busy while a forward action run through [run] is under way —
/// controller calls and awaited writes included — and while a pushed,
/// replaced or popped route's transition runs, until that animation
/// finishes or [navigationFallback] has passed. Only forward buttons go
/// through [run]; back never waits for it.
class NavigationGuard extends NavigatorObserver {
  bool _acting = false;
  final _holds = <_Hold>{};

  /// Whether a forward tap now would be ignored.
  bool get busy => _acting || _holds.isNotEmpty;

  /// Runs [action] unless the guard is busy, holding it busy until the
  /// action ends, however it ends. Completes with whether it ran.
  Future<bool> run(FutureOr<void> Function() action) async {
    if (busy) return false;
    _acting = true;
    try {
      await action();
    } finally {
      _acting = false;
    }
    return true;
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _hold(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (newRoute != null) _hold(newRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _hold(route);

  void _hold(Route<dynamic> route) {
    final animation = route is TransitionRoute ? route.animation : null;
    if (animation == null || !animation.status.isAnimating) return;
    late final _Hold hold;
    void release() {
      if (!_holds.remove(hold)) return;
      hold.timer.cancel();
      animation.removeStatusListener(hold.status);
    }

    hold = _Hold(
      timer: Timer(navigationFallback, release),
      status: (status) {
        // A hero flight holds a pushed route offstage for a frame, its
        // animation standing in as complete; that is not the end.
        if (route is ModalRoute && route.offstage) return;
        if (!status.isAnimating) release();
      },
    );
    animation.addStatusListener(hold.status);
    _holds.add(hold);
  }
}

final class _Hold {
  _Hold({required this.timer, required this.status});

  final Timer timer;
  final AnimationStatusListener status;
}

/// The board route: the game screen over the scope's controller, drawn with
/// the scope's board options.
Route<void> boardRoute() => MaterialPageRoute<void>(
  settings: const RouteSettings(name: boardRouteName),
  builder: (context) {
    final scope = AppScope.of(context);
    return ValueListenableBuilder<BoardOptions>(
      valueListenable: scope.settings.board,
      builder: (context, options, _) =>
          GameScreen(options: options, controller: scope.controller),
    );
  },
);

/// Starts a new game from [setup] on the scope's controller — the game it
/// replaces is abandoned by the controller's replace stages — and then
/// shows it with [openBoard].
Future<void> startGame(BuildContext context, GameSetup setup) async {
  final navigator = Navigator.of(context);
  final controller = AppScope.of(context).controller;
  if (!await controller.newGame(setup)) return;
  _pushBoard(navigator);
}

/// Shows the controller's game: pushes the board above the first route,
/// removing everything between, so there is never more than one board.
void openBoard(BuildContext context) => _pushBoard(Navigator.of(context));

void _pushBoard(NavigatorState navigator) {
  if (!navigator.mounted) return;
  navigator.pushAndRemoveUntil(boardRoute(), (route) => route.isFirst);
}
