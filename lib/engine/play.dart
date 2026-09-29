import 'move.dart';
import 'position.dart';
import 'src/board.dart';

/// The position after [move] is played in [position] (FIDE 1.3, 3): the
/// captured piece gone (the en-passant victim included), the castling rook
/// moved, a promoted pawn replaced, castling rights, en-passant square and
/// both counters updated, and the other side to move. The result carries its
/// Zobrist `key` from the move-making board's incremental update.
///
/// Throws an [ArgumentError] when [move] is not one of `legalMoves(position)`.
Position play(Position position, Move move) {
  final board = Board.fromPosition(position);
  final moves = <int>[];
  board.legalMoves(moves);
  for (final packed in moves) {
    if (Move.packed(packed) == move) {
      board.make(packed);
      return board.toPosition();
    }
  }
  throw ArgumentError.value(
    move,
    'move',
    'not a legal move in ${position.toFen()}',
  );
}
