import 'clock.dart';
import 'game_status.dart';
import 'move.dart';
import 'movegen.dart';
import 'piece.dart';
import 'play.dart' as rules;
import 'position.dart';
import 'strength.dart';

part 'game_json.dart';

/// #63's `status`, reachable inside [Game], whose own `status` field shadows
/// the name.
GameStatus _rulesStatus(List<Position> history) => status(history);

/// Who is playing: the player against the computer, or two players at one
/// device.
sealed class GameMode {
  const GameMode();
}

/// The player plays [playerColour] against the computer at strength [step].
/// [seed] is the 64-bit seed the computer's choices follow, so the same
/// position, step and seed always give the same move. A random colour is
/// resolved before the mode is built.
final class VsComputer extends GameMode {
  const VsComputer({
    required this.playerColour,
    required this.step,
    required this.seed,
  });

  /// A new game against the computer, with a fresh seed from
  /// [newGameSeed]: games vary, and the seed is saved with the game so it
  /// replays exactly.
  factory VsComputer.newGame({
    required Colour playerColour,
    required Strength step,
  }) => VsComputer(playerColour: playerColour, step: step, seed: newGameSeed());

  final Colour playerColour;
  final Strength step;
  final int seed;

  Colour get computerColour => playerColour.opponent;

  @override
  bool operator ==(Object other) =>
      other is VsComputer &&
      other.playerColour == playerColour &&
      other.step == step &&
      other.seed == seed;

  @override
  int get hashCode => Object.hash(playerColour, step, seed);

  @override
  String toString() => 'VsComputer(${playerColour.name}, ${step.name}, $seed)';
}

/// Two players take turns at one device.
final class TwoPlayer extends GameMode {
  const TwoPlayer();

  @override
  bool operator ==(Object other) => other is TwoPlayer;

  @override
  int get hashCode => (TwoPlayer).hashCode;

  @override
  String toString() => 'TwoPlayer()';
}

/// The settings a game is started with, fixed for its whole length.
final class GameOptions {
  const GameOptions({this.takebackAllowed = true});

  final bool takebackAllowed;

  @override
  bool operator ==(Object other) =>
      other is GameOptions && other.takebackAllowed == takebackAllowed;

  @override
  int get hashCode => takebackAllowed.hashCode;

  @override
  String toString() => 'GameOptions(takebackAllowed: $takebackAllowed)';
}

/// The game as it stood after one ply: the [position], the [move] that led
/// there (null for the start), the [clock] after that move's increment, and
/// the [status] the rules gave it.
final class GameSnapshot {
  const GameSnapshot({
    required this.position,
    required this.move,
    required this.clock,
    required this.status,
  });

  final Position position;
  final Move? move;
  final ClockSnapshot clock;
  final GameStatus status;

  @override
  bool operator ==(Object other) =>
      other is GameSnapshot &&
      other.position == position &&
      other.move == move &&
      other.clock == clock &&
      other.status == status;

  @override
  int get hashCode => Object.hash(position, move, clock, status);

  @override
  String toString() => 'GameSnapshot(${position.toFen()}, $move, $status)';
}

/// Why a [Game] refused an action.
enum GameRefusal {
  /// The game is over: no move, resignation or draw offer is possible.
  gameOver,

  /// It is not this side's turn — the piece moved is the opponent's, or,
  /// against the computer, the player acted on the computer's turn (or the
  /// reverse).
  notYourTurn,

  /// The move is not legal in the current position.
  illegalMove,

  /// This game was started with takeback turned off.
  takebackDisabled,

  /// There is no move to take back — none at all, or against the computer
  /// only the computer's opening move.
  nothingToTakeBack,

  /// A draw by agreement needs each side to have moved at least once
  /// (FIDE 5.2.3).
  drawTooEarly,

  /// The computer never resigns.
  computerNeverResigns,
}

/// A [Game] action that the rules or the game's settings refuse.
final class GameActionError implements Exception {
  const GameActionError(this.reason, this.message);

  final GameRefusal reason;
  final String message;

  @override
  String toString() => 'GameActionError(${reason.name}): $message';
}

/// One game of chess: its mode, settings, the snapshot after every ply, the
/// clock and the result.
///
/// Immutable by API: every action returns a new [Game], so a game kept
/// aside is a takeback point or a save that nothing else can change. Time is
/// read from the injected [TimeSource] at the moment of each action.
///
/// Every action that can end the game — [play], [resign], [agreeDraw] —
/// first checks the clock: if a flag has already fallen, the action returns
/// the game ended on time (see [flag]) instead of taking effect.
final class Game {
  const Game._({
    required this.mode,
    required this.options,
    required this.history,
    required this.clock,
    required this.status,
    required this._time,
  });

  /// A new game in [mode] under [timeControl], from the starting position or
  /// from [fen]. [time] defaults to [monotonicMillis]; tests pass a fake.
  ///
  /// A [fen] that is already mate, stalemate or a dead position starts a
  /// game that is already over. Throws a [FormatException] for a malformed
  /// [fen] (see `parseFen`).
  factory Game.start(
    GameMode mode,
    TimeControl timeControl, {
    GameOptions options = const GameOptions(),
    String? fen,
    TimeSource? time,
  }) {
    final clockTime = time ?? monotonicMillis();
    final position = fen == null ? Position.initial() : Position.fromFen(fen);
    final clock = ChessClock(timeControl);
    final start = GameSnapshot(
      position: position,
      move: null,
      clock: clock.snapshot(clockTime()),
      status: _rulesStatus([position]),
    );
    return Game._(
      mode: mode,
      options: options,
      history: List.unmodifiable([start]),
      clock: clock,
      status: start.status,
      time: clockTime,
    );
  }

  /// The game saved in [json] by [toJson], rebuilt by replaying its moves
  /// from its starting FEN — a stored position is never trusted — and then
  /// applying and checking its clocks and result. A clock that was running
  /// when saved comes back paused, as after a takeback. [time] is as for
  /// [Game.start].
  ///
  /// Throws a [GameLoadError], and loads nothing, for a missing, unknown or
  /// newer `version`, a missing or mistyped field, a FEN that does not
  /// parse, an illegal move, moves after the game ended, a result or clock
  /// the replay contradicts. Unknown fields are ignored.
  factory Game.fromJson(Map<String, Object?> json, {TimeSource? time}) =>
      _gameFromJson(json, time);

  final GameMode mode;
  final GameOptions options;

  /// The game after every ply; index 0 is the start, the last is now.
  final List<GameSnapshot> history;

  /// The live clock. Read it with the current time, e.g. [remaining].
  final ChessClock clock;

  /// The result: [Ongoing], or a [Win] or [Draw] with its reason. Differs
  /// from the last snapshot's status only when the game ended without a
  /// move — resignation, agreement or a flag.
  final GameStatus status;

  final TimeSource _time;

  Position get position => history.last.position;

  /// The moves played, in order.
  List<Move> get moves => [for (final s in history.skip(1)) s.move!];

  Colour get sideToMove => position.sideToMove;

  bool get isOver => status.isOver;

  /// This game as version-[gameJsonVersion] JSON data, keys in a fixed
  /// order, with the clocks as they read now — see [Game.fromJson].
  Map<String, Object?> toJson() => _gameToJson(this);

  /// [side]'s remaining milliseconds now; null in an untimed game.
  int? remaining(Colour side) => clock.remaining(side, _time());

  Game _copy({
    List<GameSnapshot>? history,
    ChessClock? clock,
    GameStatus? status,
  }) => Game._(
    mode: mode,
    options: options,
    history: history ?? this.history,
    clock: clock ?? this.clock,
    status: status ?? this.status,
    time: _time,
  );

  /// The side the move by the computer (when [byComputer]) or by a player
  /// must belong to, or null when either side may act.
  Colour? _actor(bool byComputer) => switch (mode) {
    VsComputer(:final playerColour, :final computerColour) =>
      byComputer ? computerColour : playerColour,
    TwoPlayer() => null,
  };

  /// This game ended on time at [now] if a flag has fallen, else null.
  Game? _flagged(int now) {
    if (isOver) return null;
    final side = clock.flaggedSide(now);
    if (side == null) return null;
    return _copy(clock: clock.end(now), status: flagResult(position, side));
  }

  /// Ends the game if a flag has fallen by now (FIDE 6.9): a win for the
  /// opponent, or a draw when the opponent could not mate. Otherwise, and on
  /// a game already over, returns this game unchanged.
  Game flag() => _flagged(_time()) ?? this;

  void _refuseIfOver() {
    if (isOver) {
      throw GameActionError(
        GameRefusal.gameOver,
        'game: the game is over ($status)',
      );
    }
  }

  /// Plays [move] for the side to move — the computer's side when
  /// [byComputer] — and returns the game after it: the clock stops for the
  /// mover (with its increment) and starts for the opponent, and the rules'
  /// [status] over the whole position history decides whether it ended.
  ///
  /// A paused clock (after a takeback, say) resumes at the moment of the
  /// move, so the pause is not charged to the mover.
  ///
  /// Throws a [GameActionError]: [GameRefusal.gameOver] once the game is
  /// over; [GameRefusal.notYourTurn] when the moved piece is not the side
  /// to move's, or against the computer when that side is not the actor's;
  /// [GameRefusal.illegalMove] for anything else not in `legalMoves`.
  /// Throws an [ArgumentError] when [byComputer] is set in a two-player
  /// game.
  Game play(Move move, {bool byComputer = false}) {
    if (byComputer && mode is TwoPlayer) {
      throw ArgumentError.value(byComputer, 'byComputer', 'two-player game');
    }
    final now = _time();
    final flagged = _flagged(now);
    if (flagged != null) return flagged;
    _refuseIfOver();

    final mover = sideToMove;
    final actor = _actor(byComputer);
    final piece = position.pieceAt(move.from);
    if ((actor != null && actor != mover) ||
        (piece != null && piece.colour != mover)) {
      throw GameActionError(
        GameRefusal.notYourTurn,
        'game: ${mover.name} is to move',
      );
    }
    if (!legalMoves(position).contains(move)) {
      throw GameActionError(
        GameRefusal.illegalMove,
        'game: $move is not legal in ${position.toFen()}',
      );
    }

    final next = rules.play(position, move);
    var nextClock = switch (clock.phase) {
      ClockPhase.notStarted => clock.start(mover.opponent, now),
      ClockPhase.paused => clock.resume(now).moveCompleted(mover, now),
      _ => clock.moveCompleted(mover, now),
    };
    final nextStatus = _rulesStatus([
      for (final s in history) s.position,
      next,
    ]);
    if (nextStatus.isOver) nextClock = nextClock.end(now);
    final snapshot = GameSnapshot(
      position: next,
      move: move,
      clock: nextClock.snapshot(now),
      status: nextStatus,
    );
    return _copy(
      history: List.unmodifiable([...history, snapshot]),
      clock: nextClock,
      status: nextStatus,
    );
  }

  /// [side] resigns (FIDE 5.1.2): a loss for [side], or a draw
  /// ([GameEndReason.resignationNoMatingMaterial]) when the opponent could
  /// not checkmate by any series of legal moves. Either side may resign at
  /// any time, whoever is to move. No snapshot is added: a takeback
  /// re-opens the game where it stood.
  ///
  /// Throws a [GameActionError]: [GameRefusal.gameOver] once the game is
  /// over, [GameRefusal.computerNeverResigns] for the computer's side.
  Game resign(Colour side) {
    if (mode case VsComputer(:final computerColour)
        when side == computerColour) {
      throw const GameActionError(
        GameRefusal.computerNeverResigns,
        'game: the computer never resigns',
      );
    }
    final now = _time();
    final flagged = _flagged(now);
    if (flagged != null) return flagged;
    _refuseIfOver();
    final result = canMate(position, side.opponent)
        ? Win(side.opponent, GameEndReason.resignation)
        : const Draw(GameEndReason.resignationNoMatingMaterial);
    return _copy(clock: clock.end(now), status: result);
  }

  /// Whether each side has made at least one move in this game.
  bool get _bothHaveMoved {
    var white = false, black = false;
    for (var i = 1; i < history.length; i++) {
      if (history[i - 1].position.sideToMove == Colour.white) {
        white = true;
      } else {
        black = true;
      }
      if (white && black) return true;
    }
    return false;
  }

  /// Whether [agreeDraw] would be accepted now.
  bool get canAgreeDraw => !isOver && _bothHaveMoved;

  /// Both sides agree a draw (FIDE 5.2.3). The one call records the
  /// agreement; gathering it — two taps, or the computer's answer — is the
  /// caller's. No snapshot is added.
  ///
  /// Throws a [GameActionError]: [GameRefusal.gameOver] once the game is
  /// over, [GameRefusal.drawTooEarly] until each side has moved at least
  /// once in this game.
  Game agreeDraw() {
    final now = _time();
    final flagged = _flagged(now);
    if (flagged != null) return flagged;
    _refuseIfOver();
    if (!_bothHaveMoved) {
      throw const GameActionError(
        GameRefusal.drawTooEarly,
        'game: a draw needs a move from each side first',
      );
    }
    return _copy(
      clock: clock.end(now),
      status: const Draw(GameEndReason.agreement),
    );
  }

  /// Whether the game ended without a move (resignation, agreement, flag),
  /// so a takeback only re-opens it.
  bool get _endedOffTheBoard => isOver && !history.last.status.isOver;

  /// How many plies [takeBack] would undo: one in two-player, or back to
  /// the player's own turn against the computer; 0 when there is nothing
  /// to take back.
  int get _pliesToUndo {
    final plies = history.length - 1;
    if (plies == 0) return 0;
    return switch (mode) {
      TwoPlayer() => 1,
      VsComputer(:final playerColour) =>
        history[plies - 1].position.sideToMove == playerColour
            ? 1
            : (plies >= 2 ? 2 : 0),
    };
  }

  /// Whether [takeBack] would be accepted now.
  bool get canTakeBack =>
      options.takebackAllowed && (_endedOffTheBoard || _pliesToUndo > 0);

  /// Takes back the last move — against the computer, back to the player's
  /// own turn, undoing the computer's reply too. The position, the history
  /// the repetition count reads, and the clocks as they stood then all come
  /// back exactly; the clock comes back paused. A game ended by a move is
  /// re-opened; one ended without a move (resignation, agreement, flag) is
  /// only re-opened, with the clock as at its last move.
  ///
  /// Throws a [GameActionError]: [GameRefusal.takebackDisabled] when the
  /// game's options turn takeback off, [GameRefusal.nothingToTakeBack] when
  /// there is no move to undo.
  Game takeBack() {
    if (!options.takebackAllowed) {
      throw const GameActionError(
        GameRefusal.takebackDisabled,
        'game: takeback is turned off for this game',
      );
    }
    final now = _time();
    if (_endedOffTheBoard) {
      final last = history.last;
      return _copy(
        clock: ChessClock.restore(last.clock, now),
        status: last.status,
      );
    }
    final undo = _pliesToUndo;
    if (undo == 0) {
      throw const GameActionError(
        GameRefusal.nothingToTakeBack,
        'game: there is no move to take back',
      );
    }
    final kept = history.sublist(0, history.length - undo);
    return _copy(
      history: List.unmodifiable(kept),
      clock: ChessClock.restore(kept.last.clock, now),
      status: kept.last.status,
    );
  }

  /// Stops both clocks (the app went to the background, say). A game not
  /// running a clock is returned unchanged.
  Game pause() => _copy(clock: clock.pause(_time()));

  /// Restarts the clock of the side to move after [pause] or a takeback.
  Game resume() => _copy(clock: clock.resume(_time()));
}
