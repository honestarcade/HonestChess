import 'move.dart';
import 'position.dart';
import 'src/board.dart';

/// The number of leaf nodes of the legal move tree [depth] plies below
/// [position] — the standard test of a move generator against published
/// counts. Depth 0 is the position itself, 1.
///
/// Throws an [ArgumentError] for a negative [depth].
int perft(Position position, int depth) {
  RangeError.checkNotNegative(depth, 'depth');
  if (depth == 0) return 1;
  return _perft(Board.fromPosition(position), depth, [
    for (var i = 0; i < depth; i++) <int>[],
  ]);
}

/// [perft] split by first move: each legal move's UCI form and the leaf
/// count below it, for finding where two generators disagree.
///
/// Throws an [ArgumentError] unless [depth] is at least 1.
Map<String, int> divide(Position position, int depth) {
  if (depth < 1) {
    throw ArgumentError.value(depth, 'depth', 'must be at least 1');
  }
  final board = Board.fromPosition(position);
  final buffers = [for (var i = 0; i < depth; i++) <int>[]];
  final moves = buffers[0];
  board.legalMoves(moves);
  final result = <String, int>{};
  for (final m in moves) {
    board.make(m);
    result[Move.packed(m).toUci()] = depth == 1
        ? 1
        : _perft(board, depth - 1, buffers.sublist(1));
    board.unmake();
  }
  return result;
}

int _perft(Board board, int depth, List<List<int>> buffers) {
  final moves = buffers[buffers.length - depth]..clear();
  board.legalMoves(moves);
  // Bulk counting: at the last ply the number of legal moves is the count.
  if (depth == 1) return moves.length;
  var nodes = 0;
  for (final m in moves) {
    board.make(m);
    nodes += _perft(board, depth - 1, buffers);
    board.unmake();
  }
  return nodes;
}
