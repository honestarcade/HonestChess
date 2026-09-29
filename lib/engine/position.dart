import 'fen.dart';
import 'piece.dart';
import 'square.dart';
import 'zobrist.dart';

/// The castling-rights bits of [Position.castlingRights], a 4-bit mask.
abstract final class Castling {
  static const int whiteKingside = 1;
  static const int whiteQueenside = 2;
  static const int blackKingside = 4;
  static const int blackQueenside = 8;
  static const int none = 0;
  static const int all = 15;
}

/// A chess position: piece placement, side to move, castling rights,
/// en-passant target and the two move counters — every field of a FEN.
///
/// Immutable. A position comes from [Position.initial] or [Position.fromFen],
/// which validate it, or from [Position.unchecked], which trusts its caller:
/// it exists for move making, where validating every derived position would
/// cost the search for nothing.
final class Position {
  /// Builds a position from its fields without validating them.
  ///
  /// [bitboards] has one 64-bit board per [Piece], indexed by
  /// [Piece.index]; it is copied. [key], when given, must be what
  /// `positionKey` would compute; otherwise [key] computes it on first use.
  Position.unchecked({
    required List<int> bitboards,
    required this.sideToMove,
    required this.castlingRights,
    required this.enPassant,
    required this.halfmoveClock,
    required this.fullmoveNumber,
    this._key,
  }) : _boards = List<int>.unmodifiable(bitboards) {
    assert(bitboards.length == Piece.values.length);
  }

  /// The FIDE 2.3 starting position, White to move (FIDE 1.2).
  factory Position.initial() => _initial;

  static final Position _initial = parseFen(initialFen);

  /// The FEN of the starting position.
  static const String initialFen =
      'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

  /// Parses a strict FEN, throwing a [FormatException] (see `parseFen`) for
  /// anything malformed or unreachable.
  factory Position.fromFen(String fen) => parseFen(fen);

  final List<int> _boards;

  int? _key;

  /// The Zobrist key (see `positionKey`): equal for positions that are the
  /// same under FIDE 9.2.3. Move making passes it in, updated incrementally;
  /// a position loaded from a FEN computes it on first use.
  int get key => _key ??= positionKey(this);

  /// The side to move.
  final Colour sideToMove;

  /// The [Castling] bits still available.
  final int castlingRights;

  /// The square a pawn passed over on the last move's double push, or null.
  final Square? enPassant;

  /// Plies since the last capture or pawn move.
  final int halfmoveClock;

  /// The move number, starting at 1 and incremented after Black moves.
  final int fullmoveNumber;

  /// The bitboard of [piece].
  int bitboard(Piece piece) => _boards[piece.index];

  /// Every square holding a piece of [colour].
  int occupiedBy(Colour colour) {
    final base = colour.index * 6;
    var bits = 0;
    for (var i = base; i < base + 6; i++) {
      bits |= _boards[i];
    }
    return bits;
  }

  /// Every occupied square.
  int get occupied => occupiedBy(Colour.white) | occupiedBy(Colour.black);

  /// The piece on [square], or null when it is empty.
  Piece? pieceAt(Square square) {
    final bit = square.bit;
    for (var i = 0; i < _boards.length; i++) {
      if (_boards[i] & bit != 0) return Piece.values[i];
    }
    return null;
  }

  /// The square of [colour]'s king. A validated position has exactly one.
  Square kingSquare(Colour colour) {
    final bits = _boards[Piece.of(colour, PieceKind.king).index];
    if (bits == 0) throw StateError('no ${colour.name} king');
    return Square(_lowestBit(bits));
  }

  /// This position as a canonical FEN.
  String toFen() => formatFen(this);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Position ||
        other.sideToMove != sideToMove ||
        other.castlingRights != castlingRights ||
        other.enPassant != enPassant ||
        other.halfmoveClock != halfmoveClock ||
        other.fullmoveNumber != fullmoveNumber) {
      return false;
    }
    for (var i = 0; i < _boards.length; i++) {
      if (other._boards[i] != _boards[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    Object.hashAll(_boards),
    sideToMove,
    castlingRights,
    enPassant,
    halfmoveClock,
    fullmoveNumber,
  );

  @override
  String toString() => 'Position(${toFen()})';
}

int _lowestBit(int bits) {
  var i = 0;
  while (bits & (1 << i) == 0) {
    i++;
  }
  return i;
}
