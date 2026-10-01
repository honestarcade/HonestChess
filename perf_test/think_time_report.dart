/// The arithmetic behind the thinking-time run (#112): each step's target
/// from the strength table, nearest-rank percentiles, and the table that
/// compares what was measured with what the step says, in both directions.
library;

import 'package:honest_chess/engine/strength.dart';

/// The time [step] says it thinks for, in milliseconds.
int statedMs(Strength step) => (step.settings.thinkSeconds * 1000).round();

/// The most a step's 95th percentile may be: its stated time plus 10 %
/// (owner, /n8-plan M6 round two), so Master's 5 s allows 5.5 s.
int targetMs(Strength step) => (step.settings.thinkSeconds * 1100).round();

/// The [percent]th percentile of [values] by nearest rank: the smallest
/// value at least [percent] % of the values are at or below.
int nearestRank(List<int> values, int percent) {
  if (values.isEmpty) throw ArgumentError.value(values, 'values', 'is empty');
  if (percent <= 0 || percent > 100) {
    throw RangeError.range(percent, 1, 100, 'percent');
  }
  final sorted = [...values]..sort();
  final rank = (percent * sorted.length + 99) ~/ 100;
  return sorted[rank - 1];
}

/// One timed move.
final class MoveTiming {
  const MoveTiming({
    required this.step,
    required this.index,
    required this.ms,
    required this.uci,
    required this.depth,
    required this.nodes,
  });

  final Strength step;

  /// The position's index in the list, which is also its seed.
  final int index;
  final int ms;
  final String uci;
  final int depth;
  final int nodes;

  Map<String, Object> toJson() => {
    'kind': 'move',
    'step': step.name,
    'index': index,
    'ms': ms,
    'uci': uci,
    'depth': depth,
    'nodes': nodes,
  };
}

/// One step's timings summed up.
final class StepReport {
  StepReport(this.step, List<int> ms)
    : count = ms.length,
      p50 = nearestRank(ms, 50),
      p95 = nearestRank(ms, 95),
      max = nearestRank(ms, 100);

  final Strength step;
  final int count;
  final int p50;
  final int p95;
  final int max;

  int get stated => statedMs(step);
  int get target => targetMs(step);

  /// Whether the 95th percentile is within the step's target.
  bool get within => p95 <= target;

  /// How far the 95th percentile is from the stated time, in percent of
  /// it: negative when the step answers faster than it says (its stated
  /// time overstates its thinking), positive when slower.
  int get vsStatedPercent => ((p95 - stated) * 100 / stated).round();

  Map<String, Object> toJson() => {
    'kind': 'step',
    'step': step.name,
    'count': count,
    'statedMs': stated,
    'targetMs': target,
    'p50Ms': p50,
    'p95Ms': p95,
    'maxMs': max,
    'vsStatedPercent': vsStatedPercent,
    'within': within,
  };
}

/// [StepReport]s for every step [moves] cover, weakest first.
List<StepReport> summarise(Iterable<MoveTiming> moves) => [
  for (final step in Strength.values)
    if (moves.where((m) => m.step == step).isNotEmpty)
      StepReport(step, [
        for (final m in moves)
          if (m.step == step) m.ms,
      ]),
];

String _seconds(int ms) => (ms / 1000).toStringAsFixed(2);

/// The results as a plain-text table, one line per step, with a verdict
/// column: `MISS` past the target; otherwise `ok`, or `ok, overstated` when
/// the step answers faster than its stated time — logged, never a failure
/// (#112's replan, 2026-09-29).
List<String> table(List<StepReport> reports) {
  String row(List<String> cells) => [
    cells[0].padRight(9),
    for (final cell in cells.skip(1).take(6)) cell.padLeft(10),
    '  ${cells[7]}',
  ].join();
  return [
    row([
      'step',
      'stated',
      'target',
      'p50',
      'p95',
      'max',
      'vs stated',
      'verdict',
    ]),
    for (final r in reports)
      row([
        r.step.name,
        _seconds(r.stated),
        _seconds(r.target),
        _seconds(r.p50),
        _seconds(r.p95),
        _seconds(r.max),
        '${r.vsStatedPercent > 0 ? '+' : ''}${r.vsStatedPercent}%',
        !r.within
            ? 'MISS'
            : r.p95 < r.stated
            ? 'ok, overstated'
            : 'ok',
      ]),
  ];
}
