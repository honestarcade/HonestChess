import 'movegen.dart';
import 'piece.dart';
import 'position.dart';
import 'square.dart';

/// One move: from-square, to-square, the promotion piece if any, and flags
/// the generator already knows (capture, double push, en passant, castling)
/// so that making the move needs no second look at the board.
///
/// A value type over one int. Two moves are equal when their from-square,
/// to-square and promotion agree; the flags follow from the position.
final class Move {
  /// A move from its packed form, [packed]. Only the engine's own generator
  /// builds moves this way; everyone else gets them from [legalMoves] or
  /// [Move.fromUci].
  const Move.packed(this.packed);

  /// Bits 0–5 from, 6–11 to, 12–14 promotion (a [PieceKind] index, 0 for
  /// none — a pawn is never a promotion), 15–18 [capture], [doublePush],
  /// [enPassantFlag], [castling].
  final int packed;

  static const int capture = 1 << 15;
  static const int doublePush = 1 << 16;
  static const int enPassantFlag = 1 << 17;
  static const int castling = 1 << 18;

  static const int _identity = 0x7fff;

  Square get from => Square.values[packed & 63];
  Square get to => Square.values[(packed >> 6) & 63];

  /// The kind a pawn promotes to, or null.
  PieceKind? get promotion {
    final kind = (packed >> 12) & 7;
    return kind == 0 ? null : PieceKind.values[kind];
  }

  bool get isCapture => packed & capture != 0;
  bool get isDoublePush => packed & doublePush != 0;
  bool get isEnPassant => packed & enPassantFlag != 0;
  bool get isCastling => packed & castling != 0;

  /// The UCI long-algebraic form: from, to and a lower-case promotion letter,
  /// e.g. `e2e4`, `e7e8q`; castling is the king's move, `e1g1`.
  String toUci() => '${from.name}${to.name}${promotion?.letter ?? ''}';

  /// The legal move in [position] whose UCI form is [uci].
  ///
  /// Throws a [FormatException] starting `move:` for anything that is not
  /// exactly the UCI form of a legal move there — including upper-case
  /// promotion letters and a promotion letter on a move that is not one.
  static Move fromUci(Position position, String uci) {
    for (final move in legalMoves(position)) {
      if (move.toUci() == uci) return move;
    }
    throw FormatException(
      'move: "$uci" is not a legal move in ${position.toFen()}',
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Move && other.packed & _identity == packed & _identity;

  @override
  int get hashCode => packed & _identity;

  @override
  String toString() => toUci();
}
