/// The computer's strength dial: five steps, each handicapped exactly as its
/// description says, and the computer's answer to a draw offer.
///
/// Every choice here is a function of the position, the step and the game's
/// seed, so a saved game replays exactly (CLAUDE.md invariant 4); the one
/// source of real randomness is [newGameSeed], drawn once per game.
library;

import 'dart:math';

import 'game.dart';
import 'move.dart';
import 'position.dart';
import 'search.dart';
import 'splitmix.dart';
import 'transposition.dart';

/// Master's search speed on the dev Mac, in nodes per second, to three
/// significant figures: the median of three runs (1,214,787 to 1,237,469)
/// of an AOT build of `tools/bench_search.dart`, measured 2026-09-28 on an
/// Apple M3 Max.
const int calibrationNodesPerSecond = 1220000;

/// How many times slower than the dev Mac a mid-range phone is assumed to
/// be (the readiness pass's calibration rule, #67).
const int phoneSlowdown = 4;

/// [thinkSeconds] of search on a mid-range phone, as a node budget: the
/// calibration rule rounds it to two significant figures.
int calibratedNodeBudget(double thinkSeconds) {
  final nodes = thinkSeconds * calibrationNodesPerSecond / phoneSlowdown;
  final unit = pow(10, (log(nodes) / ln10).floor() - 1);
  return ((nodes / unit).round() * unit).toInt();
}

/// One step's handicaps.
final class StrengthSettings {
  const StrengthSettings({
    required this.depthCap,
    required this.thinkSeconds,
    required this.nodeBudget,
    required this.noiseCp,
    required this.seesMateInOne,
    required this.blunderPercent,
  });

  /// The deepest the search goes, in plies; null for no cap.
  final int? depthCap;

  /// About how long the step may think on a mid-range phone, the target
  /// [nodeBudget] is calibrated to.
  final double thinkSeconds;

  /// The most nodes a search at this step visits.
  final int nodeBudget;

  /// Each root move's score is moved by a seeded amount, uniform in
  /// ±[noiseCp] centipawns, before the best is chosen.
  final int noiseCp;

  /// Whether the step always takes a mate in one and never plays into one.
  /// A step that does not may treat a mate as worth only
  /// [missedMateScore].
  final bool seesMateInOne;

  /// The share of moves, in percent, on which the step blunders: a seeded
  /// roll ([blundersNow]) picks them, and on each it chooses only among the
  /// moves its own search scores at least [blunderCp] below its best
  /// ([chooseMove] says which moves are spared).
  final int blunderPercent;
}

/// How much worse than its best, in centipawns, a move must score for the
/// step to play it as a blunder: two pawns, so a blunder gives up a piece
/// or passes over one left free — never a small positional slip.
const int blunderCp = 200;

/// What a mate, either way, is worth to a step that may miss a mate in one:
/// three pawns, so the noise can outweigh it.
const int missedMateScore = 300;

/// The computer's strength steps, weakest first. A saved game stores the
/// name, so a value is never renamed.
enum Strength {
  beginner(
    StrengthSettings(
      depthCap: 1,
      thinkSeconds: 0.3,
      nodeBudget: 92000,
      noiseCp: 200,
      blunderPercent: 20,
      seesMateInOne: false,
    ),
    'Looks one move ahead and chooses loosely. On 20% of moves it blunders, '
    "giving away two pawns' worth or more, and it can miss mate in one.",
  ),
  casual(
    StrengthSettings(
      depthCap: 2,
      thinkSeconds: 0.6,
      nodeBudget: 180000,
      noiseCp: 100,
      blunderPercent: 20,
      seesMateInOne: true,
    ),
    'Looks two moves ahead, a little loosely. On 20% of moves it blunders, '
    "giving away two pawns' worth or more.",
  ),
  club(
    StrengthSettings(
      depthCap: 2,
      thinkSeconds: 1,
      nodeBudget: 310000,
      noiseCp: 40,
      blunderPercent: 10,
      seesMateInOne: true,
    ),
    'Looks two moves ahead and chooses carefully. On 10% of moves it '
    "blunders, giving away two pawns' worth or more.",
  ),
  strong(
    StrengthSettings(
      depthCap: 4,
      thinkSeconds: 2,
      nodeBudget: 610000,
      noiseCp: 0,
      blunderPercent: 3,
      seesMateInOne: true,
    ),
    'Looks four moves ahead with no looseness. On 3% of moves it blunders, '
    "giving away two pawns' worth or more.",
  ),
  master(
    StrengthSettings(
      depthCap: null,
      thinkSeconds: 5,
      nodeBudget: 1500000,
      noiseCp: 0,
      blunderPercent: 0,
      seesMateInOne: true,
    ),
    'Thinks deeply — up to about five seconds — with nothing held back.',
  );

  const Strength(this.settings, this.description);

  final StrengthSettings settings;

  /// The owner-approved sentence shown with the step.
  final String description;
}

/// A fresh 64-bit seed for a new game against the computer, from the
/// platform's secure random source.
int newGameSeed() {
  final random = Random.secure();
  return (random.nextInt(1 << 32) << 32) | random.nextInt(1 << 32);
}

/// The seeded noise on root [move] in a position with Zobrist key
/// [positionKey]: uniform in ±[noiseCp], a function of the seed, the
/// position (not its move counters) and the move's from, to and promotion
/// only — so neither the order moves are generated in nor the SDK can
/// change it.
int rootNoise(int seed, int positionKey, Move move, int noiseCp) {
  if (noiseCp == 0) return 0;
  var hash = splitMixFinalise(seed + splitMixIncrement);
  hash = splitMixFinalise(hash ^ positionKey);
  hash = splitMixFinalise(hash ^ (move.packed & 0x7fff));
  return SplitMix64(hash).nextBelow(2 * noiseCp + 1) - noiseCp;
}

/// Whether the step blunders on this move: true on [blunderPercent] of the
/// 100 equally likely outcomes of a draw seeded by the game's [seed] and the
/// position's Zobrist key [positionKey] alone — so neither the moves' order
/// nor the device can change it.
bool blundersNow(int seed, int positionKey, int blunderPercent) {
  if (blunderPercent <= 0) return false;
  // A second stream, apart from [rootNoise]'s, so a blunder is not tied to
  // how the noise falls.
  var hash = splitMixFinalise(seed + 2 * splitMixIncrement);
  hash = splitMixFinalise(hash ^ positionKey);
  return SplitMix64(hash).nextBelow(100) < blunderPercent;
}

/// The computer's choice: [move], and the [search] it was chosen from.
final class ComputerMove {
  const ComputerMove(this.move, this.search);

  final Move move;
  final Found search;

  @override
  String toString() => 'ComputerMove($move, $search)';
}

/// The move the computer plays at [step] with the game's [seed].
///
/// The search runs within the step's depth cap and node budget ([nodeBudget]
/// replaces the budget, for tests); every step but one that may miss a mate
/// in one finishes at least two plies, whatever [shouldStop] says about the
/// deadline. The step's noise then moves each root score (mates exempt,
/// except that a step which may miss a mate in one first counts it as only
/// [missedMateScore]) and the highest wins, the first in generation order
/// on a tie. On a move [blundersNow] picks, only the moves scored at least
/// [blunderCp] below the best take part, when there are any; a step that
/// sees mate in one never blunders when it can mate, and never blunders
/// into a move its search sees get it mated. Returns null when
/// [shouldStop] cancels.
///
/// [StopReason.outOfTime] overrides all of that, the floor included: the
/// move is the search's best so far, with no noise when no iteration
/// finished.
///
/// [history] is as for [Searcher.search]. [table], when given, is cleared
/// first.
ComputerMove? chooseMove(
  Position position,
  Strength step,
  int seed, {
  List<int> history = const [],
  ShouldStop? shouldStop,
  TranspositionTable? table,
  int? nodeBudget,
}) {
  final settings = step.settings;
  final handicapped =
      settings.noiseCp > 0 ||
      !settings.seesMateInOne ||
      settings.blunderPercent > 0;
  // A table left over from another search would change what this one
  // finds, so the same position, step and seed would not always give the
  // same move.
  final searcher = Searcher(table: table?..clear());
  final cap = settings.depthCap;
  var result = searcher.search(
    position,
    limits: SearchLimits(
      depth: cap ?? const SearchLimits().depth,
      nodes: nodeBudget ?? settings.nodeBudget,
      exactRootScores: handicapped,
    ),
    history: history,
    shouldStop: shouldStop,
  );

  final floor = settings.seesMateInOne ? min(2, cap ?? 2) : 1;
  // Depth 0 means the clock is running out: there is no time for the floor.
  if (result is Found && result.depth > 0 && result.depth < floor) {
    final deeper = searcher.search(
      position,
      limits: SearchLimits(depth: floor, exactRootScores: handicapped),
      history: history,
      shouldStop: shouldStop == null
          ? null
          : () => switch (shouldStop()) {
              StopReason.deadline => null,
              final reason => reason,
            },
    );
    if (deeper is Cancelled || (deeper as Found).depth > result.depth) {
      result = deeper;
    }
  }

  switch (result) {
    case Cancelled():
      return null;
    case Found() when !handicapped || result.depth == 0:
      return ComputerMove(result.move, result);
    case Found():
      final key = position.key;
      final mates = settings.seesMateInOne;
      int seen(RootScore root) => isMateScore(root.score) && !mates
          ? root.score.sign * missedMateScore
          : root.score;
      var roots = result.rootScores;
      final top = roots.map(seen).reduce(max);
      if (blundersNow(seed, key, settings.blunderPercent) &&
          !(mates && isMateScore(top))) {
        final worse = [
          for (final root in roots)
            if (seen(root) <= top - blunderCp &&
                !(mates && isMateScore(root.score)))
              root,
        ];
        if (worse.isNotEmpty) roots = worse;
      }
      Move? best;
      var bestScore = 0;
      for (final root in roots) {
        var score = seen(root);
        if (!(mates && isMateScore(score))) {
          score += rootNoise(seed, key, root.move, settings.noiseCp);
        }
        if (best == null || score > bestScore) {
          best = root.move;
          bestScore = score;
        }
      }
      return ComputerMove(best!, result);
  }
}

/// How far ahead, in centipawns, the computer may judge itself and still
/// accept a draw.
const int drawMargin = 50;

/// The node budget of the search behind [acceptsDraw], the same at every
/// step.
const int drawSearchNodes = 50000;

/// Whether the computer accepts the player's draw offer in [game]: only when
/// a noise-free search of [nodes] nodes (the last depth it completes) scores
/// the position at most [drawMargin] for the computer. The step plays no
/// part — the answer is equally honest at every step.
/// [table], when given, is cleared first.
///
/// Throws an [ArgumentError] for a game without the computer, and a
/// [StateError] when the game's rules refuse a draw offer now
/// ([Game.canAgreeDraw]).
bool acceptsDraw(
  Game game, {
  TranspositionTable? table,
  int nodes = drawSearchNodes,
}) {
  final mode = game.mode;
  if (mode is! VsComputer) {
    throw ArgumentError.value(mode, 'game', 'is not against the computer');
  }
  if (!game.canAgreeDraw) {
    throw StateError('strength: a draw cannot be offered now');
  }
  final history = game.history;
  final result = search(
    game.position,
    limits: SearchLimits(nodes: nodes, exactRootScores: false),
    history: [
      for (var i = 0; i < history.length - 1; i++) history[i].position.key,
    ],
    table: table?..clear(),
  );
  final score = (result as Found).score;
  final forComputer = game.sideToMove == mode.computerColour ? score : -score;
  return acceptsDrawAt(forComputer);
}

/// The draw decision given the computer's own score in centipawns
/// ([forComputer]): accept at or below [drawMargin].
bool acceptsDrawAt(int forComputer) => forComputer <= drawMargin;
