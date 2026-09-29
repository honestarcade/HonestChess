/// Which one sound a move plays (#96, owner round one: one sound per move,
/// by priority, the computer's moves the same as yours).
library;

import '../engine/engine.dart';
import 'clips.dart';

/// The clip [move] plays, given the game [after] it: the end of the game >
/// check > a capture (en passant included) or castling > any other move.
/// A promotion plays by the same rule; a move that ends the game plays only
/// [Clip.end].
Clip clipFor(Move move, Game after) {
  if (after.isOver) return Clip.end;
  if (inCheck(after.position)) return Clip.check;
  if (move.isCapture || move.isEnPassant) return Clip.capture;
  if (move.isCastling) return Clip.castle;
  return Clip.move;
}
