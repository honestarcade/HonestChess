import 'piece.dart';
import 'position.dart';
import 'square.dart';

const _knightSteps = [
  (1, 2),
  (2, 1),
  (2, -1),
  (1, -2),
  (-1, -2),
  (-2, -1),
  (-2, 1),
  (-1, 2),
];
const _kingSteps = [
  (1, 0),
  (1, 1),
  (0, 1),
  (-1, 1),
  (-1, 0),
  (-1, -1),
  (0, -1),
  (1, -1),
];
const _rookRays = [(1, 0), (-1, 0), (0, 1), (0, -1)];
const _bishopRays = [(1, 1), (1, -1), (-1, 1), (-1, -1)];

/// Whether any piece of [by] attacks [square] in [position].
///
/// A ray walk over the board, simple rather than fast.
bool isAttacked(Position position, Square square, Colour by) {
  Piece? at(int file, int rank) => file < 0 || file > 7 || rank < 0 || rank > 7
      ? null
      : position.pieceAt(Square.at(file, rank));

  bool hits(int file, int rank, PieceKind kind) =>
      at(file, rank) == Piece.of(by, kind);

  final f = square.file, r = square.rank;

  // A pawn of [by] attacks diagonally forward, so it stands one rank behind
  // the square from its own side's point of view.
  final behind = by == Colour.white ? r - 1 : r + 1;
  if (hits(f - 1, behind, PieceKind.pawn) ||
      hits(f + 1, behind, PieceKind.pawn)) {
    return true;
  }
  for (final (df, dr) in _knightSteps) {
    if (hits(f + df, r + dr, PieceKind.knight)) return true;
  }
  for (final (df, dr) in _kingSteps) {
    if (hits(f + df, r + dr, PieceKind.king)) return true;
  }

  bool slides(List<(int, int)> rays, PieceKind kind) {
    for (final (df, dr) in rays) {
      for (
        var nf = f + df, nr = r + dr;
        nf >= 0 && nf <= 7 && nr >= 0 && nr <= 7;
        nf += df, nr += dr
      ) {
        final piece = position.pieceAt(Square.at(nf, nr));
        if (piece == null) continue;
        if (piece == Piece.of(by, kind) ||
            piece == Piece.of(by, PieceKind.queen)) {
          return true;
        }
        break;
      }
    }
    return false;
  }

  return slides(_rookRays, PieceKind.rook) ||
      slides(_bishopRays, PieceKind.bishop);
}

/// Whether [colour]'s king is attacked in [position].
bool isInCheck(Position position, Colour colour) =>
    isAttacked(position, position.kingSquare(colour), colour.opponent);
