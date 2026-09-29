/// Precomputed attack tables and the bit tricks the move generator runs on.
///
/// Library-private to the engine: squares are plain ints (a1 = 0 … h8 = 63),
/// colours are 0 (White) and 1 (Black), and a piece is its `Piece.index`
/// (`colour * 6 + kind`), so the hot loops never box a value.
library;

const int pawn = 0, knight = 1, bishop = 2, rook = 3, queen = 4, king = 5;

/// The index of the lowest set bit of a non-zero [bits].
///
/// Dart ints are 64-bit two's complement, so bit 63 is the sign bit: its
/// isolated value is negative and its `bitLength` does not name it.
int lowestBit(int bits) {
  final low = bits & -bits;
  return low < 0 ? 63 : low.bitLength - 1;
}

/// The index of the highest set bit of a non-zero [bits].
int highestBit(int bits) => bits < 0 ? 63 : bits.bitLength - 1;

/// Squares a knight on each square reaches.
final List<int> knightAttacks = _stepTable(const [
  (1, 2), (2, 1), (2, -1), (1, -2), (-1, -2), (-2, -1), (-2, 1), (-1, 2), //
]);

/// Squares a king on each square reaches.
final List<int> kingAttacks = _stepTable(const [
  (1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1), //
]);

/// `pawnAttacks[colour][square]`: the two diagonal-forward squares a pawn of
/// that colour on that square attacks (FIDE 3.7.3).
final List<List<int>> pawnAttacks = [
  _stepTable(const [(-1, 1), (1, 1)]),
  _stepTable(const [(-1, -1), (1, -1)]),
];

/// The eight ray directions as (file, rank) steps. The first four run
/// towards higher square indices, so their nearest blocker is the lowest set
/// bit; the last four run towards lower indices, nearest blocker highest.
const _directions = [
  (0, 1), (1, 1), (1, 0), (-1, 1), // N, NE, E, NW
  (0, -1), (-1, -1), (-1, 0), (1, -1), // S, SW, W, SE
];
const _rookDirections = [0, 2, 4, 6];
const _bishopDirections = [1, 3, 5, 7];

/// `rays[direction][square]`: every square from (not including) the square
/// to the board edge in that direction.
final List<List<int>> rays = [
  for (final (df, dr) in _directions)
    [
      for (var sq = 0; sq < 64; sq++)
        () {
          var bits = 0;
          for (
            var f = (sq & 7) + df, r = (sq >> 3) + dr;
            f >= 0 && f < 8 && r >= 0 && r < 8;
            f += df, r += dr
          ) {
            bits |= 1 << (r * 8 + f);
          }
          return bits;
        }(),
    ],
];

List<int> _stepTable(List<(int, int)> steps) => [
  for (var sq = 0; sq < 64; sq++)
    () {
      var bits = 0;
      for (final (df, dr) in steps) {
        final f = (sq & 7) + df, r = (sq >> 3) + dr;
        if (f >= 0 && f < 8 && r >= 0 && r < 8) bits |= 1 << (r * 8 + f);
      }
      return bits;
    }(),
];

/// The squares a slider on [square] reaches along [direction], stopping at
/// (and including) the first occupied square (FIDE 3.5).
int _ray(int direction, int square, int occupied) {
  var attacks = rays[direction][square];
  final blockers = attacks & occupied;
  if (blockers != 0) {
    final first = direction < 4 ? lowestBit(blockers) : highestBit(blockers);
    attacks ^= rays[direction][first];
  }
  return attacks;
}

/// The squares a rook on [square] reaches (FIDE 3.3).
int rookAttacks(int square, int occupied) {
  var bits = 0;
  for (final d in _rookDirections) {
    bits |= _ray(d, square, occupied);
  }
  return bits;
}

/// The squares a bishop on [square] reaches (FIDE 3.2).
int bishopAttacks(int square, int occupied) {
  var bits = 0;
  for (final d in _bishopDirections) {
    bits |= _ray(d, square, occupied);
  }
  return bits;
}

/// Whether any piece of colour [by] attacks [square], given the twelve piece
/// [boards] and the [occupied] squares (FIDE 3.1.2).
///
/// It asks which pieces could reach [square] by looking outward from it with
/// each piece's own movement, so a pinned piece counts like any other
/// (FIDE 3.9.1): pins restrict moving, not attacking.
bool squareAttacked(int square, int by, List<int> boards, int occupied) {
  final base = by * 6;
  // A pawn of [by] attacks [square] exactly when a pawn of the other colour
  // on [square] would attack the pawn's square.
  if (pawnAttacks[by ^ 1][square] & boards[base + pawn] != 0) return true;
  if (knightAttacks[square] & boards[base + knight] != 0) return true;
  if (kingAttacks[square] & boards[base + king] != 0) return true;
  final queens = boards[base + queen];
  if (bishopAttacks(square, occupied) & (boards[base + bishop] | queens) != 0) {
    return true;
  }
  return rookAttacks(square, occupied) & (boards[base + rook] | queens) != 0;
}
