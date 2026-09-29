/// The feedback hub (#96): the controller's [GameEvent]s reduced to at most
/// one sound each, played while Sound effects is on and the app is in the
/// foreground. Every setting is checked here, in one place, so the
/// computer's moves get the same treatment as yours (owner, round one).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/game_event.dart';
import '../ui/board/board_options.dart';
import '../ui/game/result_text.dart';
import 'clips.dart';
import 'sound_player.dart';
import 'sound_priority.dart';

/// The one clip [event] plays, or null. A move plays by [clipFor]; an end
/// with no move of its own (resignation, a flag, an agreed draw) plays
/// [Clip.end]; the end that follows a game-ending move has already been
/// heard with it. Everything else — takeback, a new game, restart, a pause,
/// a restore, an abandoned game — plays nothing.
Clip? clipForEvent(GameEvent event) => switch (event) {
  GameMoved(:final game) => clipFor(game.history.last.move!, game),
  GameEnded(:final game) => endedByMove(game) ? null : Clip.end,
  GameStarted() ||
  GameTookBack() ||
  GamePaused() ||
  GameResumed() ||
  GameRestored() ||
  GameAbandoned() => null,
};

/// Plays each event's clip through [player] while [board]'s `sfx` is on and
/// [foreground] is true.
class GameFeedback {
  GameFeedback({
    required Stream<GameEvent> events,
    required this.board,
    required this.foreground,
    required this.player,
  }) {
    _events = events.listen(_on);
  }

  final ValueListenable<BoardOptions> board;
  final ValueListenable<bool> foreground;
  final SoundPlayer player;
  late final StreamSubscription<GameEvent> _events;

  void _on(GameEvent event) {
    if (!board.value.sfx || !foreground.value) return;
    final clip = clipForEvent(event);
    if (clip != null) player.play(clip);
  }

  void dispose() => unawaited(_events.cancel());
}
