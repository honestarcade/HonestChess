import 'movegen.dart';
import 'piece.dart';
import 'position.dart';
import 'zobrist_keys.dart';

/// `castlingKey[rights]`: the XOR of the castling keys for each right set in
/// a `Castling` mask.
final List<int> castlingKey = [
  for (var rights = 0; rights < 16; rights++)
    () {
      var key = 0;
      for (var bit = 0; bit < 4; bit++) {
        if (rights & (1 << bit) != 0) key ^= zobristKeys[zobristCastling + bit];
      }
      return key;
    }(),
];

/// The key of [piece] on square [square] (0–63).
int pieceKey(int piece, int square) => zobristKeys[piece * 64 + square];

/// The file (0–7) of the en-passant capture the side to move can legally
/// make in [position], or null when there is none.
///
/// FIDE 9.2.3.1: an en-passant square only makes a position different when
/// the capture could actually be played — a pawn beside the double-pushed
/// one, and not pinned. The FEN keeps the square after every double push;
/// only position identity filters it.
int? legalEnPassantFile(Position position) {
  if (position.enPassant == null) return null;
  for (final move in legalMoves(position)) {
    if (move.isEnPassant) return move.to.file;
  }
  return null;
}

/// The Zobrist key of [position], computed from scratch.
///
/// Two positions have equal keys when they are the same position in the
/// sense of FIDE 9.2.3 — same side to move, same pieces on the same squares,
/// same castling rights and the same legal en-passant capture — and, but for
/// a 64-bit collision, only then; [isSamePosition] settles a collision.
/// `Position.key` holds the same value, kept incrementally by move making.
int positionKey(Position position) {
  var key = 0;
  for (final piece in Piece.values) {
    var bits = position.bitboard(piece);
    for (var square = 0; bits != 0; square++, bits >>>= 1) {
      if (bits & 1 != 0) key ^= pieceKey(piece.index, square);
    }
  }
  if (position.sideToMove == Colour.black) key ^= zobristKeys[zobristSide];
  key ^= castlingKey[position.castlingRights];
  final file = legalEnPassantFile(position);
  if (file != null) key ^= zobristKeys[zobristEnPassant + file];
  return key;
}

/// Whether [a] and [b] are the same position under FIDE 9.2.3: the same
/// player to move, the same pieces on the same squares, the same castling
/// rights (9.2.3.2) and the same possible en-passant capture (9.2.3.1).
/// The move counters do not matter.
bool isSamePosition(Position a, Position b) {
  if (a.sideToMove != b.sideToMove || a.castlingRights != b.castlingRights) {
    return false;
  }
  for (final piece in Piece.values) {
    if (a.bitboard(piece) != b.bitboard(piece)) return false;
  }
  return legalEnPassantFile(a) == legalEnPassantFile(b);
}
