/// The two sides (FIDE 1.1).
enum Colour {
  white,
  black;

  Colour get opponent => this == white ? black : white;
}

/// The six kinds of piece (FIDE 2.2), each with its FEN letter.
enum PieceKind {
  pawn('p'),
  knight('n'),
  bishop('b'),
  rook('r'),
  queen('q'),
  king('k');

  const PieceKind(this.letter);

  /// The lower-case FEN letter.
  final String letter;
}

/// The twelve pieces: a kind in a colour.
///
/// The declaration order is colour-major (`index == colour.index * 6 +
/// kind.index`), which is what [Piece.of] and the position's bitboard array
/// rely on.
enum Piece {
  whitePawn(Colour.white, PieceKind.pawn),
  whiteKnight(Colour.white, PieceKind.knight),
  whiteBishop(Colour.white, PieceKind.bishop),
  whiteRook(Colour.white, PieceKind.rook),
  whiteQueen(Colour.white, PieceKind.queen),
  whiteKing(Colour.white, PieceKind.king),
  blackPawn(Colour.black, PieceKind.pawn),
  blackKnight(Colour.black, PieceKind.knight),
  blackBishop(Colour.black, PieceKind.bishop),
  blackRook(Colour.black, PieceKind.rook),
  blackQueen(Colour.black, PieceKind.queen),
  blackKing(Colour.black, PieceKind.king);

  const Piece(this.colour, this.kind);

  final Colour colour;
  final PieceKind kind;

  /// The piece of [kind] in [colour].
  static Piece of(Colour colour, PieceKind kind) =>
      values[colour.index * 6 + kind.index];

  /// The FEN letter: upper case for White, lower case for Black.
  String get fenLetter =>
      colour == Colour.white ? kind.letter.toUpperCase() : kind.letter;

  /// The piece a FEN letter names, or null for any other character.
  static Piece? fromFenLetter(String letter) => _byLetter[letter];

  static final Map<String, Piece> _byLetter = {
    for (final p in values) p.fenLetter: p,
  };
}
