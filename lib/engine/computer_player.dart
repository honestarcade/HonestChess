/// The computer opponent, thinking on a background isolate so the app never
/// freezes (CLAUDE.md invariant 4): within its step's node budget, within a
/// share of its own clock in a timed game, and cancellable at any moment.
library;

import 'dart:async';
import 'dart:isolate';
import 'dart:math';

import 'clock.dart';
import 'game.dart';
import 'move.dart';
import 'position.dart';
import 'search.dart';
import 'strength.dart';
import 'transposition.dart';

/// What [ComputerPlayer.chooseMove] answers.
sealed class MoveResult {
  const MoveResult();
}

/// The computer's [move] for the game as it stood at [ply] (the number of
/// moves played), found by a search that finished [depth] plies in [nodes]
/// nodes. The move belongs to that position only.
final class Moved extends MoveResult {
  const Moved(
    this.move, {
    required this.ply,
    required this.depth,
    required this.nodes,
    this.debugSearchIsolate,
  });

  final Move move;
  final int ply;
  final int depth;
  final int nodes;

  /// In debug builds, the control port of the isolate the search ran in, so
  /// a test can tell it from the caller's; null in release builds.
  final SendPort? debugSearchIsolate;

  @override
  String toString() => 'Moved($move, ply: $ply, depth: $depth, nodes: $nodes)';
}

/// The request was cancelled — by [ComputerPlayer.cancel], a newer request,
/// or [ComputerPlayer.dispose] — or its answer no longer fits the game.
/// There is no move to play.
final class MoveCancelled extends MoveResult {
  const MoveCancelled();

  @override
  bool operator ==(Object other) => other is MoveCancelled;

  @override
  int get hashCode => (MoveCancelled).hashCode;

  @override
  String toString() => 'MoveCancelled()';
}

/// The worker failed to answer: it threw, crashed, or overran its deadline
/// by [overrunKillMs]. The worker is replaced on the next request.
final class ComputerError implements Exception {
  const ComputerError(this.message);

  final String message;

  @override
  String toString() => 'ComputerError: $message';
}

/// However early in the game, a timed search plans as if at least this many
/// moves remain.
const int minMovesToGo = 20;

/// The move number by which [minMovesToGo] takes over: at move `n` the
/// computer plans for `max(minMovesToGo, movesToGoHorizon - n)` moves.
const int movesToGoHorizon = 40;

/// The least of the clock the computer keeps back, in milliseconds, for
/// the messages to and from the worker and the search's last iteration.
const int minClockMarginMs = 50;

/// The share of its remaining clock, in percent, the computer keeps back
/// when that is more than [minClockMarginMs].
const int clockMarginPercent = 2;

/// How far past its deadline a worker may run, in milliseconds, before it
/// is killed and the request fails with a [ComputerError].
const int overrunKillMs = 500;

/// The most milliseconds a search may take with [remainingMs] on the
/// computer's clock, [incrementMs] added per move, at move [fullmoveNumber]:
/// its share of the clock plus half the increment, never more than the
/// clock less a margin, and 0 — the search's first iteration only — once
/// the clock is at or below that margin.
int clockCapMs({
  required int remainingMs,
  required int incrementMs,
  required int fullmoveNumber,
}) {
  final margin = max(minClockMarginMs, remainingMs * clockMarginPercent ~/ 100);
  if (remainingMs <= margin) return 0;
  final movesToGo = max(minMovesToGo, movesToGoHorizon - fullmoveNumber);
  final share = remainingMs ~/ movesToGo + incrementMs ~/ 2;
  return min(share, remainingMs - margin);
}

/// [clockCapMs] for the side to move in [game] as its clock reads now, or
/// null in an untimed game.
int? gameClockCapMs(Game game) {
  final control = game.clock.control;
  if (control is! Timed) return null;
  return clockCapMs(
    remainingMs: game.remaining(game.sideToMove)!,
    incrementMs: control.incrementMs,
    fullmoveNumber: game.position.fullmoveNumber,
  );
}

/// The computer at one [strength] with one game's [seed], thinking on a
/// worker isolate of its own.
///
/// The worker is spawned on the first request (or by [start]) and kept, so
/// its transposition table's memory is allocated once. Only one request is
/// pending at a time: a new one cancels the last. Cancelling kills the
/// worker at once — the search is synchronous and cannot read a message
/// mid-search — and the next request spawns a fresh one. Call [dispose]
/// when the game is left.
final class ComputerPlayer {
  /// [now] measures how long the worker took to start, which a timed
  /// request's deadline is shortened by; it defaults to [monotonicMillis].
  /// [nodeBudget], for tests, replaces the step's node budget.
  ComputerPlayer(this.strength, this.seed, {TimeSource? now, this.nodeBudget})
    : _now = now ?? monotonicMillis();

  final Strength strength;
  final int seed;
  final int? nodeBudget;
  final TimeSource _now;

  Future<_Worker>? _starting;

  /// The worker [_starting] resolved to, once it has.
  _Worker? _live;
  _Pending? _pending;
  var _nextId = 0;
  var _disposed = false;
  final _thinking = StreamController<bool>.broadcast(sync: true);

  /// Whether a request is pending: from [chooseMove] (or [acceptsDraw])
  /// until its answer or cancellation arrives.
  bool get isThinking => _pending != null;

  /// Each change of [isThinking].
  Stream<bool> get thinking => _thinking.stream;

  /// Spawns the worker now rather than on the first request, so the first
  /// move is not slowed by it.
  Future<void> start() {
    _checkNotDisposed();
    return _worker();
  }

  /// The computer's move in [game], for its side to move, searched on the
  /// worker isolate. The same position, step and seed give the same move;
  /// in a timed game the search may stop early, at [gameClockCapMs] from
  /// this call, so the computer never loses on time.
  ///
  /// Completes with [MoveCancelled] if cancelled first, or with a
  /// [ComputerError] when the worker fails. Throws a [StateError] when the
  /// game is over, it is not the computer's turn, or after [dispose]; an
  /// [ArgumentError] when [game] is against the computer at another step or
  /// seed.
  Future<MoveResult> chooseMove(Game game) {
    _checkNotDisposed();
    if (game.isOver) throw StateError('computer: the game is over');
    final mode = game.mode;
    if (mode is VsComputer) {
      if (mode.step != strength || mode.seed != seed) {
        throw ArgumentError.value(mode, 'game', 'is not $strength, $seed');
      }
      if (game.sideToMove != mode.computerColour) {
        throw StateError('computer: it is the player\'s turn');
      }
    }
    final asked = _now();
    final position = game.position;
    final ply = game.history.length - 1;
    final history = [
      for (var i = 0; i < ply; i++) game.history[i].position.key,
    ];
    final cap = gameClockCapMs(game);
    return _request(
      (id) => [
        _moveRequest,
        id,
        position.toFen(),
        history,
        strength.index,
        seed,
        if (cap == null) null else max(0, cap - (_now() - asked)),
        nodeBudget,
      ],
      deadlineMs: cap,
    ).then((reply) {
      if (reply == null) return const MoveCancelled();
      final Move move;
      try {
        move = Move.fromUci(position, reply[2]! as String);
      } on FormatException {
        return const MoveCancelled();
      }
      return Moved(
        move,
        ply: ply,
        depth: reply[3]! as int,
        nodes: reply[4]! as int,
        debugSearchIsolate: reply[5] as SendPort?,
      );
    });
  }

  /// Whether the computer accepts the player's draw offer in [game] (see
  /// the engine's `acceptsDraw`), answered on the worker. A question
  /// cancelled before its answer is declined.
  ///
  /// Throws as `acceptsDraw` does, and a [StateError] after [dispose];
  /// completes with a [ComputerError] when the worker fails.
  Future<bool> acceptsDraw(Game game) {
    _checkNotDisposed();
    if (game.mode is! VsComputer) {
      throw ArgumentError.value(
        game.mode,
        'game',
        'is not against the computer',
      );
    }
    if (!game.canAgreeDraw) {
      throw StateError('computer: a draw cannot be offered now');
    }
    final json = game.toJson();
    return _request((id) => [_drawRequest, id, json])
        .then((reply) => reply != null && reply[2]! as bool);
  }

  /// Cancels the pending request, if any: its future completes at once
  /// ([MoveCancelled], or a declined draw) and a worker already searching is
  /// killed. The returned future completes once that worker has stopped.
  Future<void> cancel() => _cancel(notify: true);

  /// Starts a new game: cancels the pending request and clears the worker's
  /// transposition table.
  Future<void> newGame() async {
    await cancel();
    final live = _live;
    if (live != null) _send(live, const [_clearRequest, -1]);
  }

  /// Cancels the pending request and stops the worker for good.
  Future<void> dispose() async {
    if (_disposed) return;
    await cancel();
    _disposed = true;
    await _thinking.close();
    final starting = _starting;
    if (starting == null) return;
    try {
      await _discard(await starting);
    } on Object {
      // It never started, so there is nothing to stop.
    }
  }

  void _checkNotDisposed() {
    if (_disposed) throw StateError('computer: disposed');
  }

  Future<_Worker> _worker() {
    if (_starting case final starting?) return starting;
    final starting = _Worker.spawn(_onReply, _onFailure);
    _starting = starting;
    starting.then(
      (worker) {
        if (identical(_starting, starting)) _live = worker;
      },
      // A spawn that failed is retried by the next request.
      onError: (Object _) {
        if (identical(_starting, starting)) _starting = null;
      },
    );
    return starting;
  }

  Future<List<Object?>?> _request(
    List<Object?> Function(int id) build, {
    int? deadlineMs,
  }) {
    final replaced = _pending;
    if (replaced != null) _cancel(notify: false);
    final pending = _Pending(_nextId++);
    _pending = pending;
    if (replaced == null) _thinking.add(true);
    _worker().then((worker) {
      if (!identical(_pending, pending)) return;
      pending.worker = worker;
      _send(worker, build(pending.id));
      if (deadlineMs != null) {
        pending.watchdog = Timer(
          Duration(milliseconds: deadlineMs + overrunKillMs),
          () => _fail(
            pending,
            ComputerError('the search ran $overrunKillMs ms past its deadline'),
          ),
        );
      }
    }, onError: (Object error) => _fail(pending, ComputerError('$error')));
    return pending.completer.future;
  }

  void _send(_Worker worker, List<Object?> message) {
    worker.port.send(message);
  }

  void _onReply(Object? reply) {
    final pending = _pending;
    if (reply is! List<Object?> || pending == null || reply[1] != pending.id) {
      return;
    }
    if (reply[0] == _failedReply) {
      _fail(pending, ComputerError(reply[2]! as String));
    } else {
      _finish(pending);
      pending.completer.complete(reply);
    }
  }

  void _onFailure(_Worker worker, Object? error) {
    final pending = _pending;
    if (pending != null && identical(pending.worker, worker)) {
      _fail(pending, ComputerError('the worker stopped: $error'));
    } else {
      _discard(worker);
    }
  }

  /// Fails [pending] with [error] and replaces its worker, which may be in
  /// any state.
  void _fail(_Pending pending, ComputerError error) {
    if (!identical(_pending, pending)) return;
    _finish(pending);
    final worker = pending.worker;
    if (worker != null) _discard(worker);
    pending.completer.completeError(error);
  }

  /// Kills [worker]; the next request spawns a new one.
  Future<void> _discard(_Worker worker) {
    if (identical(_live, worker)) {
      _live = null;
      _starting = null;
    }
    return worker.kill();
  }

  void _finish(_Pending pending) {
    _pending = null;
    pending.watchdog?.cancel();
    _thinking.add(false);
  }

  Future<void> _cancel({required bool notify}) {
    final pending = _pending;
    if (pending == null) return Future.value();
    _pending = null;
    pending.watchdog?.cancel();
    if (notify) _thinking.add(false);
    pending.completer.complete(null);
    final worker = pending.worker;
    // A request not yet sent leaves its worker idle, and it is kept.
    if (worker == null) return Future.value();
    return _discard(worker);
  }
}

final class _Pending {
  _Pending(this.id);

  final int id;
  final completer = Completer<List<Object?>?>();

  /// The worker the request was sent to; null until it is sent.
  _Worker? worker;
  Timer? watchdog;
}

/// One worker isolate and the ports that talk to it.
final class _Worker {
  _Worker._(this._isolate, this.port, this._replies, this._errors);

  final Isolate _isolate;
  final SendPort port;
  final ReceivePort _replies;
  final ReceivePort _errors;
  final _exited = Completer<void>();
  var _killed = false;

  static Future<_Worker> spawn(
    void Function(Object? reply) onReply,
    void Function(_Worker worker, Object? error) onFailure,
  ) async {
    final replies = ReceivePort();
    final errors = ReceivePort();
    final exits = ReceivePort();
    final ready = Completer<SendPort>();
    replies.listen((message) {
      if (!ready.isCompleted) {
        ready.complete(message! as SendPort);
      } else {
        onReply(message);
      }
    });
    _Worker? started;
    exits.listen((_) {
      exits.close();
      final worker = started;
      if (worker == null) {
        if (!ready.isCompleted) {
          ready.completeError(const ComputerError('the worker did not start'));
        }
        return;
      }
      worker._exited.complete();
      if (!worker._killed) onFailure(worker, 'exited');
    });
    try {
      final isolate = await Isolate.spawn(
        _workerMain,
        replies.sendPort,
        debugName: 'computer',
        onError: errors.sendPort,
        onExit: exits.sendPort,
      );
      final worker = _Worker._(isolate, await ready.future, replies, errors);
      started = worker;
      errors.listen((error) {
        if (!worker._killed) onFailure(worker, error);
      });
      return worker;
    } on Object {
      replies.close();
      errors.close();
      exits.close();
      rethrow;
    }
  }

  /// Kills the isolate mid-search, and closes its ports so nothing it sent
  /// is delivered; completes once it has exited.
  Future<void> kill() {
    if (!_killed) {
      _killed = true;
      _replies.close();
      _errors.close();
      _isolate.kill(priority: Isolate.immediate);
    }
    return _exited.future;
  }
}

// Messages are lists of primitives: [kind, request id, ...].
const _moveRequest = 0; // FEN, history keys, step, seed, deadline ms?, nodes?
const _drawRequest = 1; // the game's JSON
const _clearRequest = 2; // no reply
const _movedReply = 3; // UCI, depth, nodes, isolate port (debug builds)
const _drawReply = 4; // accepted
const _failedReply = 5; // error text

void _workerMain(SendPort replies) {
  final requests = ReceivePort();
  replies.send(requests.sendPort);
  requests.listen((message) {
    final reply = _serve(message! as List<Object?>);
    if (reply != null) replies.send(reply);
  });
}

/// The isolate's transposition table, allocated on its first request.
TranspositionTable? _table;

/// Answers one request, in whichever isolate calls it.
List<Object?>? _serve(List<Object?> request) {
  final id = request[1]! as int;
  try {
    final table = _table ??= TranspositionTable();
    switch (request[0]) {
      case _clearRequest:
        table.clear();
        return null;
      case _drawRequest:
        final game = Game.fromJson(request[2]! as Map<String, Object?>);
        return [_drawReply, id, acceptsDraw(game, table: table)];
      default:
        final deadlineMs = request[6] as int?;
        ShouldStop? shouldStop;
        if (deadlineMs != null) {
          final elapsed = Stopwatch()..start();
          shouldStop = () => elapsed.elapsedMilliseconds >= deadlineMs
              ? StopReason.deadline
              : null;
        }
        // Without a cancelling shouldStop, chooseMove always finds a move.
        final choice = chooseMove(
          Position.fromFen(request[2]! as String),
          Strength.values[request[4]! as int],
          request[5]! as int,
          history: (request[3]! as List<Object?>).cast<int>(),
          shouldStop: shouldStop,
          table: table,
          nodeBudget: request[7] as int?,
        )!;
        SendPort? isolate;
        assert(() {
          isolate = Isolate.current.controlPort;
          return true;
        }());
        return [
          _movedReply,
          id,
          choice.move.toUci(),
          choice.search.depth,
          choice.search.nodes,
          isolate,
        ];
    }
  } on Object catch (error, stack) {
    return [_failedReply, id, '$error\n$stack'];
  }
}
