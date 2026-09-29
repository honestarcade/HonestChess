import 'attacks.dart';
import 'piece.dart';
import 'position.dart';
import 'square.dart';

/// The largest halfmove clock or fullmove number a FEN may carry.
const int maxFenCounter = 100000;

final _counter = RegExp(r'^(0|[1-9][0-9]*)$');

/// Parses a strict FEN into a validated [Position].
///
/// Strict means: exactly six fields separated by single spaces with no
/// surrounding whitespace; canonical placement (no adjacent digits, no 0 or
/// 9); `w` or `b`; castling as `-` or a subsequence of `KQkq` in that order;
/// `-` or an en-passant square; counters as plain decimals up to
/// [maxFenCounter], the fullmove number at least 1. The position must also be
/// one a game could reach in the ways checked here (FIDE 3.10.3): one king per
/// colour, no pawn on rank 1 or 8, at most 16 pieces and 8 pawns per side,
/// castling rights only with king and rook at home, an en-passant target just
/// behind a pawn that could have double-pushed, and the side not to move not
/// in check.
///
/// Throws a [FormatException] whose message starts with a stable token
/// (`fen-fields:`, `fen-ranks:`, `fen-rank-length:`, `fen-placement:`,
/// `fen-piece:`, `fen-side:`, `fen-castling:`, `fen-en-passant:`,
/// `fen-counter:`, `fen-kings:`, `fen-pawn-rank:`, `fen-piece-count:`,
/// `fen-check:`) naming the first fault found. It never returns a partial
/// position.
Position parseFen(String fen) {
  final fields = fen.split(' ');
  if (fields.length != 6 || fields.any((f) => f.isEmpty)) {
    throw FormatException(
      'fen-fields: expected six fields separated by single spaces, '
      'with no surrounding whitespace',
      fen,
    );
  }
  final boards = _parsePlacement(fields[0], fen);

  final Colour side = switch (fields[1]) {
    'w' => Colour.white,
    'b' => Colour.black,
    _ => throw FormatException(
      'fen-side: side to move "${fields[1]}" is not w or b',
      fen,
    ),
  };

  final castling = _parseCastling(fields[2], fen);

  Square? enPassant;
  if (fields[3] != '-') {
    try {
      enPassant = Square.parse(fields[3]);
    } on FormatException {
      throw FormatException(
        'fen-en-passant: "${fields[3]}" is neither - nor a square',
        fen,
      );
    }
    // White to move: Black just double-pushed, passing over rank 6.
    final expectedRank = side == Colour.white ? 5 : 2;
    if (enPassant.rank != expectedRank) {
      throw FormatException(
        'fen-en-passant: ${enPassant.name} is not on rank '
        '${expectedRank + 1}, where a double push by the side that just moved '
        'would pass',
        fen,
      );
    }
  }

  final halfmove = _parseCounter(fields[4], 'halfmove clock', fen);
  final fullmove = _parseCounter(fields[5], 'fullmove number', fen);
  if (fullmove < 1) {
    throw FormatException(
      'fen-counter: the fullmove number must be at least 1',
      fen,
    );
  }

  final position = Position.unchecked(
    bitboards: boards,
    sideToMove: side,
    castlingRights: castling,
    enPassant: enPassant,
    halfmoveClock: halfmove,
    fullmoveNumber: fullmove,
  );
  _checkReachable(position, fen);
  return position;
}

List<int> _parsePlacement(String placement, String fen) {
  final ranks = placement.split('/');
  if (ranks.length != 8) {
    throw FormatException(
      'fen-ranks: placement has ${ranks.length} ranks, not 8',
      fen,
    );
  }
  final boards = List<int>.filled(Piece.values.length, 0);
  for (var i = 0; i < 8; i++) {
    final rank = 7 - i; // FEN lists rank 8 first.
    final text = ranks[i];
    var file = 0;
    var lastWasDigit = false;
    for (final char in text.split('')) {
      final digit = int.tryParse(char);
      if (digit != null) {
        if (digit < 1 || digit > 8) {
          throw FormatException(
            'fen-placement: rank ${rank + 1} has the digit $digit; '
            'empty runs are 1–8',
            fen,
          );
        }
        if (lastWasDigit) {
          throw FormatException(
            'fen-placement: rank ${rank + 1} has adjacent digits; '
            'canonical FEN writes one run',
            fen,
          );
        }
        file += digit;
        lastWasDigit = true;
      } else {
        final piece = Piece.fromFenLetter(char);
        if (piece == null) {
          throw FormatException(
            'fen-piece: "$char" on rank ${rank + 1} is not a piece letter '
            '(PNBRQK or pnbrqk)',
            fen,
          );
        }
        if (file < 8) boards[piece.index] |= Square.at(file, rank).bit;
        file++;
        lastWasDigit = false;
      }
      if (file > 8) break;
    }
    if (file != 8) {
      throw FormatException(
        'fen-rank-length: rank ${rank + 1} ("$text") covers '
        '${file > 8 ? 'more than 8' : '$file'} squares, not 8',
        fen,
      );
    }
  }
  return boards;
}

int _parseCastling(String text, String fen) {
  if (text == '-') return Castling.none;
  const letters = {
    'K': Castling.whiteKingside,
    'Q': Castling.whiteQueenside,
    'k': Castling.blackKingside,
    'q': Castling.blackQueenside,
  };
  var mask = 0;
  var last = 0;
  for (final char in text.split('')) {
    final bit = letters[char];
    // Each bit is larger than the one before it in KQkq order, so a
    // repeated or out-of-order letter is one not larger than the last.
    if (bit == null || bit <= last) {
      throw FormatException(
        'fen-castling: "$text" is neither - nor a subsequence of KQkq',
        fen,
      );
    }
    mask |= bit;
    last = bit;
  }
  return mask;
}

int _parseCounter(String text, String name, String fen) {
  final value = _counter.hasMatch(text) && text.length <= 6
      ? int.parse(text)
      : null;
  if (value == null || value > maxFenCounter) {
    throw FormatException(
      'fen-counter: the $name "$text" is not a plain decimal 0–$maxFenCounter',
      fen,
    );
  }
  return value;
}

int _popCount(int bits) {
  var n = 0;
  for (var b = bits; b != 0; b &= b - 1) {
    n++;
  }
  return n;
}

// Rank 1 and rank 8, as bitboards.
const int _rank1 = 0xFF;
const int _rank8 = 0xFF << 56;

void _checkReachable(Position p, String fen) {
  for (final colour in Colour.values) {
    final kings = _popCount(p.bitboard(Piece.of(colour, PieceKind.king)));
    if (kings != 1) {
      throw FormatException(
        'fen-kings: ${colour.name} has $kings kings, not exactly one',
        fen,
      );
    }
  }
  for (final colour in Colour.values) {
    final pawns = p.bitboard(Piece.of(colour, PieceKind.pawn));
    if (pawns & (_rank1 | _rank8) != 0) {
      throw FormatException(
        'fen-pawn-rank: a ${colour.name} pawn stands on rank 1 or 8',
        fen,
      );
    }
  }
  for (final colour in Colour.values) {
    final pieces = _popCount(p.occupiedBy(colour));
    final pawns = _popCount(p.bitboard(Piece.of(colour, PieceKind.pawn)));
    if (pieces > 16 || pawns > 8) {
      throw FormatException(
        'fen-piece-count: ${colour.name} has $pieces pieces and $pawns pawns; '
        'at most 16 and 8',
        fen,
      );
    }
  }
  const homes = [
    (Castling.whiteKingside, Piece.whiteKing, Square.e1, Square.h1, 'K'),
    (Castling.whiteQueenside, Piece.whiteKing, Square.e1, Square.a1, 'Q'),
    (Castling.blackKingside, Piece.blackKing, Square.e8, Square.h8, 'k'),
    (Castling.blackQueenside, Piece.blackKing, Square.e8, Square.a8, 'q'),
  ];
  for (final (bit, king, kingHome, rookHome, letter) in homes) {
    if (p.castlingRights & bit == 0) continue;
    final rook = Piece.of(king.colour, PieceKind.rook);
    if (p.pieceAt(kingHome) != king || p.pieceAt(rookHome) != rook) {
      throw FormatException(
        'fen-castling: right $letter needs the king on ${kingHome.name} and '
        'a rook on ${rookHome.name}',
        fen,
      );
    }
  }
  final ep = p.enPassant;
  if (ep != null) {
    // The side that just moved pushed from `start` over `ep` to `landing`.
    final forward = p.sideToMove == Colour.white ? -8 : 8;
    final start = Square(ep.index - forward);
    final landing = Square(ep.index + forward);
    final pawn = Piece.of(p.sideToMove.opponent, PieceKind.pawn);
    if (p.pieceAt(ep) != null ||
        p.pieceAt(start) != null ||
        p.pieceAt(landing) != pawn) {
      throw FormatException(
        'fen-en-passant: ${ep.name} needs ${start.name} and ${ep.name} empty '
        'and a ${pawn.colour.name} pawn on ${landing.name}',
        fen,
      );
    }
  }
  if (isInCheck(p, p.sideToMove.opponent)) {
    throw FormatException(
      'fen-check: ${p.sideToMove.opponent.name}, not to move, is in check',
      fen,
    );
  }
}

/// [position] as a canonical FEN: the inverse of [parseFen].
String formatFen(Position position) {
  final out = StringBuffer();
  for (var rank = 7; rank >= 0; rank--) {
    var empty = 0;
    for (var file = 0; file < 8; file++) {
      final piece = position.pieceAt(Square.at(file, rank));
      if (piece == null) {
        empty++;
        continue;
      }
      if (empty > 0) out.write(empty);
      empty = 0;
      out.write(piece.fenLetter);
    }
    if (empty > 0) out.write(empty);
    if (rank > 0) out.write('/');
  }
  out.write(position.sideToMove == Colour.white ? ' w ' : ' b ');
  final c = position.castlingRights;
  out.write(
    c == Castling.none
        ? '-'
        : [
            if (c & Castling.whiteKingside != 0) 'K',
            if (c & Castling.whiteQueenside != 0) 'Q',
            if (c & Castling.blackKingside != 0) 'k',
            if (c & Castling.blackQueenside != 0) 'q',
          ].join(),
  );
  out.write(' ${position.enPassant?.name ?? '-'}');
  out.write(' ${position.halfmoveClock} ${position.fullmoveNumber}');
  return out.toString();
}
