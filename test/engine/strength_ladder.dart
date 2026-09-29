// One game of the strength ladder (strength_ladder_test.dart): two steps of
// the dial, in process through chooseMove at each step's own node budget —
// the budgets players get, not the worker isolate or a clock.

import 'package:honest_chess/engine/engine.dart';

import '../fixtures/openings.dart';

/// Plies played after the opening before the game is adjudicated a draw.
const ladderPlyCap = 200;

/// Game `i` of a pair is played with seed `ladderSeedBase + i`, both sides
/// sharing it.
const ladderSeedBase = 2026;

/// How game [index] of a pair starts: game `2k` and `2k + 1` play opening
/// `k` of [ladderOpenings], the stronger step White in the even one.
({List<String> opening, bool strongerIsWhite, int seed}) ladderSetup(
  int index,
) => (
  opening: ladderOpenings[index ~/ 2],
  strongerIsWhite: index.isEven,
  seed: ladderSeedBase + index,
);

/// The end of one ladder game.
final class LadderResult {
  const LadderResult(this.strongerScore, this.ending, this.plies);

  /// 1, ½ or 0, for the stronger step.
  final double strongerScore;

  /// How the game ended: a [GameStatus], or the ply cap.
  final String ending;

  /// Plies played after the opening.
  final int plies;
}

/// Plays game [index] of the match between [stronger] and [weaker]. [table]
/// is reused between moves; chooseMove clears it before every search.
LadderResult playLadderGame(
  Strength stronger,
  Strength weaker,
  int index, {
  TranspositionTable? table,
}) {
  final setup = ladderSetup(index);
  var position = Position.initial();
  final positions = [position];
  for (final uci in setup.opening) {
    position = play(position, Move.fromUci(position, uci));
    positions.add(position);
  }
  final strongerColour = setup.strongerIsWhite ? Colour.white : Colour.black;
  final keys = [for (final p in positions) p.key];
  for (var ply = 0; ply < ladderPlyCap; ply++) {
    final now = status(positions);
    switch (now) {
      case Win(:final winner):
        return LadderResult(winner == strongerColour ? 1 : 0, '$now', ply);
      case Draw():
        return LadderResult(0.5, '$now', ply);
      case Ongoing():
    }
    final step = position.sideToMove == strongerColour ? stronger : weaker;
    final choice = chooseMove(
      position,
      step,
      setup.seed,
      history: keys.sublist(0, keys.length - 1),
      table: table,
    )!;
    position = play(position, choice.move);
    positions.add(position);
    keys.add(position.key);
  }
  final last = status(positions);
  return switch (last) {
    Win(:final winner) => LadderResult(
      winner == strongerColour ? 1 : 0,
      '$last',
      ladderPlyCap,
    ),
    Draw() => LadderResult(0.5, '$last', ladderPlyCap),
    Ongoing() => const LadderResult(0.5, 'ply cap', ladderPlyCap),
  };
}
