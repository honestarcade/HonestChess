// The Elo arithmetic of the Stockfish benchmark (uci_match.dart): the
// logistic 400-point model, fitted by maximum likelihood with draws as half
// points.

import 'dart:math';

/// The score a player rated [elo] expects against one rated [opponent].
double expectedScore(double elo, double opponent) =>
    1 / (1 + pow(10, (opponent - elo) / 400));

/// What Master scored against one opponent level.
final class LevelScore {
  const LevelScore(this.level, this.games, this.points);

  /// The opponent's rating.
  final int level;
  final int games;

  /// Wins plus half the draws.
  final double points;

  /// The rating that expects exactly this score against [level]; null at
  /// 0% or 100%, where only a bound can be said ([performanceText]).
  double? get performance {
    if (points <= 0 || points >= games) return null;
    final s = points / games;
    return level + 400 * log(s / (1 - s)) / ln10;
  }

  String get performanceText {
    final p = performance;
    if (p != null) return '${p.round()}';
    return points <= 0 ? 'below $level' : 'above $level';
  }
}

/// A fitted rating: [elo] with a 95% interval, or a one-sided bound when
/// every game was won or every game lost.
sealed class EloEstimate {
  const EloEstimate();
}

final class Estimate extends EloEstimate {
  const Estimate(this.elo, this.low, this.high);

  final double elo;
  final double low;
  final double high;

  @override
  String toString() =>
      '${elo.round()} (95% interval ${low.round()}–${high.round()})';
}

final class EloBound extends EloEstimate {
  const EloBound({required this.above, required this.level});

  /// Whether the rating is above [level] (every game won) or below it
  /// (every game lost).
  final bool above;
  final int level;

  @override
  String toString() =>
      '${above ? 'above' : 'below'} $level (no finite estimate)';
}

/// The maximum-likelihood rating over [scores], with a 95% interval from
/// the normal approximation (the inverse of the Fisher information).
EloEstimate fitElo(List<LevelScore> scores) {
  final games = scores.fold(0, (n, s) => n + s.games);
  final points = scores.fold(0.0, (n, s) => n + s.points);
  if (games == 0) throw ArgumentError.value(scores, 'scores', 'has no games');
  final levels = [for (final s in scores) s.level];
  if (points <= 0) return EloBound(above: false, level: levels.reduce(min));
  if (points >= games) return EloBound(above: true, level: levels.reduce(max));

  // The likelihood's slope is proportional to points minus expected points,
  // which falls as the rating rises, so bisection finds its one zero.
  double surplus(double elo) =>
      points -
      scores.fold(
        0.0,
        (n, s) => n + s.games * expectedScore(elo, s.level * 1.0),
      );
  var low = -4000.0;
  var high = 8000.0;
  for (var i = 0; i < 200; i++) {
    final mid = (low + high) / 2;
    if (surplus(mid) > 0) {
      low = mid;
    } else {
      high = mid;
    }
  }
  final elo = (low + high) / 2;
  const k = ln10 / 400;
  final information = scores.fold(0.0, (n, s) {
    final e = expectedScore(elo, s.level * 1.0);
    return n + s.games * e * (1 - e) * k * k;
  });
  final margin = 1.96 / sqrt(information);
  return Estimate(elo, elo - margin, elo + margin);
}
