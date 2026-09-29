import 'dart:async';

import 'package:flutter/scheduler.dart';

import 'package:honest_chess/engine/engine.dart';

/// The computer as the play screen sees it: #68's [ComputerPlayer] in the
/// app, a scripted fake in widget tests.
abstract interface class ComputerOpponent {
  /// The computer's move in [game] — see [ComputerPlayer.chooseMove], which
  /// reads the game's clock itself for a timed game's deadline.
  Future<MoveResult> chooseMove(Game game);

  /// Whether the computer accepts your draw offer in [game].
  Future<bool> acceptsDraw(Game game);

  /// Cancels the pending request, whose future then completes with
  /// [MoveCancelled] (or a declined draw).
  Future<void> cancel();

  /// Cancels any request and stops the computer for good.
  Future<void> dispose();
}

/// Builds the computer for one game at [strength] with that game's [seed].
typedef ComputerFactory = ComputerOpponent Function(
  Strength strength,
  int seed,
);

/// [ComputerOpponent] over the real [ComputerPlayer]. Its worker isolate is
/// spawned as soon as the game starts, so the computer's first move is not
/// slowed by it.
final class ComputerPlayerOpponent implements ComputerOpponent {
  ComputerPlayerOpponent(Strength strength, int seed)
    : _player = ComputerPlayer(strength, seed) {
    // A worker that fails to start is retried by the first request.
    _player.start().ignore();
  }

  final ComputerPlayer _player;

  @override
  Future<MoveResult> chooseMove(Game game) => _player.chooseMove(game);

  @override
  Future<bool> acceptsDraw(Game game) => _player.acceptsDraw(game);

  @override
  Future<void> cancel() => _player.cancel();

  @override
  Future<void> dispose() => _player.dispose();
}

/// The least time from a request to the computer's move landing, so its
/// reply never arrives in the same frame as your move.
const Duration minThinkTime = Duration(milliseconds: 400);

/// Asks the computer for its move whenever it is its turn, and hands the
/// move back through [play].
///
/// The controller calls [follow] after every change of its game. Any change
/// starts a new turn: a request still pending for the last one is cancelled,
/// and its answer, however late, is dropped — it is checked against the turn
/// and the ply count it was asked for. The computer thinks only while the
/// game goes on, unpaused, with the computer to move.
class ComputerTurns {
  ComputerTurns(this.opponent, {required this.play, required this.changed});

  final ComputerOpponent opponent;

  /// Plays the computer's move in the game last passed to [follow];
  /// returns whether the game took it.
  final bool Function(Move move) play;

  /// [thinking] or [failed] changed outside a [follow] call.
  final void Function() changed;

  Game? _game;
  var _paused = false;

  /// Bumped by every change of game, so an answer can tell it is stale.
  var _turn = 0;
  var _due = false;
  var _failed = false;
  var _retried = false;

  /// Whether a request is waiting for its answer or its [minThinkTime].
  var _pending = false;
  Timer? _floor;
  var _disposed = false;

  /// Whether it is the computer's turn: from the moment it begins, through
  /// the request and its floor — and a failure — until the move lands or
  /// the turn ends.
  bool get thinking => _due;

  /// The computer could not move this turn, even after one retry; [retry]
  /// asks again.
  bool get failed => _failed;

  /// Follows the controller's [game], [paused] or not.
  void follow(Game game, {required bool paused}) {
    if (_disposed || (identical(game, _game) && paused == _paused)) return;
    _game = game;
    _paused = paused;
    _stop();
    _turn++;
    _failed = false;
    _retried = false;
    _due =
        !paused &&
        !game.isOver &&
        game.mode is VsComputer &&
        game.sideToMove == (game.mode as VsComputer).computerColour;
    if (!_due) return;
    final turn = _turn;
    // After the frame that shows your move, so the request never delays it.
    SchedulerBinding.instance
      ..addPostFrameCallback((_) {
        if (turn == _turn && !_disposed) _request();
      })
      ..ensureVisualUpdate();
  }

  /// Asks again after [failed]. Returns whether a request was made.
  bool retry() {
    if (!_failed || _disposed) return false;
    _failed = false;
    _retried = false;
    _request();
    changed();
    return true;
  }

  /// Cancels any request for good.
  void dispose() {
    if (_disposed) return;
    _stop();
    _disposed = true;
    _turn++;
    _due = false;
    opponent.dispose().ignore();
  }

  void _stop() {
    _floor?.cancel();
    _floor = null;
    if (_pending) {
      _pending = false;
      opponent.cancel().ignore();
    }
  }

  void _request() {
    final game = _game!;
    final turn = _turn;
    final ply = game.history.length - 1;
    var floorDone = false;
    var answered = false;
    MoveResult? answer;
    _pending = true;

    void settle() {
      if (!floorDone || !answered) return;
      if (turn != _turn || _disposed) return;
      final current = _game!;
      _pending = false;
      _floor = null;
      if (answer case Moved(:final move, ply: final asked)
          when asked == ply && current.history.length - 1 == ply) {
        // A refused move that still changed the game (a flag had fallen)
        // has started a new turn already.
        if (play(move) || turn != _turn) return;
      }
      // Cancelled by nobody here, or the worker failed: once more, then
      // the chip.
      if (!_retried) {
        _retried = true;
        _request();
        return;
      }
      _failed = true;
      changed();
    }

    _floor = Timer(minThinkTime, () {
      floorDone = true;
      settle();
    });
    Future.sync(() => opponent.chooseMove(game)).then(
      (result) {
        answer = result;
        answered = true;
        settle();
      },
      onError: (Object _) {
        answered = true;
        settle();
      },
    );
  }
}
