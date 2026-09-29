/// The feedback hub (#96): the controller's [GameEvent]s reduced to at most
/// one sound each, played while Sound effects is on, and to a tick for each
/// capture and each refused tap or drop (#97) while Haptics is on — both
/// only while the app is in the foreground — and to a sentence for TalkBack
/// (#102), which the announcer speaks only while a screen reader is on.
/// Every setting is checked here,
/// in one place, so the computer's moves get the same treatment as yours
/// (owner, round one).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../a11y/announcer.dart';
import '../a11y/move_speech.dart';
import '../data/game_event.dart';
import '../engine/engine.dart';
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

/// What TalkBack says for [event]; [previous] is the game of the event
/// before it, which a takeback names its undone move from. Every move is
/// spoken, whoever played it; the result once, at the end, straight after
/// the final move's words; an abandoned game says nothing, the new game's
/// start saying enough.
String? announcementFor(GameEvent event, {Game? previous}) => switch (event) {
  GameMoved(:final game) => moveSpeech(
    game.history.last.move!,
    game.history[game.history.length - 2].position,
    game.position,
  ),
  GameEnded(:final game) => resultSpeech(game),
  GameStarted(:final game, :final restart) => startSpeech(
    game,
    restart: restart,
  ),
  GameTookBack(:final game) => takebackSpeech(game, previous),
  GamePaused() => pausedText,
  GameResumed() => resumedText,
  GameRestored(:final game) => restoreSpeech(game),
  GameAbandoned() => null,
};

/// Plays each event's clip through [player] while [board]'s `sfx` is on, and
/// ticks [haptics] for each capture and each of [refusals] while its
/// `haptics` is on; neither while [foreground] is false. Every event and
/// refusal is also handed to [announcer], whatever the settings say.
class GameFeedback {
  GameFeedback({
    required Stream<GameEvent> events,
    required Stream<Refusal> refusals,
    required this.board,
    required this.foreground,
    required this.player,
    required this.haptics,
    required this.announcer,
  }) {
    _events = events.listen(_on);
    _refusals = refusals.listen(_refused);
  }

  final ValueListenable<BoardOptions> board;
  final ValueListenable<bool> foreground;
  final SoundPlayer player;
  final HapticsPort haptics;
  final Announcer announcer;

  /// The last event's game, for a takeback's words.
  Game? _previous;
  late final StreamSubscription<GameEvent> _events;
  late final StreamSubscription<Refusal> _refusals;

  void _on(GameEvent event) {
    final text = announcementFor(event, previous: _previous);
    _previous = event.game;
    if (text != null) announcer.announce(text);
    if (!foreground.value) return;
    if (board.value.sfx) {
      final clip = clipForEvent(event);
      if (clip != null) player.play(clip);
    }
    if (ticksFor(event)) _tick();
  }

  void _refused(Refusal refusal) {
    announcer.announce(refusalSpeech(refusal.kind));
    _tick();
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
