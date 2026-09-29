// Chess clocks against a fake time source: each time control's start, the
// increment only after a completed move, pausing, flag fall and the FIDE
// 6.9 draw when the opponent has no mating material.

import 'package:flutter_test/flutter_test.dart';
import 'package:honest_chess/engine/engine.dart';

const white = Colour.white, black = Colour.black;
const minute = 60000;

/// A hand-wound monotonic time source.
class FakeTime {
  int ms = 0;
  int call() => ms;
  void advance(int by) => ms += by;
}

void main() {
  group('time controls', () {
    test('each preset starts both sides on its minutes', () {
      expect(TimeControl.presets, [Timed.blitz, Timed.rapid, Timed.classical]);
      for (final (control, minutes, increment) in [
        (Timed.blitz, 5, 0),
        (Timed.rapid, 10, 5),
        (Timed.classical, 30, 0),
      ]) {
        expect(control.minutes, minutes);
        expect(control.incrementSeconds, increment);
        final clock = ChessClock(control);
        expect(clock.phase, ClockPhase.notStarted);
        expect(clock.remaining(white, 0), minutes * minute);
        expect(clock.remaining(black, 0), minutes * minute);
      }
    });

    test('a custom control equal to a preset is that preset', () {
      expect(Timed(5, 0), Timed.blitz);
      expect(Timed(5, 0).preset, TimePreset.blitz);
      expect(Timed(10, 5).preset, TimePreset.rapid);
      expect(Timed(30, 0).preset, TimePreset.classical);
      expect(Timed(5, 1).preset, isNull);
      expect(Timed(5, 1), isNot(Timed.blitz));
      expect(const Untimed(), const Untimed());
      expect(const Untimed(), isNot(Timed.blitz));
    });

    test('custom accepts the bounds and refuses anything outside', () {
      for (final (m, i) in [(1, 0), (90, 60), (1, 60), (90, 0), (45, 30)]) {
        final control = Timed(m, i);
        expect(control.initialMs, m * minute);
        expect(control.incrementMs, i * 1000);
      }
      for (final (m, i) in [(0, 0), (91, 0), (-1, 5), (5, -1), (5, 61)]) {
        expect(
          () => Timed(m, i),
          throwsArgumentError,
          reason: 'clock: Timed($m, $i) is outside 1–90 min, 0–60 s',
        );
      }
    });
  });

  group('running', () {
    test('nothing runs before the start (White\'s first move)', () {
      final clock = ChessClock(Timed.blitz);
      expect(clock.remaining(white, 99999), 5 * minute);
      expect(clock.remaining(black, 99999), 5 * minute);
      expect(clock.flaggedSide(10 * minute), isNull);
      expect(
        clock.moveCompleted(white, 1000),
        clock,
        reason: 'clock: a move before the start is ignored',
      );
      expect(clock.pause(5), clock);
      expect(clock.resume(5), clock);
    });

    test('White\'s first move earns no increment; later moves do', () {
      final time = FakeTime()..ms = 7000;
      // White has thought 7 s over the first move; the clock starts after it.
      var clock = ChessClock(Timed.rapid).start(black, time());
      expect(clock.phase, ClockPhase.running);
      expect(clock.runningSide, black);
      expect(clock.remaining(white, time()), 10 * minute);

      time.advance(3000);
      expect(clock.remaining(black, time()), 10 * minute - 3000);
      expect(
        clock.remaining(black, time()),
        isNot(10 * minute + 2000),
        reason: 'clock: no increment while still thinking',
      );
      expect(clock.remaining(white, time()), 10 * minute);

      clock = clock.moveCompleted(black, time());
      expect(clock.remaining(black, time()), 10 * minute - 3000 + 5000);
      expect(clock.runningSide, white);

      time.advance(4000);
      expect(
        clock.remaining(black, time()),
        10 * minute + 2000,
        reason: 'clock: the idle clock does not run',
      );
      expect(clock.remaining(white, time()), 10 * minute - 4000);
      clock = clock.moveCompleted(white, time());
      expect(clock.remaining(white, time()), 10 * minute + 1000);
      expect(clock.runningSide, black);
    });

    test('a move on the other side\'s time is refused', () {
      final clock = ChessClock(Timed.blitz).start(black, 0);
      expect(() => clock.moveCompleted(white, 10), throwsStateError);
    });

    test('pause stops both clocks; resume restarts the side to move', () {
      final time = FakeTime();
      var clock = ChessClock(Timed.blitz).start(black, time());
      time.advance(1000);
      clock = clock.pause(time());
      expect(clock.phase, ClockPhase.paused);
      time.advance(10 * minute);
      expect(clock.remaining(black, time()), 5 * minute - 1000);
      expect(clock.remaining(white, time()), 5 * minute);
      expect(clock.flaggedSide(time()), isNull);
      expect(
        clock.moveCompleted(black, time()),
        clock,
        reason: 'clock: a paused clock takes no moves',
      );
      expect(clock.pause(time()), clock, reason: 'clock: pausing twice');

      clock = clock.resume(time());
      expect(clock.phase, ClockPhase.running);
      expect(clock.runningSide, black);
      time.advance(500);
      expect(clock.remaining(black, time()), 5 * minute - 1500);
      expect(clock.resume(time()), clock, reason: 'clock: resuming twice');
    });

    test('a time source going backwards counts as no time passing', () {
      final clock = ChessClock(Timed.blitz).start(black, 5000);
      expect(clock.remaining(black, 1000), 5 * minute);
      expect(
        clock.moveCompleted(black, 1000).remaining(black, 1000),
        5 * minute,
      );
    });

    test('an untimed game never flags', () {
      final time = FakeTime();
      var clock = ChessClock(const Untimed()).start(black, time());
      time.advance(1000 * 24 * 60 * minute);
      expect(clock.remaining(black, time()), isNull);
      expect(clock.flaggedSide(time()), isNull);
      clock = clock.moveCompleted(black, time());
      expect(clock.phase, ClockPhase.running);
      expect(clock.runningSide, white);
      expect(clock.flaggedSide(time() + (1 << 40)), isNull);
    });

    test('ended clocks ignore every transition', () {
      final time = FakeTime();
      var clock = ChessClock(Timed.blitz).start(black, time());
      time.advance(2000);
      clock = clock.end(time());
      expect(clock.phase, ClockPhase.ended);
      time.advance(10 * minute);
      expect(clock.remaining(black, time()), 5 * minute - 2000);
      expect(clock.flaggedSide(time()), isNull);
      for (final next in [
        clock.moveCompleted(black, time()),
        clock.pause(time()),
        clock.resume(time()),
        clock.start(white, time()),
        clock.end(time()),
      ]) {
        expect(next, clock, reason: 'clock: an ended clock does not change');
      }
    });
  });

  group('flag fall', () {
    test('the running side flags at zero, not a millisecond before', () {
      var clock = ChessClock(Timed(1, 0)).start(black, 0);
      expect(clock.flaggedSide(minute - 1), isNull);
      expect(clock.remaining(black, minute - 1), 1);
      expect(clock.flaggedSide(minute), black);
      expect(clock.remaining(black, minute + 5000), 0);
      expect(clock.remaining(white, minute + 5000), minute);

      clock = clock.moveCompleted(black, minute - 1);
      expect(clock.phase, ClockPhase.running);
      expect(clock.flaggedSide(minute - 1), isNull);
    });

    test(
      'a move completed after the time ran out flags, with no increment',
      () {
        final clock = ChessClock(Timed(1, 60)).start(black, 0);
        final late = clock.moveCompleted(black, minute + 10);
        expect(late.phase, ClockPhase.ended);
        expect(late.flaggedSide(minute + 10), black);
        expect(
          late.remaining(black, minute + 10),
          0,
          reason: 'clock: the flag outranks the increment',
        );
        expect(late.flaggedSide(5 * minute), black);
      },
    );

    test('flag → loss when the opponent has mating material', () {
      for (final fen in [
        Position.initialFen,
        // K+N v K+B: the bishop can block its own king, so a helpmate exists.
        '4kb2/8/8/8/8/8/8/1N2K3 w - - 0 1',
        // Opponent K+P only.
        '4k3/8/8/8/8/8/4P3/4K3 w - - 0 1',
      ]) {
        expect(
          flagResult(Position.fromFen(fen), black),
          const Win(white, GameEndReason.flag),
          reason: 'flag: $fen',
        );
      }
      expect(
        flagResult(Position.fromFen('4k2r/8/8/8/8/8/8/1N2K3 w - - 0 1'), white),
        const Win(black, GameEndReason.flag),
      );
    });

    test('flag → draw when the opponent has a bare king or a lone minor', () {
      for (final (fen, flagged) in [
        // Opponent bare king against the flagging queen.
        ('4k3/8/8/8/8/8/8/3QK3 w - - 0 1', white),
        // Opponent K+N, flagging side bare king.
        ('4k3/8/8/8/8/8/8/1N2K3 w - - 0 1', black),
        // Opponent K+B, flagging side bare king.
        ('4k3/8/8/8/8/8/8/2B1K3 w - - 0 1', black),
      ]) {
        expect(
          flagResult(Position.fromFen(fen), flagged),
          const Draw(GameEndReason.flagNoMatingMaterial),
          reason: 'flag: $fen, ${flagged.name} flagged',
        );
      }
    });

    test('flag → loss for K+N v K+R even though the rook side flags', () {
      // White K+N, Black K+R: Black flags. White's lone knight can mate
      // (Black's rook can block its own king), so White wins.
      final position = Position.fromFen('4k2r/8/8/8/8/8/8/1N2K3 w - - 0 1');
      expect(flagResult(position, black), const Win(white, GameEndReason.flag));
    });
  });

  group('snapshot', () {
    test('holds and restores the clock exactly, paused', () {
      final time = FakeTime();
      var clock = ChessClock(Timed.rapid).start(black, time());
      time.advance(2500);
      clock = clock.moveCompleted(black, time());
      time.advance(1200);
      final snapshot = clock.snapshot(time());
      expect(
        snapshot,
        ClockSnapshot(
          control: Timed.rapid,
          phase: ClockPhase.running,
          runningSide: white,
          whiteMs: 10 * minute - 1200,
          blackMs: 10 * minute + 2500,
        ),
      );

      time.advance(60000);
      final restored = ChessClock.restore(snapshot, time());
      expect(restored.phase, ClockPhase.paused);
      expect(restored.runningSide, white);
      expect(restored.control, Timed.rapid);
      expect(restored.remaining(white, time()), 10 * minute - 1200);
      expect(restored.remaining(black, time()), 10 * minute + 2500);
      time.advance(1000);
      expect(
        restored.snapshot(time()),
        ClockSnapshot(
          control: Timed.rapid,
          phase: ClockPhase.paused,
          runningSide: white,
          whiteMs: 10 * minute - 1200,
          blackMs: 10 * minute + 2500,
        ),
      );
    });

    test('a takeback restores the earlier times with no increment', () {
      final time = FakeTime();
      var clock = ChessClock(Timed.rapid).start(black, time());
      time.advance(1000);
      final before = clock.snapshot(time());
      clock = clock.moveCompleted(black, time());
      expect(clock.remaining(black, time()), 10 * minute + 4000);

      final back = ChessClock.restore(before, time());
      expect(
        back.remaining(black, time()),
        10 * minute - 1000,
        reason: 'clock: a takeback earns no increment',
      );
      expect(back.resume(time() + 1).runningSide, black);
    });

    test('not-started and ended clocks restore as they were', () {
      final fresh = ChessClock(Timed.blitz);
      expect(
        ChessClock.restore(fresh.snapshot(0), 50).phase,
        ClockPhase.notStarted,
      );
      final ended = ChessClock(Timed(1, 0)).start(black, 0).end(minute + 1);
      final restored = ChessClock.restore(ended.snapshot(minute + 1), 5);
      expect(restored.phase, ClockPhase.ended);
      expect(restored.flaggedSide(5), black);
    });
  });

  test('monotonicMillis counts up from zero', () {
    final now = monotonicMillis();
    final first = now();
    expect(first, greaterThanOrEqualTo(0));
    expect(now(), greaterThanOrEqualTo(first));
  });
}
