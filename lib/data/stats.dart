import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:honest_chess/data/app_store.dart';
import 'package:honest_chess/data/recorded_state.dart';
import 'package:honest_chess/engine/engine.dart';

/// How many recorded game ids the statistics keep, newest last.
const maxRecentIds = 50;

/// The time controls two-player statistics count games under: the three
/// presets, untimed, and every other timed control as one [custom].
enum StatsClock {
  untimed,
  blitz,
  rapid,
  classical,
  custom;

  /// A custom control equal to a preset counts under that preset.
  static StatsClock of(TimeControl control) => switch (control) {
    Untimed() => StatsClock.untimed,
    Timed(:final preset) => switch (preset) {
      TimePreset.blitz => StatsClock.blitz,
      TimePreset.rapid => StatsClock.rapid,
      TimePreset.classical => StatsClock.classical,
      null => StatsClock.custom,
    },
  };
}

/// What [StatsRecorder.recordResult] did: counted the game, found it
/// already counted, or refused a call that was not valid.
enum RecordOutcome { recorded, duplicate, invalid }

/// [StatsRecorder.resetAll] could not write the zeroed statistics; the
/// statistics are unchanged.
final class StatsResetFailed implements Exception {
  const StatsResetFailed();

  @override
  String toString() => 'StatsResetFailed: the statistics were not reset';
}

/// Whether leaving [game] unfinished for a new one counts as a loss: a game
/// against the computer, not over, that you have started and whose result
/// is not already counted.
bool isAbandonable(Game game, RecordedState recorded) =>
    game.mode is VsComputer &&
    !game.isOver &&
    recorded.started &&
    !recorded.outcome;

/// The moves White made in [game] — the result card's MOVES, and what the
/// longest game is measured in.
int whiteMoveCount(Game game) {
  final history = game.history;
  var count = 0;
  for (var i = 1; i < history.length; i++) {
    if (history[i - 1].position.sideToMove == Colour.white) count++;
  }
  return count;
}

/// A whole, non-negative JSON number; anything else reads as 0.
int _count(Object? value) => value is int && value > 0 ? value : 0;

Map<String, Object?> _object(Object? value) =>
    value is Map<String, Object?> ? value : const {};

int _max(int a, int b) => a > b ? a : b;

/// One computer strength step's games.
@immutable
final class StepStats {
  const StepStats({this.played = 0, this.won = 0});

  factory StepStats.fromJson(Object? json) {
    final map = _object(json);
    final played = _count(map['played']);
    return StepStats(played: played, won: _count(map['won']).clamp(0, played));
  }

  final int played;
  final int won;

  Map<String, Object?> toJson() => {'played': played, 'won': won};
}

/// Games against the computer.
@immutable
final class ComputerStats {
  const ComputerStats({
    this.played = 0,
    this.won = 0,
    this.drawn = 0,
    this.lost = 0,
    this.streak = 0,
    this.longestMoves = 0,
    this.steps = const {
      Strength.beginner: StepStats(),
      Strength.casual: StepStats(),
      Strength.club: StepStats(),
      Strength.strong: StepStats(),
      Strength.master: StepStats(),
    },
  });

  /// Reads the `computer` block, cleaned: see [StatsDocument.fromJson].
  factory ComputerStats.fromJson(Object? json) {
    final map = _object(json);
    final played = _count(map['played']);
    final won = _count(map['won']).clamp(0, played);
    final steps = _object(map['steps']);
    return ComputerStats(
      played: played,
      won: won,
      drawn: _count(map['drawn']).clamp(0, played),
      lost: _count(map['lost']).clamp(0, played),
      streak: _count(map['streak']).clamp(0, won),
      longestMoves: _count(map['longestMoves']),
      steps: {
        for (final step in Strength.values)
          step: StepStats.fromJson(steps[step.name]),
      },
    );
  }

  final int played;
  final int won;
  final int drawn;
  final int lost;

  /// Wins in a row, up to the latest game; a draw or a loss ends it.
  final int streak;
  final int longestMoves;

  /// Every step's games, all five always present.
  final Map<Strength, StepStats> steps;

  Map<String, Object?> toJson() => {
    'played': played,
    'won': won,
    'drawn': drawn,
    'lost': lost,
    'streak': streak,
    'longestMoves': longestMoves,
    'steps': {for (final s in Strength.values) s.name: steps[s]!.toJson()},
  };

  ComputerStats _counted(Game game, {required bool? won}) {
    final mode = game.mode as VsComputer;
    final before = steps[mode.step]!;
    return ComputerStats(
      played: played + 1,
      won: won == true ? this.won + 1 : this.won,
      drawn: won == null ? drawn + 1 : drawn,
      lost: won == false ? lost + 1 : lost,
      streak: won == true ? streak + 1 : 0,
      longestMoves: _max(longestMoves, whiteMoveCount(game)),
      steps: {
        for (final s in Strength.values)
          s: s == mode.step
              ? StepStats(
                  played: before.played + 1,
                  won: won == true ? before.won + 1 : before.won,
                )
              : steps[s]!,
      },
    );
  }
}

/// Games between two players.
@immutable
final class TwoPlayerStats {
  const TwoPlayerStats({
    this.played = 0,
    this.whiteWins = 0,
    this.blackWins = 0,
    this.drawn = 0,
    this.longestMoves = 0,
    this.clocks = const {
      StatsClock.untimed: 0,
      StatsClock.blitz: 0,
      StatsClock.rapid: 0,
      StatsClock.classical: 0,
      StatsClock.custom: 0,
    },
  });

  /// Reads the `two` block, cleaned: see [StatsDocument.fromJson].
  factory TwoPlayerStats.fromJson(Object? json) {
    final map = _object(json);
    final played = _count(map['played']);
    final clocks = _object(map['clocks']);
    return TwoPlayerStats(
      played: played,
      whiteWins: _count(map['whiteWins']).clamp(0, played),
      blackWins: _count(map['blackWins']).clamp(0, played),
      drawn: _count(map['drawn']).clamp(0, played),
      longestMoves: _count(map['longestMoves']),
      clocks: {
        for (final clock in StatsClock.values)
          clock: _count(_object(clocks[clock.name])['played']),
      },
    );
  }

  final int played;
  final int whiteWins;
  final int blackWins;
  final int drawn;
  final int longestMoves;

  /// Games played under each time control, all five always present.
  final Map<StatsClock, int> clocks;

  Map<String, Object?> toJson() => {
    'played': played,
    'whiteWins': whiteWins,
    'blackWins': blackWins,
    'drawn': drawn,
    'longestMoves': longestMoves,
    'clocks': {
      for (final c in StatsClock.values) c.name: {'played': clocks[c]!},
    },
  };

  TwoPlayerStats _counted(Game game, GameStatus status) {
    final counted = StatsClock.of(game.clock.control);
    return TwoPlayerStats(
      played: played + 1,
      whiteWins: status is Win && status.winner == Colour.white
          ? whiteWins + 1
          : whiteWins,
      blackWins: status is Win && status.winner == Colour.black
          ? blackWins + 1
          : blackWins,
      drawn: status is Draw ? drawn + 1 : drawn,
      longestMoves: _max(longestMoves, whiteMoveCount(game)),
      clocks: {
        for (final c in StatsClock.values)
          c: c == counted ? clocks[c]! + 1 : clocks[c]!,
      },
    );
  }
}

/// The `stats` document: both modes' counts, the ids of the games counted
/// last ([recentIds], oldest first), and when the statistics were last
/// reset ([resetAt], epoch millis; null if never).
///
/// Immutable: recording answers a new document, so the counting rules are
/// plain functions of the document and the game.
@immutable
final class StatsDocument {
  const StatsDocument({
    this.computer = const ComputerStats(),
    this.two = const TwoPlayerStats(),
    this.recentIds = const [],
    this.resetAt,
  });

  /// No games counted, never reset.
  const StatsDocument.empty() : this();

  /// Reads a stored document, cleaned: counts that are negative, not whole
  /// numbers or not numbers at all read as 0; each mode's results clamp to
  /// its games played, a step's wins to its games, and the streak to the
  /// wins; `recentIds` keeps only well-formed ids, each once, the last
  /// [maxRecentIds]; a `resetAt` that is not a positive whole number reads
  /// as never. Unknown keys are dropped.
  factory StatsDocument.fromJson(Object? json) {
    final map = _object(json);
    final ids = map['recentIds'];
    final seen = <String>{};
    final kept = <String>[
      if (ids is List)
        for (final id in ids)
          if (isGameId(id) && seen.add(id as String)) id,
    ];
    final resetAt = map['resetAt'];
    return StatsDocument(
      computer: ComputerStats.fromJson(map['computer']),
      two: TwoPlayerStats.fromJson(map['two']),
      recentIds: List.unmodifiable(
        kept.length > maxRecentIds
            ? kept.sublist(kept.length - maxRecentIds)
            : kept,
      ),
      resetAt: resetAt is int && resetAt > 0 ? resetAt : null,
    );
  }

  final ComputerStats computer;
  final TwoPlayerStats two;
  final List<String> recentIds;
  final int? resetAt;

  /// The document in one fixed key order, so equal documents encode to the
  /// same bytes.
  Map<String, Object?> toJson() => {
    'computer': computer.toJson(),
    'two': two.toJson(),
    'recentIds': recentIds,
    'resetAt': ?resetAt,
  };

  /// The finished [game], counted under [id]: vs Computer as your win,
  /// draw or loss, between two players as White's win, Black's win or a
  /// draw. Throws [ArgumentError] for a game that is not over.
  StatsDocument withResult(Game game, String id) {
    final status = game.status;
    if (!game.isOver) {
      throw ArgumentError.value(game, 'game', 'the game is not over');
    }
    return switch (game.mode) {
      VsComputer(:final playerColour) => _with(
        id,
        computer: computer._counted(
          game,
          won: status is Win ? status.winner == playerColour : null,
        ),
      ),
      TwoPlayer() => _with(id, two: two._counted(game, status)),
    };
  }

  /// The unfinished game against the computer [game], left for a new one,
  /// counted under [id] as a loss.
  StatsDocument withAbandon(Game game, String id) =>
      _with(id, computer: computer._counted(game, won: false));

  /// Both modes zeroed, [resetAt] set to [now]; [recentIds] is kept, so a
  /// game counted before the reset is never counted again.
  StatsDocument reset(int now) =>
      StatsDocument(recentIds: recentIds, resetAt: now);

  StatsDocument _with(
    String id, {
    ComputerStats? computer,
    TwoPlayerStats? two,
  }) {
    final ids = [...recentIds, id];
    return StatsDocument(
      computer: computer ?? this.computer,
      two: two ?? this.two,
      recentIds: List.unmodifiable(
        ids.length > maxRecentIds
            ? ids.sublist(ids.length - maxRecentIds)
            : ids,
      ),
      resetAt: resetAt,
    );
  }
}

/// Keeps the statistics: the [document] in memory, written to the store's
/// `stats` document after every change.
///
/// Every record and reset runs on one chain, in call order, behind [load];
/// each write is awaited before the next operation starts.
class StatsRecorder extends ChangeNotifier {
  /// [nowMillis] stamps a reset (default the wall clock); tests pass a fake.
  StatsRecorder({required this._store, int Function()? nowMillis})
    : _nowMillis = nowMillis ?? _wallClock;

  static int _wallClock() => DateTime.now().millisecondsSinceEpoch;

  final AppStore _store;
  final int Function() _nowMillis;
  StatsDocument _document = const StatsDocument.empty();
  bool _loaded = false;
  bool _disposed = false;
  Future<void>? _loading;
  Future<void> _tail = Future.value();

  /// The statistics as counted so far; zeros until [load] finishes.
  StatsDocument get document => _document;

  /// Whether the stored statistics have been read.
  bool get isLoaded => _loaded;

  /// Reads the stored statistics once; later calls answer the same future.
  /// An absent or unreadable document starts from zeros, and nothing is
  /// written until the first record or reset.
  Future<void> load() => _loading ??= _enqueue('load', () async {
    try {
      final read = await _store.read(StoreDoc.stats);
      if (read is Loaded) _document = StatsDocument.fromJson(read.data);
    } on Object catch (e) {
      debugPrint('stats: load failed: $e');
    }
    _loaded = true;
    _changed();
  });

  /// Counts the finished [game] once. Answers [RecordOutcome.duplicate],
  /// counting nothing, when [recorded] says it is already counted or its id
  /// was counted before; [RecordOutcome.invalid] for a game not over.
  Future<RecordOutcome> recordResult(Game game, RecordedState recorded) {
    assert(game.isOver, 'stats: recordResult of a game that is not over');
    if (!game.isOver) return Future.value(RecordOutcome.invalid);
    load();
    return _guarded('record', RecordOutcome.invalid, () async {
      if (recorded.outcome || _document.recentIds.contains(recorded.id)) {
        return RecordOutcome.duplicate;
      }
      await _apply(_document.withResult(game, recorded.id));
      return RecordOutcome.recorded;
    });
  }

  /// Counts the unfinished [game] against the computer as a loss, once;
  /// only for a game [isAbandonable] allows. Answers whether the counts
  /// changed.
  Future<bool> recordAbandon(Game game, RecordedState recorded) {
    final valid = isAbandonable(game, recorded);
    assert(valid, 'stats: recordAbandon of a game that is not abandonable');
    if (!valid) return Future.value(false);
    load();
    return _guarded('abandon', false, () async {
      if (_document.recentIds.contains(recorded.id)) return false;
      await _apply(_document.withAbandon(game, recorded.id));
      return true;
    });
  }

  /// Zeroes both modes. The zeroed document is written first; only once
  /// the store accepts it does it replace [document], and the quarantined
  /// copies of the statistics are purged. Throws [StatsResetFailed],
  /// changing nothing, when the store refuses the write.
  Future<void> resetAll() {
    load();
    return _enqueue('reset', () async {
      final zeroed = _document.reset(_nowMillis());
      if (!await _store.write(StoreDoc.stats, zeroed.toJson())) {
        throw const StatsResetFailed();
      }
      _document = zeroed;
      _changed();
      await _store.purgeQuarantined(StoreDoc.stats);
    });
  }

  /// Completes once every record and reset asked for so far is done.
  Future<void> get idle async {
    for (;;) {
      final tail = _tail;
      await tail;
      if (identical(tail, _tail)) return;
    }
  }

  /// Takes [next] in memory at once, then writes it. A refused write keeps
  /// the in-memory counts; the next write carries them to the disk.
  Future<void> _apply(StatsDocument next) async {
    _document = next;
    _changed();
    if (!await _store.write(StoreDoc.stats, next.toJson())) {
      debugPrint('stats: write failed: the store refused it');
    }
  }

  Future<T> _guarded<T>(
    String operation,
    T fallback,
    Future<T> Function() work,
  ) => _enqueue(operation, work).catchError((Object _) => fallback);

  /// Runs [work] after everything queued before it. An error is logged
  /// here and reaches the caller; the chain goes on.
  Future<T> _enqueue<T>(String operation, Future<T> Function() work) {
    final result = _tail.then((_) => work());
    _tail = result.then<void>(
      (_) {},
      onError: (Object e) => debugPrint('stats: $operation failed: $e'),
    );
    return result;
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
