import 'package:honest_chess/engine/engine.dart';

/// A change of the controller's game, as its `events` stream delivers it.
///
/// Every event carries an immutable snapshot, so a listener never reads the
/// controller: [game] (for [GameAbandoned], the game being replaced) and an
/// unmodifiable copy of the `recorded` map the controller keeps with it.
sealed class GameEvent {
  const GameEvent(this.game, this.recorded);

  final Game game;
  final Map<String, Object?> recorded;
}

/// A new game was put on the board: New, Restart or Rematch. [restart] is
/// true for Restart and Rematch, which play the same game again, so the
/// spoken start (#102) can say which.
final class GameStarted extends GameEvent {
  const GameStarted(super.game, super.recorded, {this.restart = false});

  final bool restart;
}

/// A move was applied — yours, the computer's, or either player's.
final class GameMoved extends GameEvent {
  const GameMoved(super.game, super.recorded);
}

/// A move was taken back.
final class GameTookBack extends GameEvent {
  const GameTookBack(super.game, super.recorded);
}

/// The clocks were held and the board locked.
final class GamePaused extends GameEvent {
  const GamePaused(super.game, super.recorded);
}

/// Play went on after a pause.
final class GameResumed extends GameEvent {
  const GameResumed(super.game, super.recorded);
}

/// The computer declined your draw offer; the game stays paused, the
/// declined-draw card up, until play resumes.
final class GameDrawDeclined extends GameEvent {
  const GameDrawDeclined(super.game, super.recorded);
}

/// A saved game was put back on the board, paused.
final class GameRestored extends GameEvent {
  const GameRestored(super.game, super.recorded);
}

/// The game ended: by a move, a resignation, an agreed draw or a flag.
final class GameEnded extends GameEvent {
  const GameEnded(super.game, super.recorded);
}

/// An unfinished game is about to be replaced by a new one; [game] is the
/// one being left.
final class GameAbandoned extends GameEvent {
  const GameAbandoned(super.game, super.recorded);
}
