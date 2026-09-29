import 'move.dart';
import 'position.dart';
import 'src/board.dart';

/// Every legal move in [position] (FIDE 3.10), and nothing else.
///
/// The order is deterministic — pawns, then knights, bishops, rooks, queens
/// and the king, each from a1 upwards, castling last — so the same position
/// always yields the same list.
List<Move> legalMoves(Position position) {
  final packed = <int>[];
  Board.fromPosition(position).legalMoves(packed);
  return [for (final m in packed) Move.packed(m)];
}
