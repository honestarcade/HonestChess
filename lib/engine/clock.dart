import 'game_status.dart';
import 'piece.dart';
import 'position.dart';

/// Monotonic milliseconds. The clock never reads time itself: every
/// transition takes `now` from one of these, so tests drive it with a fake.
typedef TimeSource = int Function();

/// The production [TimeSource]: milliseconds since this call, from a
/// [Stopwatch], which is monotonic where wall-clock time is not.
TimeSource monotonicMillis() {
  final stopwatch = Stopwatch()..start();
  return () => stopwatch.elapsedMilliseconds;
}

/// A game's time control: untimed, or minutes per side plus an increment.
sealed class TimeControl {
  const TimeControl();

  /// The design's presets, in the order the UI offers them.
  static const presets = <Timed>[Timed.blitz, Timed.rapid, Timed.classical];
}

/// No clocks: the game can never be lost on time.
final class Untimed extends TimeControl {
  const Untimed();

  @override
  bool operator ==(Object other) => other is Untimed;

  @override
  int get hashCode => (Untimed).hashCode;

  @override
  String toString() => 'Untimed()';
}

/// The named presets a [Timed] control may match.
enum TimePreset { blitz, rapid, classical }

/// [minutes] per side, plus [incrementSeconds] added to the mover after
/// each completed move.
final class Timed extends TimeControl {
  /// Throws a [RangeError] (an [ArgumentError]) unless [minutes] is 1–90
  /// and [incrementSeconds] is 0–60, both inclusive.
  factory Timed(int minutes, int incrementSeconds) {
    RangeError.checkValueInInterval(minutes, minMinutes, maxMinutes, 'minutes');
    RangeError.checkValueInInterval(
      incrementSeconds,
      0,
      maxIncrementSeconds,
      'incrementSeconds',
    );
    return Timed._(minutes, incrementSeconds);
  }

  const Timed._(this.minutes, this.incrementSeconds);

  static const blitz = Timed._(5, 0);
  static const rapid = Timed._(10, 5);
  static const classical = Timed._(30, 0);

  static const minMinutes = 1, maxMinutes = 90, maxIncrementSeconds = 60;

  final int minutes;
  final int incrementSeconds;

  /// Each side's starting time.
  int get initialMs => minutes * 60000;

  int get incrementMs => incrementSeconds * 1000;

  /// The preset these values match, if any — derived, so a custom 5+0 is
  /// the blitz preset.
  TimePreset? get preset => switch ((minutes, incrementSeconds)) {
    (5, 0) => TimePreset.blitz,
    (10, 5) => TimePreset.rapid,
    (30, 0) => TimePreset.classical,
    _ => null,
  };

  @override
  bool operator ==(Object other) =>
      other is Timed &&
      other.minutes == minutes &&
      other.incrementSeconds == incrementSeconds;

  @override
  int get hashCode => Object.hash(minutes, incrementSeconds);

  @override
  String toString() => 'Timed($minutes, $incrementSeconds)';
}

/// Where a [ChessClock] is in its life.
enum ClockPhase {
  /// Before the first move that starts it (White's, from the initial
  /// position): neither clock runs.
  notStarted,

  /// [ChessClock.runningSide]'s clock is running.
  running,

  /// Both clocks are stopped; resuming restarts [ChessClock.runningSide]'s.
  paused,

  /// The game is over; every transition is ignored.
  ended,
}

/// A pair of chess clocks as an immutable value: every transition returns a
/// new clock, and every reading takes the current time `now` from the
/// game's [TimeSource].
///
/// Only [runningSide]'s clock runs, and only in [ClockPhase.running]; its
/// time is kept as the remaining time when it started ([_whiteMs] or
/// [_blackMs]) minus the time since [_since]. Times are milliseconds. A time
/// source that goes backwards counts as no time passing.
final class ChessClock {
  /// A clock for [control] that has not started, both sides on the full
  /// time.
  factory ChessClock(TimeControl control) {
    final initial = switch (control) {
      Untimed() => 0,
      Timed() => control.initialMs,
    };
    return ChessClock._(
      control: control,
      phase: ClockPhase.notStarted,
      runningSide: Colour.black,
      whiteMs: initial,
      blackMs: initial,
      since: 0,
    );
  }

  const ChessClock._({
    required this.control,
    required this.phase,
    required this.runningSide,
    required this._whiteMs,
    required this._blackMs,
    required this._since,
  });

  /// A clock restored from [snapshot] at time [now]: the same remaining
  /// times and sides, paused if it was running (the player resumes it).
  factory ChessClock.restore(ClockSnapshot snapshot, int now) => ChessClock._(
    control: snapshot.control,
    phase: snapshot.phase == ClockPhase.running
        ? ClockPhase.paused
        : snapshot.phase,
    runningSide: snapshot.runningSide,
    whiteMs: snapshot.whiteMs,
    blackMs: snapshot.blackMs,
    since: now,
  );

  final TimeControl control;
  final ClockPhase phase;

  /// The side whose clock runs now, or would run on [start] or [resume].
  final Colour runningSide;

  final int _whiteMs;
  final int _blackMs;
  final int _since;

  bool get _timed => control is Timed;

  int _stored(Colour side) => side == Colour.white ? _whiteMs : _blackMs;

  int _elapsed(int now) => now > _since ? now - _since : 0;

  /// [side]'s remaining milliseconds at [now], never below zero; null for
  /// an untimed game.
  int? remaining(Colour side, int now) {
    if (!_timed) return null;
    var ms = _stored(side);
    if (phase == ClockPhase.running && side == runningSide) {
      ms -= _elapsed(now);
    }
    return ms > 0 ? ms : 0;
  }

  /// The side whose time has run out at [now], if any. Never a side in an
  /// untimed game or before the clock starts.
  Colour? flaggedSide(int now) {
    if (!_timed || phase == ClockPhase.notStarted) return null;
    for (final side in Colour.values) {
      if (remaining(side, now)! <= 0) return side;
    }
    return null;
  }

  ChessClock _copy({
    ClockPhase? phase,
    Colour? runningSide,
    int? whiteMs,
    int? blackMs,
    int? since,
  }) => ChessClock._(
    control: control,
    phase: phase ?? this.phase,
    runningSide: runningSide ?? this.runningSide,
    whiteMs: whiteMs ?? _whiteMs,
    blackMs: blackMs ?? _blackMs,
    since: since ?? _since,
  );

  /// This clock with the running side's elapsed time taken off its stored
  /// time, as at [now], and [_since] moved to [now].
  ChessClock _folded(int now) {
    if (phase != ClockPhase.running) return _copy(since: now);
    final left = _stored(runningSide) - _elapsed(now);
    final ms = left > 0 ? left : 0;
    return runningSide == Colour.white
        ? _copy(whiteMs: ms, since: now)
        : _copy(blackMs: ms, since: now);
  }

  /// Starts [side]'s clock at [now] — called after the game's first move,
  /// which earns no increment, with [side] the side now to move. Ignored
  /// unless the clock has not started.
  ChessClock start(Colour side, int now) => phase == ClockPhase.notStarted
      ? _copy(phase: ClockPhase.running, runningSide: side, since: now)
      : this;

  /// [side] completed a move at [now]: its clock stops, it earns the
  /// increment and the opponent's clock starts. A move completed when
  /// [side]'s time had already run out does not count — the result is an
  /// ended clock with [side] flagged, and no increment. Ignored unless the
  /// clock is running.
  ///
  /// Throws a [StateError] when [side]'s clock is not the running one.
  ChessClock moveCompleted(Colour side, int now) {
    if (phase != ClockPhase.running) return this;
    if (side != runningSide) {
      throw StateError(
        'clock: ${side.name} moved on ${runningSide.name}\'s time',
      );
    }
    final folded = _folded(now);
    if (_timed && folded._stored(side) <= 0) {
      return folded._copy(phase: ClockPhase.ended);
    }
    final increment = switch (control) {
      Untimed() => 0,
      final Timed timed => timed.incrementMs,
    };
    final ms = folded._stored(side) + increment;
    return (side == Colour.white
            ? folded._copy(whiteMs: ms)
            : folded._copy(blackMs: ms))
        ._copy(runningSide: side.opponent);
  }

  /// Stops both clocks at [now]. Ignored unless running.
  ChessClock pause(int now) => phase == ClockPhase.running
      ? _folded(now)._copy(phase: ClockPhase.paused)
      : this;

  /// Restarts [runningSide]'s clock at [now]. Ignored unless paused.
  ChessClock resume(int now) => phase == ClockPhase.paused
      ? _copy(phase: ClockPhase.running, since: now)
      : this;

  /// Stops both clocks for good at [now]: the game is over.
  ChessClock end(int now) => phase == ClockPhase.ended
      ? this
      : _folded(now)._copy(phase: ClockPhase.ended);

  /// The clock as plain data at [now], the running side's elapsed time
  /// folded into its remaining time.
  ClockSnapshot snapshot(int now) {
    final folded = _folded(now);
    return ClockSnapshot(
      control: control,
      phase: phase,
      runningSide: runningSide,
      whiteMs: folded._whiteMs,
      blackMs: folded._blackMs,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ChessClock &&
      other.control == control &&
      other.phase == phase &&
      other.runningSide == runningSide &&
      other._whiteMs == _whiteMs &&
      other._blackMs == _blackMs &&
      other._since == _since;

  @override
  int get hashCode =>
      Object.hash(control, phase, runningSide, _whiteMs, _blackMs, _since);

  @override
  String toString() =>
      'ChessClock($control, ${phase.name}, ${runningSide.name}, '
      'white: $_whiteMs, black: $_blackMs, since: $_since)';
}

/// A [ChessClock] as plain data — what a saved game or a takeback snapshot
/// holds. [whiteMs] and [blackMs] are the remaining times at the moment it
/// was taken; they mean nothing for an untimed control.
final class ClockSnapshot {
  const ClockSnapshot({
    required this.control,
    required this.phase,
    required this.runningSide,
    required this.whiteMs,
    required this.blackMs,
  });

  final TimeControl control;
  final ClockPhase phase;
  final Colour runningSide;
  final int whiteMs;
  final int blackMs;

  @override
  bool operator ==(Object other) =>
      other is ClockSnapshot &&
      other.control == control &&
      other.phase == phase &&
      other.runningSide == runningSide &&
      other.whiteMs == whiteMs &&
      other.blackMs == blackMs;

  @override
  int get hashCode =>
      Object.hash(control, phase, runningSide, whiteMs, blackMs);

  @override
  String toString() =>
      'ClockSnapshot($control, ${phase.name}, ${runningSide.name}, '
      'white: $whiteMs, black: $blackMs)';
}

/// The result when [flagged]'s time runs out in [position] (FIDE 6.9): a
/// win for the opponent, or a draw when the opponent could not checkmate by
/// any series of legal moves ([canMate]). Whether the game had already
/// ended is the caller's to check.
GameStatus flagResult(Position position, Colour flagged) {
  final opponent = flagged.opponent;
  return canMate(position, opponent)
      ? Win(opponent, GameEndReason.flag)
      : const Draw(GameEndReason.flagNoMatingMaterial);
}
