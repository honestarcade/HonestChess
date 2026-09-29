import 'piece.dart';
import 'position.dart';
import 'square.dart';
import 'src/tables.dart';

/// Whether any piece of [by] attacks [square] in [position] (FIDE 3.1.2):
/// could capture a piece standing there. A pinned piece still attacks
/// (FIDE 3.9.1).
bool isAttacked(Position position, Square square, Colour by) => squareAttacked(
  square.index,
  by.index,
  [for (final piece in Piece.values) position.bitboard(piece)],
  position.occupied,
);

/// Whether [colour]'s king is attacked in [position].
bool isInCheck(Position position, Colour colour) =>
    isAttacked(position, position.kingSquare(colour), colour.opponent);

/// Whether the side to move is in check (FIDE 3.9.1).
bool inCheck(Position position) => isInCheck(position, position.sideToMove);
