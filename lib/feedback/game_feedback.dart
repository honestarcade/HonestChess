/// The feedback hub (#96): the controller's [GameEvent]s reduced to at most
/// one sound each, played while Sound effects is on, and to a tick for each
/// capture and each refused tap or drop (#97) while Haptics is on — both
/// only while the app is in the foreground. Every setting is checked here,
/// in one place, so the computer's moves get the same treatment as yours
/// (owner, round one).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/game_event.dart';
import '../ui/board/board_options.dart';
import '../ui/game/refusal.dart';
import '../ui/game/result_text.dart';
import 'clips.dart';
import 'haptics.dart';
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

/// Whether [event] ticks: a move that captured, whoever played it, en
/// passant and capturing promotions included. Nothing else does — a quiet
/// move, a takeback, a new game, an end.
bool ticksFor(GameEvent event) => switch (event) {
  GameMoved(:final game) => game.history.last.move!.isCapture,
  GameStarted() ||
  GameTookBack() ||
  GamePaused() ||
  GameResumed() ||
  GameRestored() ||
  GameEnded() ||
  GameAbandoned() => false,
};

/// Plays each event's clip through [player] while [board]'s `sfx` is on, and
/// ticks [haptics] for each capture and each of [refusals] while its
/// `haptics` is on; neither while [foreground] is false.
class GameFeedback {
  GameFeedback({
    required Stream<GameEvent> events,
    required Stream<Refusal> refusals,
    required this.board,
    required this.foreground,
    required this.player,
    required this.haptics,
  }) {
    _events = events.listen(_on);
    _refusals = refusals.listen((_) => _tick());
  }

  final ValueListenable<BoardOptions> board;
  final ValueListenable<bool> foreground;
  final SoundPlayer player;
  final HapticsPort haptics;
  late final StreamSubscription<GameEvent> _events;
  late final StreamSubscription<Refusal> _refusals;

  void _on(GameEvent event) {
    if (!foreground.value) return;
    if (board.value.sfx) {
      final clip = clipForEvent(event);
      if (clip != null) player.play(clip);
    }
    if (ticksFor(event)) _tick();
  }

  void _tick() {
    if (!board.value.haptics || !foreground.value) return;
    unawaited(haptics.tick());
  }

  void dispose() {
    unawaited(_events.cancel());
    unawaited(_refusals.cancel());
  }
}
