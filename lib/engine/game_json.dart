part of 'game.dart';

// A part of game.dart so the loader builds a Game through its private
// constructor: a saved game enters only through a replay of its moves, never
// through a public constructor that trusts stored positions.

/// The saved-game format this build writes and reads.
const int gameJsonVersion = 1;

/// Why a saved game was refused by [Game.fromJson].
enum GameLoadFailure {
  /// There is no `version`.
  missingVersion,

  /// `version` is not an integer, or is an integer below 1.
  unknownVersion,

  /// `version` is newer than [gameJsonVersion]: a save from a later build.
  newerVersion,

  /// A required field is missing or has the wrong type or value.
  malformed,

  /// The starting FEN does not parse.
  invalidFen,

  /// A move in the list is not legal where it stands.
  illegalMove,

  /// The move list goes on after the game ended.
  movesAfterGameOver,

  /// The stored result is not what the replayed game allows.
  resultContradicted,

  /// The time control or a clock reading is impossible for this game.
  invalidClock,
}

/// A saved game that [Game.fromJson] refuses. Nothing is loaded: the caller
/// gets this error or a whole game, never part of one.
final class GameLoadError implements Exception {
  const GameLoadError(this.reason, this.message, {this.ply});

  final GameLoadFailure reason;
  final String message;

  /// The index in `moves` (or, for a clock reading, in `clock.snapshots`)
  /// where the problem was found, when it belongs to one ply.
  final int? ply;

  @override
  String toString() =>
      'GameLoadError(${reason.name}${ply == null ? '' : ', ply $ply'}): '
      '$message';
}

Never _refuse(GameLoadFailure reason, String message, {int? ply}) =>
    throw GameLoadError(reason, 'game-load: $message', ply: ply);

Never _malformed(String field, String expected) =>
    _refuse(GameLoadFailure.malformed, '$field must be $expected');

String _seedToJson(int seed) => BigInt.from(seed).toUnsigned(64).toString();

final _unsignedDecimal = RegExp(r'^(0|[1-9][0-9]*)$');
final _twoTo64 = BigInt.one << 64;

int _seedFromJson(String text) {
  if (!_unsignedDecimal.hasMatch(text)) {
    _malformed('options.seed', 'an unsigned decimal string');
  }
  final value = BigInt.parse(text);
  if (value >= _twoTo64) _malformed('options.seed', 'below 2^64');
  return value.toSigned(64).toInt();
}

Map<String, Object?> _statusToJson(GameStatus status) => switch (status) {
  Ongoing() => {'outcome': 'ongoing'},
  Win(:final winner, :final reason) => {
    'outcome': 'win',
    'winner': winner.name,
    'reason': reason.name,
  },
  Draw(:final reason) => {'outcome': 'draw', 'reason': reason.name},
};

Map<String, Object?> _clockToJson(Game game, int now) {
  final live = game.clock.snapshot(now);
  return {
    'whiteMs': live.whiteMs,
    'blackMs': live.blackMs,
    'snapshots': [
      for (final s in game.history) [s.clock.whiteMs, s.clock.blackMs],
    ],
  };
}

Map<String, Object?> _gameToJson(Game game) {
  final now = game._time();
  final mode = game.mode;
  return {
    'version': gameJsonVersion,
    'mode': switch (mode) {
      VsComputer(:final playerColour) => {
        'type': 'vsComputer',
        'playerColour': playerColour.name,
      },
      TwoPlayer() => {'type': 'twoPlayers'},
    },
    'options': {
      if (mode is VsComputer) ...{
        'step': mode.step.name,
        'seed': _seedToJson(mode.seed),
      },
      'timeControl': switch (game.clock.control) {
        Untimed() => null,
        Timed(:final minutes, :final incrementSeconds) => {
          'minutes': minutes,
          'incrementSeconds': incrementSeconds,
        },
      },
      'takebackAllowed': game.options.takebackAllowed,
    },
    'startFen': game.history.first.position.toFen(),
    'moves': [for (final move in game.moves) move.toUci()],
    'clock': _clockToJson(game, now),
    'result': _statusToJson(game.status),
  };
}

/// Typed reads from one JSON object, each refusing with [_malformed].
extension type _Fields(Map<String, Object?> map) {
  T _get<T>(String key, String where, String expected) {
    final value = map[key];
    if (value is T) return value;
    _malformed(where.isEmpty ? key : '$where.$key', expected);
  }

  Map<String, Object?> object(String key, [String where = '']) =>
      _get<Map<String, Object?>>(key, where, 'an object');
  List<Object?> list(String key, [String where = '']) =>
      _get<List<Object?>>(key, where, 'an array');
  String string(String key, [String where = '']) =>
      _get<String>(key, where, 'a string');
  int integer(String key, [String where = '']) =>
      _get<int>(key, where, 'an integer');
  bool boolean(String key, [String where = '']) =>
      _get<bool>(key, where, 'true or false');

  E named<E extends Enum>(List<E> values, String key, [String where = '']) {
    final name = string(key, where);
    for (final value in values) {
      if (value.name == name) return value;
    }
    _malformed(
      where.isEmpty ? key : '$where.$key',
      'one of ${values.map((v) => v.name).join(', ')}',
    );
  }
}

void _checkVersion(Map<String, Object?> json) {
  final version = json['version'];
  if (version == null) {
    _refuse(GameLoadFailure.missingVersion, 'there is no version');
  }
  if (version is! int || version < 1) {
    _refuse(
      GameLoadFailure.unknownVersion,
      'version $version is not a known version',
    );
  }
  if (version > gameJsonVersion) {
    _refuse(
      GameLoadFailure.newerVersion,
      'version $version is newer than $gameJsonVersion',
    );
  }
}

GameMode _modeFromJson(_Fields json) {
  final mode = _Fields(json.object('mode'));
  final options = _Fields(json.object('options'));
  return switch (mode.string('type', 'mode')) {
    'vsComputer' => VsComputer(
      playerColour: mode.named(Colour.values, 'playerColour', 'mode'),
      step: options.named(Strength.values, 'step', 'options'),
      seed: _seedFromJson(options.string('seed', 'options')),
    ),
    'twoPlayers' => const TwoPlayer(),
    _ => _malformed('mode.type', 'vsComputer or twoPlayers'),
  };
}

TimeControl _timeControlFromJson(Map<String, Object?> options) {
  if (!options.containsKey('timeControl')) {
    _malformed('options.timeControl', 'present (null when untimed)');
  }
  if (options['timeControl'] == null) return const Untimed();
  final timed = _Fields(_Fields(options).object('timeControl', 'options'));
  final minutes = timed.integer('minutes', 'options.timeControl');
  final increment = timed.integer('incrementSeconds', 'options.timeControl');
  try {
    return Timed(minutes, increment);
  } on RangeError {
    _refuse(
      GameLoadFailure.invalidClock,
      'time control $minutes+$increment is out of range',
    );
  }
}

GameStatus _resultFromJson(_Fields json) {
  final result = _Fields(json.object('result'));
  return switch (result.string('outcome', 'result')) {
    'ongoing' => const Ongoing(inCheck: false),
    'win' => Win(
      result.named(Colour.values, 'winner', 'result'),
      result.named(GameEndReason.values, 'reason', 'result'),
    ),
    'draw' => Draw(result.named(GameEndReason.values, 'reason', 'result')),
    _ => _malformed('result.outcome', 'ongoing, win or draw'),
  };
}

/// Reads `clock.snapshots`: one `[whiteMs, blackMs]` pair per position.
List<(int, int)> _pairsFromJson(_Fields clock, int positions) {
  final raw = clock.list('snapshots', 'clock');
  if (raw.length != positions) {
    _refuse(
      GameLoadFailure.invalidClock,
      'there are ${raw.length} clock snapshots for $positions positions',
    );
  }
  return [
    for (var i = 0; i < raw.length; i++)
      switch (raw[i]) {
        [final int w, final int b] when w >= 0 && b >= 0 => (w, b),
        _ => _refuse(
          GameLoadFailure.invalidClock,
          'clock snapshot $i is not two non-negative integers',
          ply: i,
        ),
      },
  ];
}

int _side((int, int) pair, Colour side) =>
    side == Colour.white ? pair.$1 : pair.$2;

/// Checks that each stored reading could have come from the clock over the
/// replayed moves: the start is the full time, a ply changes only the
/// mover's time, and the mover never gains more than the increment.
void _checkPairs(List<(int, int)> pairs, Game replay, TimeControl control) {
  if (control is! Timed) {
    for (var i = 0; i < pairs.length; i++) {
      if (pairs[i] != (0, 0)) {
        _refuse(
          GameLoadFailure.invalidClock,
          'an untimed game has a clock reading',
          ply: i,
        );
      }
    }
    return;
  }
  final initial = control.initialMs, increment = control.incrementMs;
  if (pairs.first != (initial, initial)) {
    _refuse(
      GameLoadFailure.invalidClock,
      'the start is not ${control.minutes} minutes each',
      ply: 0,
    );
  }
  for (var i = 1; i < pairs.length; i++) {
    final mover = replay.history[i - 1].position.sideToMove;
    final before = _side(pairs[i - 1], mover);
    final after = _side(pairs[i], mover);
    final waited = _side(pairs[i - 1], mover.opponent);
    final possible = i == 1
        ? after == before
        : after > increment && after <= before + increment;
    if (!possible || _side(pairs[i], mover.opponent) != waited) {
      _refuse(
        GameLoadFailure.invalidClock,
        'clock snapshot $i cannot follow snapshot ${i - 1}',
        ply: i,
      );
    }
  }
}

/// The side that resigns in a game over by resignation must be one allowed
/// to: the player against the computer, either side at one device.
List<Colour> _resigners(GameMode mode) => switch (mode) {
  VsComputer(:final playerColour) => [playerColour],
  TwoPlayer() => Colour.values,
};

/// The game's result: the replay's own when the moves ended it or it goes
/// on, else the stored ending once the replay confirms it was possible.
GameStatus _checkResult(GameStatus stored, Game replay, ClockSnapshot live) {
  final last = replay.status;
  final position = replay.position;
  if (last.isOver || stored is Ongoing) {
    if (stored is Ongoing ? last.isOver : stored != last) {
      _refuse(
        GameLoadFailure.resultContradicted,
        'the result $stored is not what the moves give ($last)',
      );
    }
    return last;
  }
  final reason = switch (stored) {
    Win(:final reason) || Draw(:final reason) => reason,
    Ongoing() => throw StateError('unreachable'),
  };
  final possible = switch (reason) {
    GameEndReason.resignation ||
    GameEndReason.resignationNoMatingMaterial => _resigners(replay.mode).any(
      (side) =>
          stored ==
          (canMate(position, side.opponent)
              ? Win(side.opponent, GameEndReason.resignation)
              : const Draw(GameEndReason.resignationNoMatingMaterial)),
    ),
    GameEndReason.agreement =>
      stored == const Draw(GameEndReason.agreement) && replay.moves.length >= 2,
    GameEndReason.flag || GameEndReason.flagNoMatingMaterial =>
      live.control is Timed &&
          replay.moves.isNotEmpty &&
          _side((live.whiteMs, live.blackMs), live.runningSide) == 0 &&
          stored == flagResult(position, live.runningSide),
    _ => false,
  };
  if (!possible) {
    _refuse(
      GameLoadFailure.resultContradicted,
      'the result $stored is not possible after these moves',
    );
  }
  return stored;
}

Game _gameFromJson(Map<String, Object?> map, TimeSource? time) {
  _checkVersion(map);
  final json = _Fields(map);
  final mode = _modeFromJson(json);
  final optionsJson = json.object('options');
  final control = _timeControlFromJson(optionsJson);
  final options = GameOptions(
    takebackAllowed: _Fields(optionsJson).boolean('takebackAllowed', 'options'),
  );
  final startFen = json.string('startFen');
  final moves = json.list('moves');
  final clock = _Fields(json.object('clock'));
  final storedResult = _resultFromJson(json);

  // The replay runs untimed on a stopped time source; the stored clocks are
  // checked against it and applied afterwards.
  Game replay;
  try {
    replay = Game.start(
      mode,
      const Untimed(),
      options: options,
      fen: startFen,
      time: () => 0,
    );
  } on FormatException catch (e) {
    _refuse(GameLoadFailure.invalidFen, 'the start FEN: ${e.message}');
  }
  for (var i = 0; i < moves.length; i++) {
    final uci = moves[i];
    if (uci is! String) _malformed('moves[$i]', 'a UCI string');
    if (replay.isOver) {
      _refuse(
        GameLoadFailure.movesAfterGameOver,
        '$uci follows the end of the game (${replay.status})',
        ply: i,
      );
    }
    try {
      final byComputer = switch (mode) {
        VsComputer(:final computerColour) =>
          replay.sideToMove == computerColour,
        TwoPlayer() => false,
      };
      replay = replay.play(
        Move.fromUci(replay.position, uci),
        byComputer: byComputer,
      );
    } on FormatException {
      _refuse(
        GameLoadFailure.illegalMove,
        '$uci is not legal in ${replay.position.toFen()}',
        ply: i,
      );
    }
  }

  final pairs = _pairsFromJson(clock, replay.history.length);
  _checkPairs(pairs, replay, control);
  final history = [
    for (var i = 0; i < replay.history.length; i++)
      GameSnapshot(
        position: replay.history[i].position,
        move: replay.history[i].move,
        clock: ClockSnapshot(
          control: control,
          phase: i == 0
              ? ClockPhase.notStarted
              : replay.history[i].status.isOver
              ? ClockPhase.ended
              : ClockPhase.running,
          runningSide: i == 0
              ? Colour.black
              : replay.history[i].position.sideToMove,
          whiteMs: pairs[i].$1,
          blackMs: pairs[i].$2,
        ),
        status: replay.history[i].status,
      ),
  ];

  final lastClock = history.last.clock;
  final live = ClockSnapshot(
    control: control,
    phase: storedResult.isOver
        ? (replay.moves.isEmpty && replay.status.isOver
              ? ClockPhase.notStarted
              : ClockPhase.ended)
        : (replay.moves.isEmpty ? ClockPhase.notStarted : ClockPhase.paused),
    runningSide: lastClock.runningSide,
    whiteMs: clock.integer('whiteMs', 'clock'),
    blackMs: clock.integer('blackMs', 'clock'),
  );
  _checkLive(live, lastClock, stoppedAtLastMove: replay.status.isOver);
  final status = _checkResult(storedResult, replay, live);

  final source = time ?? monotonicMillis();
  return Game._(
    mode: mode,
    options: options,
    history: List.unmodifiable(history),
    clock: ChessClock.restore(live, source()),
    status: status,
    time: source,
  );
}

/// Checks the live reading against the last snapshot: only the running
/// side's clock can have moved since, and only down; a clock not started,
/// or stopped by the move that ended the game, has not moved at all.
void _checkLive(
  ClockSnapshot live,
  ClockSnapshot last, {
  required bool stoppedAtLastMove,
}) {
  final running = live.runningSide;
  final now = (live.whiteMs, live.blackMs);
  final then = (last.whiteMs, last.blackMs);
  final unchanged = live.phase == ClockPhase.notStarted || stoppedAtLastMove;
  final possible = live.control is! Timed
      ? now == (0, 0)
      : unchanged
      ? now == then
      : _side(now, running.opponent) == _side(then, running.opponent) &&
            _side(now, running) >= 0 &&
            _side(now, running) <= _side(then, running);
  if (!possible) {
    _refuse(
      GameLoadFailure.invalidClock,
      'the clock ${now.$1}/${now.$2} cannot follow the last move\'s '
      '${then.$1}/${then.$2}',
    );
  }
}
