/// A square of the board, a1 to h8.
///
/// Backed by an int so that a square costs nothing to store and indexes a
/// bitboard directly: a1 = 0, b1 = 1, … h1 = 7, a2 = 8, … h8 = 63
/// (rank-major, so a square's bit is `1 << index`).
extension type const Square._(int index) {
  /// The square at [index] (0–63).
  factory Square(int index) {
    RangeError.checkValueInInterval(index, 0, 63, 'index');
    return Square._(index);
  }

  /// The square on [file] (0 = a … 7 = h) and [rank] (0 = rank 1 … 7 = rank 8).
  factory Square.at(int file, int rank) {
    RangeError.checkValueInInterval(file, 0, 7, 'file');
    RangeError.checkValueInInterval(rank, 0, 7, 'rank');
    return Square._(rank * 8 + file);
  }

  /// The square named [text] in algebraic notation, `a1` to `h8`.
  ///
  /// Throws a [FormatException] starting `square:` for anything else,
  /// including upper-case files and surrounding whitespace.
  static Square parse(String text) {
    if (text.length != 2) {
      throw FormatException('square: "$text" is not a file a–h and a rank 1–8');
    }
    final file = text.codeUnitAt(0) - 0x61; // 'a'
    final rank = text.codeUnitAt(1) - 0x31; // '1'
    if (file < 0 || file > 7 || rank < 0 || rank > 7) {
      throw FormatException('square: "$text" is not a file a–h and a rank 1–8');
    }
    return Square._(rank * 8 + file);
  }

  /// All 64 squares, a1 first, in index order.
  static final List<Square> values = List.unmodifiable([
    for (var i = 0; i < 64; i++) Square._(i),
  ]);

  static const a1 = Square._(0);
  static const c1 = Square._(2);
  static const e1 = Square._(4);
  static const g1 = Square._(6);
  static const h1 = Square._(7);
  static const a8 = Square._(56);
  static const c8 = Square._(58);
  static const e8 = Square._(60);
  static const g8 = Square._(62);
  static const h8 = Square._(63);

  /// The file, 0 (a) to 7 (h).
  int get file => index & 7;

  /// The rank, 0 (rank 1) to 7 (rank 8).
  int get rank => index >> 3;

  /// This square's bit in a bitboard.
  int get bit => 1 << index;

  /// The algebraic name, e.g. `e4`.
  String get name =>
      String.fromCharCodes([0x61 + file, 0x31 + rank]); // 'a', '1'

  /// FIDE 2.1: h1 is light and colours alternate, so a square is light exactly
  /// when its file and rank indices have different parity.
  bool get isLight => (file + rank).isOdd;

  /// Whether [other] is a different square on the same file (FIDE 2.4).
  bool isSameFile(Square other) => other != this && other.file == file;

  /// Whether [other] is a different square on the same rank (FIDE 2.4).
  bool isSameRank(Square other) => other != this && other.rank == rank;

  /// Whether [other] is a different square on one of this square's two
  /// diagonals (FIDE 2.4): the a1–h8 direction, where file − rank is
  /// constant, or the a8–h1 direction, where file + rank is.
  bool isSameDiagonal(Square other) =>
      other != this &&
      (other.file - other.rank == file - rank ||
          other.file + other.rank == file + rank);
}
