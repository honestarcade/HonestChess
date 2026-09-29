import 'attacks.dart';
import 'movegen.dart';
import 'piece.dart';
import 'position.dart';
import 'square.dart';
import 'zobrist.dart';

/// Why a game ended. Every ending of the M2 rule set is listed here, the
/// ones [status] never reports included, so the stories that add
/// resignation, agreement and the clock reuse this enum.
enum GameEndReason {
  /// FIDE 1.4.1, 5.1.1.
  checkmate,

  /// FIDE 5.2.1.
  stalemate,

  /// FIDE 5.2.2, as scoped: neither side has mating material ([canMate]).
  insufficientMaterial,

  /// FIDE 9.2, automatic.
  threefoldRepetition,

  /// FIDE 9.3, automatic.
  fiftyMoves,

  /// FIDE 5.1.2: a player resigned.
  resignation,

  /// A player resigned, but the opponent could not checkmate by any series
  /// of legal moves, so the game is drawn.
  resignationNoMatingMaterial,

  /// FIDE 5.2.3: both players agreed a draw.
  agreement,

  /// FIDE 6.9: a player's flag fell.
  flag,

  /// FIDE 6.9: a flag fell, but the opponent could not checkmate by any
  /// series of legal moves, so the game is drawn.
  flagNoMatingMaterial,
}

/// Where a game stands: still going, won, or drawn.
sealed class GameStatus {
  const GameStatus();

  /// Whether the game has ended.
  bool get isOver => this is! Ongoing;
}

/// The game goes on; [inCheck] says whether the side to move is in check.
final class Ongoing extends GameStatus {
  const Ongoing({required this.inCheck});

  final bool inCheck;

  @override
  bool operator ==(Object other) =>
      other is Ongoing && other.inCheck == inCheck;

  @override
  int get hashCode => inCheck.hashCode;

  @override
  String toString() => 'Ongoing(inCheck: $inCheck)';
}

/// [winner] won, for [reason].
final class Win extends GameStatus {
  const Win(this.winner, this.reason);

  final Colour winner;
  final GameEndReason reason;

  @override
  bool operator ==(Object other) =>
      other is Win && other.winner == winner && other.reason == reason;

  @override
  int get hashCode => Object.hash(winner, reason);

  @override
  String toString() => 'Win(${winner.name}, ${reason.name})';
}

/// The game is drawn, for [reason].
final class Draw extends GameStatus {
  const Draw(this.reason);

  final GameEndReason reason;

  @override
  bool operator ==(Object other) => other is Draw && other.reason == reason;

  @override
  int get hashCode => reason.hashCode;

  @override
  String toString() => 'Draw(${reason.name})';
}

/// The status of the game whose positions, from its start, are [history];
/// the last is the current position.
///
/// In this precedence: checkmate wins for the side that delivered it —
/// even on the move that completes the fifty-move count (FIDE 9.6.2);
/// stalemate draws; insufficient material draws; the third occurrence of
/// the current position (9.2.2, identity per [isSamePosition], the first
/// position in [history] counting as an occurrence) draws; a halfmove
/// clock of 100 or more (9.3) draws. Both draws are automatic, so the
/// fivefold and seventy-five-move rules (9.6) are never reached.
///
/// [history] must be consecutive positions of one game. Throws an
/// [ArgumentError] when it is empty.
GameStatus status(List<Position> history) {
  if (history.isEmpty) {
    throw ArgumentError.value(history, 'history', 'must not be empty');
  }
  final current = history.last;
  final checked = inCheck(current);
  if (legalMoves(current).isEmpty) {
    return checked
        ? Win(current.sideToMove.opponent, GameEndReason.checkmate)
        : const Draw(GameEndReason.stalemate);
  }
  if (!canMate(current, Colour.white) && !canMate(current, Colour.black)) {
    return const Draw(GameEndReason.insufficientMaterial);
  }
  if (_occurrences(history) >= 3) {
    return const Draw(GameEndReason.threefoldRepetition);
  }
  if (current.halfmoveClock >= 100) {
    return const Draw(GameEndReason.fiftyMoves);
  }
  return Ongoing(inCheck: checked);
}

/// How many times the last position of [history] has occurred in it.
///
/// Only positions since the last capture or pawn move can match — both are
/// irreversible — so the scan stops where the halfmove clock was reset.
int _occurrences(List<Position> history) {
  final current = history.last;
  final first = history.length - 1 - current.halfmoveClock;
  var count = 0;
  for (var i = history.length - 1; i >= 0 && i >= first; i--) {
    final earlier = history[i];
    if (earlier.key == current.key && isSamePosition(earlier, current)) {
      count++;
    }
  }
  return count;
}

/// Whether [colour] has material that could checkmate by some series of
/// legal moves, however unlikely (FIDE 5.2.2, 6.9 — as scoped: material
/// only, no fortress detection).
///
/// False only for a bare king; a king and a single knight, or a king and
/// bishops all on one square colour, when the opponent has nothing that
/// could block its own king's flight squares — no pawn, knight, rook or
/// queen, and no bishop on the other square colour. True otherwise: two
/// knights, knight and bishop, or bishops on both colours can all mate.
bool canMate(Position position, Colour colour) {
  int count(Colour c, PieceKind kind) =>
      _popCount(position.bitboard(Piece.of(c, kind)));
  if (count(colour, PieceKind.pawn) +
          count(colour, PieceKind.rook) +
          count(colour, PieceKind.queen) >
      0) {
    return true;
  }
  final knights = count(colour, PieceKind.knight);
  final bishops = position.bitboard(Piece.of(colour, PieceKind.bishop));
  if (knights == 0 && bishops == 0) return false;
  if (knights >= 2 || (knights >= 1 && bishops != 0)) return true;
  final ownColours = _squareColours(bishops);
  if (ownColours == _both) return true;

  final opponent = colour.opponent;
  final canBlock =
      count(opponent, PieceKind.pawn) +
          count(opponent, PieceKind.knight) +
          count(opponent, PieceKind.rook) +
          count(opponent, PieceKind.queen) >
      0;
  if (canBlock) return true;
  final theirBishops = _squareColours(
    position.bitboard(Piece.of(opponent, PieceKind.bishop)),
  );
  if (knights == 1) return theirBishops != 0;
  // Our bishops are all on one colour: only an opposing bishop on the other
  // colour can stand on the flight squares they cannot reach.
  return theirBishops & ~ownColours != 0;
}

const _light = 1, _dark = 2, _both = 3;

/// Which square colours the pieces on [bits] stand on: [_light], [_dark],
/// both, or 0 for none.
int _squareColours(int bits) {
  var colours = 0;
  for (var square = 0; bits != 0; square++, bits >>>= 1) {
    if (bits & 1 != 0) colours |= Square(square).isLight ? _light : _dark;
  }
  return colours;
}

int _popCount(int bits) {
  var n = 0;
  for (; bits != 0; bits &= bits - 1) {
    n++;
  }
  return n;
}
