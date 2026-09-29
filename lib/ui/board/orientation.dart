import '../../engine/engine.dart';

/// The side drawn at the bottom of the board.
///
/// Against the computer the player's side is always at the bottom. Two
/// players keep White at the bottom unless [rotate] ("rotate board each
/// turn") is on, when the board faces [sideToMove].
Colour boardBottom(GameMode mode, Colour sideToMove, {required bool rotate}) =>
    switch (mode) {
      VsComputer(:final playerColour) => playerColour,
      TwoPlayer() => rotate ? sideToMove : Colour.white,
    };

/// [boardBottom] for [game], except that a game ended by its last move
/// keeps facing the side that made it: the board does not turn to the
/// loser of a checkmate. A takeback lands on an ongoing game, so the board
/// follows the side to move again.
Colour boardBottomOf(Game game, {required bool rotate}) {
  final endedByMove =
      game.isOver && game.history.length > 1 && game.history.last.status.isOver;
  final facing = endedByMove ? game.sideToMove.opponent : game.sideToMove;
  return boardBottom(game.mode, facing, rotate: rotate);
}
