/// The computer's search: iterative-deepening alpha-beta over the engine's
/// mutable board.
///
/// Deterministic by construction: nothing here reads a clock or draws a
/// random number (a guard scans this file for both), so the same position,
/// history, limits and starting table give the same move, score and node
/// count every time. Time limits and cancellation come in from outside
/// through [ShouldStop]; the node count is the only budget read inside.
library;

import 'dart:typed_data';

import 'evaluate.dart';
import 'game_status.dart';
import 'move.dart';
import 'piece.dart';
import 'position.dart';
import 'src/board.dart';
import 'src/tables.dart';
import 'transposition.dart';

/// A checkmate, in centipawns: a side mated at ply `n` from the root scores
/// `-(mateScore - n)`, so a nearer mate scores further from zero.
const int mateScore = 32000;

const int _infinity = 32001;
const int _maxPly = 128;
const int _maxExtensions = 16;

/// How many nodes pass between calls to [ShouldStop] (a power of two).
const int stopCheckInterval = 2048;

/// Why a search was asked to stop early.
enum StopReason {
  /// Time is up: the search returns its last finished iteration.
  deadline,

  /// The clock itself is about to run out: the search stops even its first
  /// iteration, and returns its last finished one or, when none has
  /// finished, the best move it has searched so far ([Found.depth] 0).
  outOfTime,

  /// The answer is no longer wanted: the search returns [Cancelled].
  cancel,
}

/// Asked every [stopCheckInterval] nodes; null means carry on.
typedef ShouldStop = StopReason? Function();

/// When a search stops: at [depth] plies, or once it has visited [nodes]
/// nodes, whichever comes first. A deadline is the caller's [ShouldStop].
final class SearchLimits {
  const SearchLimits({
    this.depth = 64,
    this.nodes,
    this.exactRootScores = true,
  });

  /// The deepest iteration to run (at least 1).
  final int depth;

  /// The most nodes to visit, quiescence nodes included; null for no limit.
  /// The first iteration always finishes, so a search may pass it there.
  final int? nodes;

  /// Whether every root move gets an exact score (see [Found.rootScores]).
  /// When false, a root move that cannot beat the best so far is only
  /// proven worse, with a null window — the same move is found for less
  /// work, so the same budget reaches deeper, but the other moves' scores
  /// are bounds.
  final bool exactRootScores;
}

/// What a search found.
sealed class SearchResult {
  const SearchResult();
}

/// The best move of the last iteration the search finished, and its score in
/// centipawns from the side to move's point of view.
final class Found extends SearchResult {
  const Found({
    required this.move,
    required this.score,
    required this.depth,
    required this.nodes,
    required this.pv,
    required this.rootScores,
  });

  final Move move;
  final int score;

  /// The last finished iteration; 0 when [StopReason.outOfTime] stopped the
  /// first.
  final int depth;

  /// Every node visited, the unfinished iteration's included.
  final int nodes;

  /// The expected line, starting with [move].
  final List<Move> pv;

  /// Every legal move with its score at [depth], in move-generation order:
  /// the strength dial chooses among these. Each is exact when the search
  /// ran with [SearchLimits.exactRootScores]; otherwise only [move]'s is
  /// sure to be, and a move marked inexact scores at most what it shows.
  /// At depth 0, a move not yet searched is inexact with a bound above any
  /// score.
  final List<RootScore> rootScores;

  @override
  String toString() =>
      'Found($move, score: $score, depth: $depth, nodes: $nodes, pv: $pv)';
}

/// The search was cancelled: there is no move to play.
final class Cancelled extends SearchResult {
  const Cancelled({required this.nodes});

  final int nodes;

  @override
  String toString() => 'Cancelled(nodes: $nodes)';
}

/// A root move and its score: exact, or (when [exact] is false) an upper
/// bound.
final class RootScore {
  const RootScore(this.move, this.score, {this.exact = true});

  final Move move;
  final int score;
  final bool exact;

  @override
  String toString() => '$move: ${exact ? '' : '<='}$score';
}

/// Whether [score] is a mate for either side.
bool isMateScore(int score) => score.abs() >= mateThreshold;

/// Searches [position] with a fresh [Searcher]; see [Searcher.search].
SearchResult search(
  Position position, {
  SearchLimits limits = const SearchLimits(),
  List<int> history = const [],
  ShouldStop? shouldStop,
  TranspositionTable? table,
}) => Searcher(table: table)
    .search(position, limits: limits, history: history, shouldStop: shouldStop);

final class _Abort implements Exception {
  const _Abort(this.reason);
  final StopReason reason;
}

/// A search with its move-ordering memory (killer moves and history, both
/// cleared at the start of every search) and its transposition table, which
/// lasts as long as the searcher.
final class Searcher {
  /// A searcher using [table], or a new 16 MB table when none is given.
  Searcher({TranspositionTable? table}) : table = table ?? TranspositionTable();

  final TranspositionTable table;

  final Int32List _killers = Int32List(_maxPly * 2);
  final Int32List _history = Int32List(64 * 64);
  final Int32List _pv = Int32List(_maxPly * _maxPly);
  final Int32List _pvLength = Int32List(_maxPly);
  final List<List<int>> _moves = [for (var i = 0; i < _maxPly; i++) <int>[]];
  final List<Int32List> _order = [
    for (var i = 0; i < _maxPly; i++) Int32List(256),
  ];

  late Board _board;
  final List<int> _keys = [];
  int _rootIndex = 0;
  int _nodes = 0;
  int _nodeLimit = 0;
  bool _firstIteration = true;
  ShouldStop? _shouldStop;

  /// Searches [position] and returns its best move.
  ///
  /// [history] holds the Zobrist keys of the game's earlier positions,
  /// oldest first, not including [position]: a position that occurs twice
  /// on the search's own path, or a third time counting [history], is
  /// scored as a draw, as are the fifty-move rule and insufficient material
  /// (as `status` rules them). [shouldStop] is called every
  /// [stopCheckInterval] nodes: [StopReason.deadline] returns the last
  /// finished iteration (the first always finishes), [StopReason.outOfTime]
  /// does the same without waiting for the first, [StopReason.cancel]
  /// returns [Cancelled] at once.
  ///
  /// With one legal move, that move is returned after one iteration. Throws
  /// an [ArgumentError] when there is no legal move.
  SearchResult search(
    Position position, {
    SearchLimits limits = const SearchLimits(),
    List<int> history = const [],
    ShouldStop? shouldStop,
  }) {
    _board = Board.fromPosition(position);
    final rootMoves = <int>[];
    _board.legalMoves(rootMoves);
    if (rootMoves.isEmpty) {
      throw ArgumentError.value(
        position.toFen(),
        'position',
        'has no legal move',
      );
    }

    _keys
      ..clear()
      ..addAll(history)
      ..add(_board.key);
    _rootIndex = history.length;
    _nodes = 0;
    _nodeLimit = limits.nodes ?? -1;
    _shouldStop = shouldStop;
    _killers.fillRange(0, _killers.length, 0);
    _history.fillRange(0, _history.length, 0);
    table.newSearch();

    final count = rootMoves.length;
    final maxDepth = count == 1 ? 1 : limits.depth.clamp(1, _maxPly - 1);
    // Search order for this iteration: indices into rootMoves.
    var order = [for (var i = 0; i < count; i++) i];
    final scores = List<int>.filled(count, 0);
    final exact = List<bool>.filled(count, false);
    final pvs = List<List<int>>.filled(count, const []);
    Found? found;

    for (var depth = 1; depth <= maxDepth; depth++) {
      _firstIteration = depth == 1;
      try {
        var bestSoFar = -_infinity;
        for (final i in order) {
          final move = rootMoves[i];
          if (!limits.exactRootScores && bestSoFar > -_infinity) {
            final bound = _proveNoBetter(move, depth, bestSoFar);
            if (bound <= bestSoFar) {
              scores[i] = bound;
              exact[i] = false;
              pvs[i] = [move];
              continue;
            }
          }
          final (score, line) = _searchRoot(
            move,
            depth,
            found == null || !exact[i] ? null : scores[i],
          );
          scores[i] = score;
          exact[i] = true;
          pvs[i] = line;
          if (score > bestSoFar) bestSoFar = score;
        }
      } on _Abort catch (abort) {
        if (abort.reason == StopReason.cancel) {
          return Cancelled(nodes: _nodes);
        }
        break;
      }

      // The highest exact score; on a tie, the first in generation order.
      var best = exact.indexOf(true);
      for (var i = best + 1; i < count; i++) {
        if (exact[i] && scores[i] > scores[best]) best = i;
      }
      found = Found(
        move: Move.packed(rootMoves[best]),
        score: scores[best],
        depth: depth,
        nodes: _nodes,
        pv: [for (final m in pvs[best]) Move.packed(m)],
        rootScores: [
          for (var i = 0; i < count; i++)
            RootScore(Move.packed(rootMoves[i]), scores[i], exact: exact[i]),
        ],
      );
      // A mate this iteration proved cannot get shorter by going deeper.
      if (isMateScore(scores[best]) &&
          mateScore - scores[best].abs() <= depth) {
        break;
      }
      order = [for (var i = 0; i < count; i++) i]
        ..sort((a, b) {
          final byScore = scores[b].compareTo(scores[a]);
          return byScore != 0 ? byScore : a.compareTo(b);
        });
    }

    if (found == null) {
      // Out of time in the first iteration: the root moves searched so far
      // were searched in generation order, so with none of them finished the
      // first legal move stands.
      var best = exact.indexOf(true);
      for (var i = best + 1; i < count && best >= 0; i++) {
        if (exact[i] && scores[i] > scores[best]) best = i;
      }
      if (best < 0) best = 0;
      return Found(
        move: Move.packed(rootMoves[best]),
        score: exact[best] ? scores[best] : 0,
        depth: 0,
        nodes: _nodes,
        pv: [
          if (exact[best])
            for (final m in pvs[best]) Move.packed(m)
          else
            Move.packed(rootMoves[best]),
        ],
        rootScores: [
          for (var i = 0; i < count; i++)
            pvs[i].isEmpty
                ? RootScore(Move.packed(rootMoves[i]), _infinity, exact: false)
                : RootScore(
                    Move.packed(rootMoves[i]),
                    scores[i],
                    exact: exact[i],
                  ),
        ],
      );
    }
    return Found(
      move: found.move,
      score: found.score,
      depth: found.depth,
      nodes: _nodes,
      pv: found.pv,
      rootScores: found.rootScores,
    );
  }

  /// The exact score of root [move] at [depth], and its line.
  ///
  /// Every root move gets a full-window score, so the strength dial can
  /// compare them all; from depth 5 each starts in a ±25 cp window around
  /// its [previous] score, doubled on the failing side until the score falls
  /// inside.
  (int, List<int>) _searchRoot(int move, int depth, int? previous) {
    var delta = 25;
    var alpha = -_infinity, beta = _infinity;
    if (depth >= 5 && previous != null && !isMateScore(previous)) {
      alpha = previous - delta;
      beta = previous + delta;
    }
    while (true) {
      _board.make(move);
      int score;
      try {
        score = -_negamax(depth - 1, -beta, -alpha, 1, 0, true);
      } finally {
        _board.unmake();
      }
      if (score <= alpha && alpha > -_infinity) {
        delta *= 2;
        alpha = delta > 800 ? -_infinity : score - delta;
      } else if (score >= beta && beta < _infinity) {
        delta *= 2;
        beta = delta > 800 ? _infinity : score + delta;
      } else {
        final length = _pvLength[1];
        return (
          score,
          [move, for (var p = 1; p < length; p++) _pv[_maxPly + p]],
        );
      }
    }
  }

  /// A null-window search of root [move] against [best]: a result at or
  /// below [best] proves the move no better, and bounds its score.
  int _proveNoBetter(int move, int depth, int best) {
    _board.make(move);
    try {
      return -_negamax(depth - 1, -best - 1, -best, 1, 0, true);
    } finally {
      _board.unmake();
    }
  }

  void _visit() {
    _nodes++;
    if (!_firstIteration && _nodeLimit >= 0 && _nodes >= _nodeLimit) {
      throw const _Abort(StopReason.deadline);
    }
    if (_nodes & (stopCheckInterval - 1) == 0 && _shouldStop != null) {
      final reason = _shouldStop!();
      if (reason == StopReason.cancel ||
          reason == StopReason.outOfTime ||
          (reason == StopReason.deadline && !_firstIteration)) {
        throw _Abort(reason!);
      }
    }
  }

  /// Whether the position just reached (its key is [key]) is a draw by
  /// repetition: seen before on the search path, or twice in the game.
  bool _repeated(int key) {
    final top = _keys.length; // where this position's key will go
    final earliest = top - _board.halfmoveClock;
    var inHistory = 0;
    for (var i = top - 2; i >= earliest && i >= 0; i -= 2) {
      if (_keys[i] == key) {
        if (i >= _rootIndex) return true;
        if (++inHistory >= 2) return true;
      }
    }
    return false;
  }

  bool _insufficientMaterial() {
    final b = _board.boards;
    if (b[pawn] |
            b[rook] |
            b[queen] |
            b[6 + pawn] |
            b[6 + rook] |
            b[6 + queen] !=
        0) {
      return false;
    }
    final position = _board.toPosition();
    return !canMate(position, Colour.white) && !canMate(position, Colour.black);
  }

  bool _hasLegalMove(int ply) {
    final moves = _moves[ply]..clear();
    _board.pseudoLegalMoves(moves);
    final us = _board.side;
    for (final move in moves) {
      _board.make(move);
      final legal = !_board.isAttacked(_board.kingSquare(us), us ^ 1);
      _board.unmake();
      if (legal) return true;
    }
    return false;
  }

  int _negamax(
    int depth,
    int alpha,
    int beta,
    int ply,
    int extensions,
    bool nullAllowed,
  ) {
    _pvLength[ply] = ply;
    _visit();
    final board = _board;
    final key = board.key;
    final inCheck = board.inCheck;

    // Draws the game itself would declare.
    if (board.halfmoveClock >= 100) {
      return inCheck && !_hasLegalMove(ply) ? -(mateScore - ply) : 0;
    }
    if (_repeated(key) || _insufficientMaterial()) return 0;
    if (ply >= _maxPly - 1) return evaluateBoard(board);

    // Mate-distance pruning: no line from here beats a mate already found
    // nearer the root.
    if (alpha < -(mateScore - ply)) alpha = -(mateScore - ply);
    if (beta > mateScore - ply - 1) beta = mateScore - ply - 1;
    if (alpha >= beta) return alpha;

    if (inCheck && extensions < _maxExtensions) {
      depth++;
      extensions++;
    }
    if (depth <= 0) return _quiesce(alpha, beta, ply);

    final pvNode = beta - alpha > 1;
    final entry = table.probe(key);
    var ttMove = 0;
    if (entry != 0) {
      ttMove = TranspositionTable.entryMove(entry);
      if (!pvNode && TranspositionTable.entryDepth(entry) >= depth) {
        final score = TranspositionTable.entryScore(entry, ply);
        final bound = TranspositionTable.entryBound(entry);
        if (bound == Bound.exact ||
            (bound == Bound.lower && score >= beta) ||
            (bound == Bound.upper && score <= alpha)) {
          return score;
        }
      }
    }

    final us = board.side;
    // Null move: if passing still leaves this side above beta, a real move
    // would too. Not in check (passing would be illegal), and not with only
    // pawns (zugzwang is common there).
    if (!pvNode &&
        nullAllowed &&
        !inCheck &&
        depth >= 2 &&
        _hasPieces(us) &&
        evaluateBoard(board) >= beta) {
      final reduction = depth > 6 ? 3 : 2;
      _keys.add(key);
      board.makeNull();
      int score;
      try {
        score = -_negamax(
          depth - 1 - reduction,
          -beta,
          -beta + 1,
          ply + 1,
          extensions,
          false,
        );
      } finally {
        board.unmakeNull();
        _keys.removeLast();
      }
      if (score >= beta) return isMateScore(score) ? beta : score;
    }

    final moves = _moves[ply]..clear();
    board.pseudoLegalMoves(moves);
    final order = _order[ply];
    final killer1 = _killers[ply * 2], killer2 = _killers[ply * 2 + 1];
    for (var i = 0; i < moves.length; i++) {
      order[i] = _orderScore(moves[i], ttMove, killer1, killer2);
    }

    final originalAlpha = alpha;
    var best = -_infinity;
    var bestMove = 0;
    var legal = 0;
    _keys.add(key);
    try {
      for (var n = 0; n < moves.length; n++) {
        final move = _pickNext(moves, order, n);
        board.make(move);
        if (board.isAttacked(board.kingSquare(us), us ^ 1)) {
          board.unmake();
          continue;
        }
        legal++;
        final identity = move & 0x7fff;
        final quiet = move & Move.capture == 0 && (move >> 12) & 7 == 0;
        final givesCheck = board.inCheck;

        int score;
        try {
          if (legal == 1) {
            score = -_negamax(
              depth - 1,
              -beta,
              -alpha,
              ply + 1,
              extensions,
              true,
            );
          } else {
            // Late-move reduction: a quiet move ordered this late rarely
            // matters, so it is searched shallower first.
            final reduce =
                legal >= 4 &&
                depth >= 3 &&
                !inCheck &&
                quiet &&
                !givesCheck &&
                identity != killer1 &&
                identity != killer2;
            final reduction = reduce ? (legal >= 10 && depth >= 6 ? 2 : 1) : 0;
            score = -_negamax(
              depth - 1 - reduction,
              -alpha - 1,
              -alpha,
              ply + 1,
              extensions,
              true,
            );
            if (score > alpha && reduction > 0) {
              score = -_negamax(
                depth - 1,
                -alpha - 1,
                -alpha,
                ply + 1,
                extensions,
                true,
              );
            }
            if (score > alpha && score < beta) {
              score = -_negamax(
                depth - 1,
                -beta,
                -alpha,
                ply + 1,
                extensions,
                true,
              );
            }
          }
        } finally {
          board.unmake();
        }

        if (score > best) {
          best = score;
          bestMove = move;
          if (score > alpha) {
            alpha = score;
            _updatePv(ply, move);
            if (score >= beta) {
              if (quiet) {
                if (identity != killer1) {
                  _killers[ply * 2 + 1] = killer1;
                  _killers[ply * 2] = identity;
                }
                _rewardHistory(move, depth);
              }
              break;
            }
          }
        }
      }
    } finally {
      _keys.removeLast();
    }

    if (legal == 0) return inCheck ? -(mateScore - ply) : 0;

    final bound = best >= beta
        ? Bound.lower
        : best > originalAlpha
        ? Bound.exact
        : Bound.upper;
    table.store(key, bestMove, best, depth, bound, ply);
    return best;
  }

  /// Captures and promotions only, until the position is quiet: the side
  /// to move may also "stand pat" on the static evaluation, since it is
  /// never forced to capture.
  int _quiesce(int alpha, int beta, int ply) {
    _pvLength[ply] = ply;
    _visit();
    final board = _board;
    final standPat = evaluateBoard(board);
    if (ply >= _maxPly - 1 || standPat >= beta) return standPat;
    if (standPat > alpha) alpha = standPat;

    final moves = _moves[ply]..clear();
    board.pseudoLegalMoves(moves);
    final order = _order[ply];
    var kept = 0;
    for (var i = 0; i < moves.length; i++) {
      final move = moves[i];
      if (move & Move.capture != 0 || (move >> 12) & 7 != 0) {
        moves[kept] = move;
        order[kept] = _orderScore(move, 0, 0, 0);
        kept++;
      }
    }
    moves.length = kept;

    final us = board.side;
    var best = standPat;
    for (var n = 0; n < kept; n++) {
      final move = _pickNext(moves, order, n);
      final promotion = (move >> 12) & 7;
      // Delta pruning: even winning this piece and a margin would not lift
      // the score to alpha.
      if (promotion == 0) {
        final to = (move >> 6) & 63;
        final victim = move & Move.enPassantFlag != 0
            ? pawn
            : board.squares[to] % 6;
        if (standPat + materialEg[victim] + 200 <= alpha) continue;
      }
      board.make(move);
      if (board.isAttacked(board.kingSquare(us), us ^ 1)) {
        board.unmake();
        continue;
      }
      int score;
      try {
        score = -_quiesce(-beta, -alpha, ply + 1);
      } finally {
        board.unmake();
      }
      if (score > best) {
        best = score;
        if (score > alpha) {
          alpha = score;
          _updatePv(ply, move);
          if (score >= beta) break;
        }
      }
    }
    return best;
  }

  bool _hasPieces(int colour) {
    final b = _board.boards;
    final base = colour * 6;
    return b[base + knight] |
            b[base + bishop] |
            b[base + rook] |
            b[base + queen] !=
        0;
  }

  static const _victimValue = [1, 3, 3, 5, 9, 0];

  /// The move-ordering key: the table's move first, then captures and
  /// promotions by most valuable victim and least valuable attacker, then
  /// the two killers, then quiet moves by history.
  int _orderScore(int move, int ttMove, int killer1, int killer2) {
    final identity = move & 0x7fff;
    if (identity == ttMove && ttMove != 0) return 1 << 30;
    final promotion = (move >> 12) & 7;
    if (move & Move.capture != 0 || promotion != 0) {
      final to = (move >> 6) & 63;
      final victim = move & Move.capture == 0
          ? 0
          : move & Move.enPassantFlag != 0
          ? 1
          : _victimValue[_board.squares[to] % 6];
      final attacker = _board.squares[move & 63] % 6;
      final promoted = promotion == 0 ? 0 : _victimValue[promotion];
      return (1 << 28) + (victim + promoted) * 16 - attacker;
    }
    if (identity == killer1 && killer1 != 0) return (1 << 27) + 1;
    if (identity == killer2 && killer2 != 0) return 1 << 27;
    return _history[identity & 0xfff];
  }

  /// Swaps the best-ordered move from index [n] on into place and returns it;
  /// on a tie the earlier-generated move comes first.
  int _pickNext(List<int> moves, Int32List order, int n) {
    var best = n;
    for (var i = n + 1; i < moves.length; i++) {
      if (order[i] > order[best]) best = i;
    }
    if (best != n) {
      final move = moves[best];
      final score = order[best];
      // Shift rather than swap, so equal-scored moves keep generation order.
      for (var i = best; i > n; i--) {
        moves[i] = moves[i - 1];
        order[i] = order[i - 1];
      }
      moves[n] = move;
      order[n] = score;
    }
    return moves[n];
  }

  void _rewardHistory(int move, int depth) {
    final i = move & 0xfff;
    _history[i] += depth * depth;
    if (_history[i] > (1 << 26)) {
      for (var j = 0; j < _history.length; j++) {
        _history[j] >>= 1;
      }
    }
  }

  void _updatePv(int ply, int move) {
    final row = ply * _maxPly;
    final childRow = (ply + 1) * _maxPly;
    _pv[row + ply] = move;
    final childLength = _pvLength[ply + 1];
    for (var p = ply + 1; p < childLength; p++) {
      _pv[row + p] = _pv[childRow + p];
    }
    _pvLength[ply] = childLength > ply + 1 ? childLength : ply + 1;
  }
}
