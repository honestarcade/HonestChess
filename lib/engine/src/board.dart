/// The engine's mutable board: pseudo-legal generation, make and unmake.
///
/// A [Position] is immutable, which is right for everything outside the
/// engine and too slow for a search that visits millions of nodes. This
/// board is mutated in place and restored from an undo stack instead.
library;

import '../move.dart';
import '../piece.dart';
import '../position.dart';
import '../square.dart';
import '../zobrist.dart';
import '../zobrist_keys.dart';
import 'tables.dart';

const _whiteKingside = Castling.whiteKingside;
const _whiteQueenside = Castling.whiteQueenside;
const _blackKingside = Castling.blackKingside;
const _blackQueenside = Castling.blackQueenside;

/// The kinds a pawn may promote to (FIDE 3.7.3.3): never a king or a pawn.
const _promotionKinds = [queen, rook, bishop, knight];

/// `_rightsKept[square]`: the castling bits that survive a move from or to
/// that square. Moving the king loses both of its side's rights, and moving
/// or capturing a rook on its home square loses that one (FIDE 3.8.2.1).
final List<int> _rightsKept = [
  for (var sq = 0; sq < 64; sq++)
    Castling.all &
        ~switch (sq) {
          0 => _whiteQueenside, // a1
          4 => _whiteKingside | _whiteQueenside, // e1
          7 => _whiteKingside, // h1
          56 => _blackQueenside, // a8
          60 => _blackKingside | _blackQueenside, // e8
          63 => _blackKingside, // h8
          _ => 0,
        },
];

int _pack(int from, int to, [int flags = 0, int promotion = 0]) =>
    from | to << 6 | promotion << 12 | flags;

/// A mutable chess position with an undo stack.
final class Board {
  /// A board set up as [position].
  Board.fromPosition(Position position)
    : side = position.sideToMove.index,
      castling = position.castlingRights,
      enPassant = position.enPassant?.index ?? -1,
      halfmoveClock = position.halfmoveClock,
      fullmoveNumber = position.fullmoveNumber {
    for (final piece in Piece.values) {
      var bits = position.bitboard(piece);
      boards[piece.index] = bits;
      occupiedBy[piece.colour.index] |= bits;
      while (bits != 0) {
        final square = lowestBit(bits);
        squares[square] = piece.index;
        _baseKey ^= pieceKey(piece.index, square);
        bits &= bits - 1;
      }
    }
    if (side == 1) _baseKey ^= zobristKeys[zobristSide];
    _baseKey ^= castlingKey[castling];
  }

  /// One bitboard per piece, indexed by `Piece.index`.
  final List<int> boards = List.filled(12, 0);

  /// The piece index on each square, or -1 when it is empty.
  final List<int> squares = List.filled(64, -1);

  /// The squares each colour occupies.
  final List<int> occupiedBy = [0, 0];

  /// The side to move: 0 White, 1 Black.
  int side;

  /// The `Castling` bits still available.
  int castling;

  /// The en-passant target square, or -1.
  int enPassant;

  int halfmoveClock;
  int fullmoveNumber;

  /// The Zobrist key of everything but the en-passant file: pieces, side to
  /// move and castling rights, kept by [make] and [unmake] with one XOR per
  /// change.
  int _baseKey = 0;

  /// Per made move: the move, then its undo record (captured piece + 1,
  /// castling rights, en-passant square + 1, halfmove clock).
  final List<int> _history = [];

  int get occupied => occupiedBy[0] | occupiedBy[1];

  /// This board as an immutable [Position].
  Position toPosition() => Position.unchecked(
    bitboards: boards,
    sideToMove: Colour.values[side],
    castlingRights: castling,
    enPassant: enPassant < 0 ? null : Square(enPassant),
    halfmoveClock: halfmoveClock,
    fullmoveNumber: fullmoveNumber,
    key: key,
  );

  /// The Zobrist key of this board, equal to `positionKey(toPosition())`.
  ///
  /// The en-passant file is added only when an en-passant capture is legal
  /// (FIDE 9.2.3.1), which takes trying the capture — so it is worked out
  /// here, on demand, rather than on every [make].
  int get key {
    if (enPassant < 0) return _baseKey;
    final us = side;
    var capturers = pawnAttacks[us ^ 1][enPassant] & boards[us * 6 + pawn];
    while (capturers != 0) {
      final from = lowestBit(capturers);
      capturers &= capturers - 1;
      make(_pack(from, enPassant, Move.capture | Move.enPassantFlag));
      final legal = !isAttacked(kingSquare(us), us ^ 1);
      unmake();
      if (legal) {
        return _baseKey ^ zobristKeys[zobristEnPassant + (enPassant & 7)];
      }
    }
    return _baseKey;
  }

  int kingSquare(int colour) => lowestBit(boards[colour * 6 + king]);

  bool isAttacked(int square, int by) =>
      squareAttacked(square, by, boards, occupied);

  /// Whether the side to move's king is attacked.
  bool get inCheck => isAttacked(kingSquare(side), side ^ 1);

  /// Appends every legal move (packed) to [out].
  ///
  /// Pseudo-legal generation, then each move is made and kept only if the
  /// mover's king is not attacked afterwards (FIDE 3.9.2) — which handles
  /// pins, discovered checks and the en-passant capture that uncovers a rank
  /// in one test.
  void legalMoves(List<int> out) {
    final start = out.length;
    _pseudoLegal(out);
    final mover = side;
    var kept = start;
    for (var i = start; i < out.length; i++) {
      final move = out[i];
      make(move);
      if (!isAttacked(kingSquare(mover), mover ^ 1)) out[kept++] = move;
      unmake();
    }
    out.length = kept;
  }

  void _pseudoLegal(List<int> out) {
    final us = side, them = side ^ 1;
    final base = us * 6;
    final own = occupiedBy[us], enemy = occupiedBy[them];
    final all = own | enemy;

    _pawnMoves(out, us, enemy, all);

    void targets(int from, int reach) {
      // FIDE 3.1: never onto a square of the mover's own piece.
      var bits = reach & ~own;
      while (bits != 0) {
        final to = lowestBit(bits);
        bits &= bits - 1;
        out.add(_pack(from, to, enemy & (1 << to) != 0 ? Move.capture : 0));
      }
    }

    void each(int piece, int Function(int from) reach) {
      var bits = boards[base + piece];
      while (bits != 0) {
        final from = lowestBit(bits);
        bits &= bits - 1;
        targets(from, reach(from));
      }
    }

    each(knight, (from) => knightAttacks[from]);
    each(bishop, (from) => bishopAttacks(from, all));
    each(rook, (from) => rookAttacks(from, all));
    each(queen, (from) => bishopAttacks(from, all) | rookAttacks(from, all));
    each(king, (from) => kingAttacks[from]);
    _castlingMoves(out, us, all);
  }

  void _pawnMoves(List<int> out, int us, int enemy, int all) {
    final forward = us == 0 ? 8 : -8;
    final startRank = us == 0 ? 1 : 6;
    final lastRank = us == 0 ? 7 : 0;

    void add(int from, int to, int flags) {
      if (to >> 3 == lastRank) {
        for (final kind in _promotionKinds) {
          out.add(_pack(from, to, flags, kind));
        }
      } else {
        out.add(_pack(from, to, flags));
      }
    }

    var pawns = boards[us * 6 + pawn];
    while (pawns != 0) {
      final from = lowestBit(pawns);
      pawns &= pawns - 1;
      // FIDE 3.7.1–3.7.2: forward onto empty squares only.
      final one = from + forward;
      if (all & (1 << one) == 0) {
        add(from, one, 0);
        final two = one + forward;
        if (from >> 3 == startRank && all & (1 << two) == 0) {
          out.add(_pack(from, two, Move.doublePush));
        }
      }
      // FIDE 3.7.3: diagonally forward, onto an enemy piece…
      var hits = pawnAttacks[us][from] & enemy;
      while (hits != 0) {
        final to = lowestBit(hits);
        hits &= hits - 1;
        add(from, to, Move.capture);
      }
      // …or onto the square an enemy pawn just passed over (3.7.3.1).
      if (enPassant >= 0 && pawnAttacks[us][from] & (1 << enPassant) != 0) {
        out.add(_pack(from, enPassant, Move.capture | Move.enPassantFlag));
      }
    }
  }

  void _castlingMoves(List<int> out, int us, int all) {
    final rights = us == 0
        ? (_whiteKingside, _whiteQueenside)
        : (_blackKingside, _blackQueenside);
    final home = us == 0 ? 4 : 60;
    // FIDE 3.8.2: rights are trusted only with the king and rook at home.
    if (squares[home] != us * 6 + king) return;
    final rookPiece = us * 6 + rook;
    if (castling & rights.$1 != 0 &&
        squares[home + 3] == rookPiece &&
        all & (1 << (home + 1) | 1 << (home + 2)) == 0 &&
        _castlePathSafe(home, home + 1, home + 2, us ^ 1)) {
      out.add(_pack(home, home + 2, Move.castling));
    }
    if (castling & rights.$2 != 0 &&
        squares[home - 4] == rookPiece &&
        all & (1 << (home - 1) | 1 << (home - 2) | 1 << (home - 3)) == 0 &&
        _castlePathSafe(home, home - 1, home - 2, us ^ 1)) {
      out.add(_pack(home, home - 2, Move.castling));
    }
  }

  /// FIDE 3.8.2.2: not out of check, not across an attacked square, not into
  /// check.
  bool _castlePathSafe(int from, int crossed, int to, int by) =>
      !isAttacked(from, by) && !isAttacked(crossed, by) && !isAttacked(to, by);

  void _put(int piece, int square) {
    final bit = 1 << square;
    _baseKey ^= pieceKey(piece, square);
    boards[piece] |= bit;
    occupiedBy[piece ~/ 6] |= bit;
    squares[square] = piece;
  }

  void _remove(int piece, int square) {
    final bit = 1 << square;
    _baseKey ^= pieceKey(piece, square);
    boards[piece] &= ~bit;
    occupiedBy[piece ~/ 6] &= ~bit;
    squares[square] = -1;
  }

  /// Plays [move] (packed), which must be pseudo-legal here.
  void make(int move) {
    final from = move & 63, to = (move >> 6) & 63;
    final promotion = (move >> 12) & 7;
    final piece = squares[from];
    final captureSquare = move & Move.enPassantFlag != 0
        ? (side == 0 ? to - 8 : to + 8)
        : to;
    final captured = squares[captureSquare];

    _history
      ..add(move)
      ..add(
        (captured + 1) |
            castling << 4 |
            (enPassant + 1) << 8 |
            halfmoveClock << 15,
      );

    if (captured >= 0) _remove(captured, captureSquare);
    _remove(piece, from);
    _put(promotion == 0 ? piece : side * 6 + promotion, to);
    if (move & Move.castling != 0) {
      final rookPiece = side * 6 + rook;
      final (rookFrom, rookTo) = to > from
          ? (from + 3, from + 1)
          : (from - 4, from - 1);
      _remove(rookPiece, rookFrom);
      _put(rookPiece, rookTo);
    }

    final rights = castling & _rightsKept[from] & _rightsKept[to];
    _baseKey ^= castlingKey[castling] ^ castlingKey[rights];
    castling = rights;
    enPassant = move & Move.doublePush != 0 ? (from + to) >> 1 : -1;
    halfmoveClock = piece % 6 == pawn || captured >= 0 ? 0 : halfmoveClock + 1;
    if (side == 1) fullmoveNumber++;
    side ^= 1;
    _baseKey ^= zobristKeys[zobristSide];
  }

  /// Takes back the last [make].
  void unmake() {
    final undo = _history.removeLast();
    final move = _history.removeLast();
    side ^= 1;
    _baseKey ^= zobristKeys[zobristSide];
    if (side == 1) fullmoveNumber--;
    final from = move & 63, to = (move >> 6) & 63;
    final promotion = (move >> 12) & 7;
    final moved = squares[to];
    final piece = promotion == 0 ? moved : side * 6 + pawn;

    if (move & Move.castling != 0) {
      final rookPiece = side * 6 + rook;
      final (rookFrom, rookTo) = to > from
          ? (from + 3, from + 1)
          : (from - 4, from - 1);
      _remove(rookPiece, rookTo);
      _put(rookPiece, rookFrom);
    }
    _remove(moved, to);
    _put(piece, from);
    final captured = (undo & 15) - 1;
    if (captured >= 0) {
      final captureSquare = move & Move.enPassantFlag != 0
          ? (side == 0 ? to - 8 : to + 8)
          : to;
      _put(captured, captureSquare);
    }
    final rights = (undo >> 4) & 15;
    _baseKey ^= castlingKey[castling] ^ castlingKey[rights];
    castling = rights;
    enPassant = ((undo >> 8) & 127) - 1;
    halfmoveClock = undo >> 15;
  }
}
