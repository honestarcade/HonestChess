/// The music loop's gate (#96; Honest Solitaire's controller): the loop
/// plays only while Background music is on, a live game is on the board,
/// that game is not paused and the app is in the foreground. It pauses,
/// keeping its place, when any of those stops being true; a new game,
/// restart or rematch starts it from the beginning; turning the setting off
/// stops it. It never plays over another app's audio: the bridge refuses a
/// start then, and a refused start is tried again only at the next change
/// of the gate.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../ui/board/board_options.dart';
import '../ui/game/game_controller.dart';
import '../ui/navigation.dart';
import 'sound_player.dart';

/// Whether the board route is the page on top of the app's navigator. Only
/// page routes count: a dialog or sheet over the board leaves it showing,
/// and the board's own cards are layers of its page, not routes.
class BoardRouteObserver extends NavigatorObserver {
  final _pages = <Route<dynamic>>[];
  final _visible = ValueNotifier<bool>(false);

  ValueListenable<bool> get visible => _visible;

  void _update() {
    final top = _pages.isEmpty ? null : _pages.last;
    _visible.value = top?.settings.name == boardRouteName;
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PageRoute) _pages.add(route);
    _update();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _pages.remove(route);
    _update();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _pages.remove(route);
    _update();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final at = oldRoute == null ? -1 : _pages.indexOf(oldRoute);
    if (at >= 0) _pages.removeAt(at);
    if (newRoute is PageRoute) {
      _pages.insert(at >= 0 ? at : _pages.length, newRoute);
    }
    _update();
  }

  void dispose() => _visible.dispose();
}

class MusicController {
  MusicController({
    required this.controller,
    required this.board,
    required this.boardVisible,
    required this.foreground,
    required this.player,
  }) : _musicOn = board.value.music {
    controller.addListener(_reconcile);
    board.addListener(_reconcile);
    boardVisible.addListener(_reconcile);
    foreground.addListener(_reconcile);
    _reconcile();
  }

  final GameController controller;
  final ValueListenable<BoardOptions> board;
  final ValueListenable<bool> boardVisible;
  final ValueListenable<bool> foreground;
  final SoundPlayer player;
  bool _musicOn;

  /// The statistics id of the game on the board: a different one is a
  /// different game, whose loop starts from the beginning.
  Object? _gameId;
  bool _open = false;
  bool _playing = false;
  Future<void> _chain = Future.value();
  bool _disposed = false;

  /// Whether every condition for the loop holds right now.
  bool get gateOpen =>
      board.value.music &&
      boardVisible.value &&
      foreground.value &&
      !controller.isIdle &&
      !controller.game.isOver &&
      !controller.state.paused;

  /// Serialised, so a pause never overtakes the start before it.
  void _later(Future<void> Function() action) {
    _chain = _chain.then((_) => action()).catchError((Object _) {});
  }

  void _stop() => _later(() async {
    _playing = false;
    await player.stopMusic();
  });

  void _reconcile() {
    if (_disposed) return;
    final id = controller.isIdle ? null : controller.recorded['id'];
    if (id != _gameId) {
      // A new game, restart or rematch; the first game after launch has
      // nothing to rewind.
      if (_gameId != null) {
        _stop();
        _open = false;
      }
      _gameId = id;
    }
    final musicOn = board.value.music;
    if (_musicOn && !musicOn) _stop();
    _musicOn = musicOn;
    final open = gateOpen;
    if (open == _open) return;
    _open = open;
    _later(open ? _start : _pause);
  }

  Future<void> _start() async {
    // The gate closed again before this start's turn came.
    if (_disposed || !_open) return;
    _playing = await player.startMusic();
    // The gate closed while the start was on its way.
    if (_playing && (_disposed || !_open)) await _pause();
  }

  Future<void> _pause() async {
    if (!_playing) return;
    _playing = false;
    await player.pauseMusic();
  }

  /// Everything queued has run, for tests.
  Future<void> settle() => _chain;

  void dispose() {
    _disposed = true;
    if (_playing) unawaited(player.pauseMusic());
    controller.removeListener(_reconcile);
    board.removeListener(_reconcile);
    boardVisible.removeListener(_reconcile);
    foreground.removeListener(_reconcile);
  }
}
