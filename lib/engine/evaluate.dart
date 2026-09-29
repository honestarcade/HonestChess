/// Static evaluation: how good a position looks without searching it.
///
/// Material and piece-square tables, blended between a middlegame and an
/// endgame score by how much material is left (a "tapered" evaluation),
/// plus a few pawn-structure and rook terms. Every value below was written
/// for this project from general chess principles — centralise knights,
/// keep the king sheltered until the endgame and then bring it to the
/// centre, push passed pawns — rather than copied from a published engine:
/// the PeSTO tables carry no explicit licence (#66's plan, /n8-plan M2,
/// 2026-09-28). Tuning them is left to the strength ladder; the search's
/// correctness does not depend on any particular value.
///
/// No term reads a clock or a random number, so the same position always
/// gets the same score.
library;

import 'position.dart';
import 'src/board.dart';
import 'src/tables.dart';

/// Material in centipawns, middlegame then endgame, by kind (pawn … king).
const List<int> materialMg = [90, 320, 335, 470, 960, 0];
const List<int> materialEg = [115, 300, 320, 520, 950, 0];

/// How much each kind counts towards the game phase: 24 with every piece on
/// the board (pure middlegame), 0 with only kings and pawns (pure endgame).
const List<int> _phaseWeight = [0, 1, 1, 2, 4, 0];
const int _fullPhase = 24;

// The tables are written as a board is drawn — rank 8 on the first row, a
// file on the left — from White's side; Black uses them mirrored. Values are
// centipawns added to the piece's material.

const List<int> _pawnMg = [
  0, 0, 0, 0, 0, 0, 0, 0, //
  60, 65, 65, 70, 70, 65, 65, 60,
  25, 30, 35, 45, 45, 35, 30, 25,
  8, 10, 16, 28, 28, 16, 10, 8,
  2, 4, 10, 22, 22, 8, 4, 2,
  2, 6, 4, 8, 8, -2, 6, 2,
  0, 4, 4, -12, -12, 6, 6, 0,
  0, 0, 0, 0, 0, 0, 0, 0,
];

const List<int> _pawnEg = [
  0, 0, 0, 0, 0, 0, 0, 0, //
  70, 70, 66, 62, 62, 66, 70, 70,
  40, 40, 36, 32, 32, 36, 40, 40,
  20, 20, 16, 14, 14, 16, 20, 20,
  10, 9, 6, 4, 4, 6, 9, 10,
  3, 3, 0, 0, 0, 0, 3, 3,
  0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0,
];

const List<int> _knightMg = [
  -60, -30, -25, -20, -20, -25, -30, -60, //
  -30, -15, 0, 5, 5, 0, -15, -30,
  -20, 5, 15, 20, 20, 15, 5, -20,
  -15, 8, 18, 26, 26, 18, 8, -15,
  -15, 4, 16, 22, 22, 16, 4, -15,
  -20, 2, 12, 12, 12, 12, 2, -20,
  -30, -15, 0, 4, 4, 0, -15, -30,
  -55, -25, -20, -18, -18, -20, -25, -55,
];

const List<int> _knightEg = [
  -50, -35, -25, -20, -20, -25, -35, -50, //
  -35, -15, -5, 0, 0, -5, -15, -35,
  -25, -5, 8, 12, 12, 8, -5, -25,
  -20, 0, 12, 18, 18, 12, 0, -20,
  -20, 0, 12, 18, 18, 12, 0, -20,
  -25, -5, 8, 12, 12, 8, -5, -25,
  -35, -15, -5, 0, 0, -5, -15, -35,
  -50, -35, -25, -20, -20, -25, -35, -50,
];

const List<int> _bishopMg = [
  -18, -8, -10, -12, -12, -10, -8, -18, //
  -8, 4, 2, 0, 0, 2, 4, -8,
  -6, 6, 10, 10, 10, 10, 6, -6,
  -4, 10, 8, 14, 14, 8, 10, -4,
  -4, 6, 12, 14, 14, 12, 6, -4,
  -2, 10, 10, 8, 8, 10, 10, -2,
  -6, 14, 6, 6, 6, 6, 14, -6,
  -16, -6, -12, -8, -8, -12, -6, -16,
];

const List<int> _bishopEg = [
  -14, -8, -6, -4, -4, -6, -8, -14, //
  -8, -2, 0, 2, 2, 0, -2, -8,
  -6, 0, 6, 8, 8, 6, 0, -6,
  -4, 2, 8, 10, 10, 8, 2, -4,
  -4, 2, 8, 10, 10, 8, 2, -4,
  -6, 0, 6, 8, 8, 6, 0, -6,
  -8, -2, 0, 2, 2, 0, -2, -8,
  -14, -8, -6, -4, -4, -6, -8, -14,
];

const List<int> _rookMg = [
  6, 6, 8, 10, 10, 8, 6, 6, //
  16, 20, 20, 22, 22, 20, 20, 16,
  -4, 2, 4, 4, 4, 4, 2, -4,
  -8, -2, 0, 2, 2, 0, -2, -8,
  -10, -4, -2, 0, 0, -2, -4, -10,
  -12, -6, -4, -2, -2, -4, -6, -12,
  -14, -8, -4, -2, -2, -4, -8, -18,
  -6, -2, 4, 10, 10, 6, -4, -6,
];

const List<int> _rookEg = [
  6, 6, 6, 6, 6, 6, 6, 6, //
  12, 12, 12, 12, 12, 12, 12, 12,
  2, 2, 2, 2, 2, 2, 2, 2,
  0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0,
  -2, -2, -2, -2, -2, -2, -2, -2,
  -4, -4, -4, -4, -4, -4, -4, -4,
  -4, -2, 0, 2, 2, 0, -2, -4,
];

const List<int> _queenMg = [
  -20, -10, -8, -4, -4, -8, -10, -20, //
  -12, -6, 0, 2, 2, 0, -6, -12,
  -8, 0, 4, 4, 4, 4, 0, -8,
  -4, 0, 4, 4, 4, 4, 0, -4,
  -4, 0, 4, 4, 4, 4, 0, -4,
  -8, 2, 4, 4, 4, 4, 0, -8,
  -12, 0, 2, 0, 0, 0, 0, -12,
  -20, -10, -8, 0, -4, -8, -10, -20,
];

const List<int> _queenEg = [
  -24, -16, -10, -8, -8, -10, -16, -24, //
  -16, -6, 0, 4, 4, 0, -6, -16,
  -10, 0, 8, 12, 12, 8, 0, -10,
  -8, 4, 12, 16, 16, 12, 4, -8,
  -8, 4, 12, 16, 16, 12, 4, -8,
  -10, 0, 8, 12, 12, 8, 0, -10,
  -16, -6, 0, 4, 4, 0, -6, -16,
  -24, -16, -10, -8, -8, -10, -16, -24,
];

const List<int> _kingMg = [
  -40, -45, -45, -50, -50, -45, -45, -40, //
  -40, -45, -45, -50, -50, -45, -45, -40,
  -40, -45, -45, -50, -50, -45, -45, -40,
  -40, -45, -45, -50, -50, -45, -45, -40,
  -30, -35, -35, -40, -40, -35, -35, -30,
  -15, -20, -20, -25, -25, -20, -20, -15,
  8, 8, -6, -12, -12, -6, 8, 8,
  18, 28, 12, -4, 0, 8, 30, 20,
];

const List<int> _kingEg = [
  -45, -30, -24, -18, -18, -24, -30, -45, //
  -28, -10, -4, 0, 0, -4, -10, -28,
  -22, -4, 10, 16, 16, 10, -4, -22,
  -18, 0, 16, 24, 24, 16, 0, -18,
  -18, 0, 16, 24, 24, 16, 0, -18,
  -22, -4, 10, 16, 16, 10, -4, -22,
  -30, -14, -4, 0, 0, -4, -14, -30,
  -50, -34, -26, -20, -20, -26, -34, -50,
];

const _tablesMg = [
  _pawnMg, _knightMg, _bishopMg, _rookMg, _queenMg, _kingMg, //
];
const _tablesEg = [
  _pawnEg, _knightEg, _bishopEg, _rookEg, _queenEg, _kingEg, //
];

/// `_mg[piece * 64 + square]`: material plus table value for that piece on
/// that square, from White's point of view (Black's entries negated), so
/// the evaluation is one sum. [_eg] likewise.
final List<int> _mg = _combined(_tablesMg, materialMg);
final List<int> _eg = _combined(_tablesEg, materialEg);

List<int> _combined(List<List<int>> tables, List<int> material) => [
  for (var piece = 0; piece < 12; piece++)
    for (var square = 0; square < 64; square++)
      piece < 6
          // White: the drawn row for rank r is row 7 - r.
          ? material[piece] + tables[piece][square ^ 56]
          // Black, mirrored: its rank r reads White's row r.
          : -(material[piece - 6] + tables[piece - 6][square]),
];

const int _bishopPairMg = 30, _bishopPairEg = 50;
const int _doubledMg = -10, _doubledEg = -22;
const int _isolatedMg = -10, _isolatedEg = -14;
const int _openFileMg = 22, _openFileEg = 8;
const int _halfOpenFileMg = 10, _halfOpenFileEg = 4;

/// Bonus for a passed pawn by how far it has come (its own rank 1–8, 0 and
/// 7 unused): a pawn nothing can stop grows in value as it nears promotion,
/// much more so once the pieces that could stop it are gone.
const List<int> _passedMg = [0, 2, 6, 12, 22, 38, 60, 0];
const List<int> _passedEg = [0, 8, 14, 26, 44, 70, 105, 0];

final List<int> _fileMask = [
  for (var f = 0; f < 8; f++) 0x0101010101010101 << f,
];

final List<int> _adjacentFiles = [
  for (var f = 0; f < 8; f++)
    (f > 0 ? _fileMask[f - 1] : 0) | (f < 7 ? _fileMask[f + 1] : 0),
];

/// `_passedMask[colour][square]`: the squares ahead of a pawn on [square],
/// on its own and both adjacent files, that an enemy pawn must occupy to
/// stop it being passed.
final List<List<int>> _passedMask = [
  for (var colour = 0; colour < 2; colour++)
    [
      for (var sq = 0; sq < 64; sq++)
        () {
          final files = _fileMask[sq & 7] | _adjacentFiles[sq & 7];
          final rank = sq >> 3;
          var ahead = 0;
          for (var r = 0; r < 8; r++) {
            if (colour == 0 ? r > rank : r < rank) ahead |= 0xff << (r * 8);
          }
          return files & ahead;
        }(),
    ],
];

int _popCount(int bits) {
  var n = 0;
  for (; bits != 0; bits &= bits - 1) {
    n++;
  }
  return n;
}

/// The static evaluation of [position], in centipawns from the point of
/// view of the side to move: positive when that side looks better.
int evaluate(Position position) => evaluateBoard(Board.fromPosition(position));

/// [evaluate] on the search's mutable board.
int evaluateBoard(Board board) {
  final boards = board.boards;
  final squares = board.squares;
  var mg = 0, eg = 0, phase = 0;
  var occupied = board.occupied;
  while (occupied != 0) {
    final square = lowestBit(occupied);
    occupied &= occupied - 1;
    final piece = squares[square];
    final index = piece * 64 + square;
    mg += _mg[index];
    eg += _eg[index];
    phase += _phaseWeight[piece % 6];
  }

  final whitePawns = boards[pawn], blackPawns = boards[6 + pawn];
  for (var colour = 0; colour < 2; colour++) {
    final sign = colour == 0 ? 1 : -1;
    final own = colour == 0 ? whitePawns : blackPawns;
    final enemy = colour == 0 ? blackPawns : whitePawns;
    var termMg = 0, termEg = 0;

    final bishops = boards[colour * 6 + bishop];
    if (bishops & (bishops - 1) != 0) {
      termMg += _bishopPairMg;
      termEg += _bishopPairEg;
    }

    for (var file = 0; file < 8; file++) {
      final count = _popCount(own & _fileMask[file]);
      if (count > 1) {
        termMg += _doubledMg * (count - 1);
        termEg += _doubledEg * (count - 1);
      }
      if (count > 0 && own & _adjacentFiles[file] == 0) {
        termMg += _isolatedMg * count;
        termEg += _isolatedEg * count;
      }
    }

    var pawns = own;
    while (pawns != 0) {
      final square = lowestBit(pawns);
      pawns &= pawns - 1;
      if (_passedMask[colour][square] & enemy == 0) {
        final rank = colour == 0 ? square >> 3 : 7 - (square >> 3);
        termMg += _passedMg[rank];
        termEg += _passedEg[rank];
      }
    }

    var rooks = boards[colour * 6 + rook];
    while (rooks != 0) {
      final file = lowestBit(rooks) & 7;
      rooks &= rooks - 1;
      if (own & _fileMask[file] == 0) {
        if (enemy & _fileMask[file] == 0) {
          termMg += _openFileMg;
          termEg += _openFileEg;
        } else {
          termMg += _halfOpenFileMg;
          termEg += _halfOpenFileEg;
        }
      }
    }

    mg += sign * termMg;
    eg += sign * termEg;
  }

  if (phase > _fullPhase) phase = _fullPhase;
  final score = (mg * phase + eg * (_fullPhase - phase)) ~/ _fullPhase;
  return board.side == 0 ? score : -score;
}
