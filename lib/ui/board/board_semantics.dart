/// The board for a screen reader (#102): each square's spoken label, with
/// its piece and every state it is in, and the double-tap that selects and
/// moves exactly as a tap does, speaking what the tap did.
///
/// The spoken states do not follow the visual switches (owner, round two):
/// [SquareStates] derives them from the game and its legal moves, not from
/// the filtered `GameViewState` the board draws.
library;

import 'package:honest_chess/a11y/announcer.dart';
import 'package:honest_chess/a11y/move_speech.dart';
import 'package:honest_chess/engine/engine.dart';
import 'package:honest_chess/ui/board/board_view.dart';
import 'package:honest_chess/ui/game/game_controller.dart';
import 'package:honest_chess/ui/game/labels.dart';

/// A state a square is read out in, in the order the label joins them.
enum SquareState {
  selected('selected'),
  legalMove('legal move'),
  capture('capture'),
  enPassant('can be captured en passant'),
  lastMove('last move'),
  inCheck('in check');

  const SquareState(this.words);

  final String words;
}

/// Every square's states in a game, whatever the display options say: the
/// selected piece and its targets (a capture's, en passant's included, read
/// "capture", and the passed pawn "can be captured en passant"), the last
/// move's two squares, and the king in check.
class SquareStates {
  SquareStates._(this._states);

  /// The states of [game]'s squares with the piece on [selection] picked
  /// up. A finished game has no targets.
  factory SquareStates.of(Game game, Square? selection) {
    final states = List.generate(64, (_) => <SquareState>{});
    final position = game.position;
    if (selection != null) {
      states[selection.index].add(SquareState.selected);
      if (!game.isOver) {
        for (final move in legalMoves(position)) {
          if (move.from != selection) continue;
          states[move.to.index].add(
            move.isCapture ? SquareState.capture : SquareState.legalMove,
          );
          if (move.isEnPassant) {
            final passed = Square.values[move.from.rank * 8 + move.to.file];
            states[passed.index].add(SquareState.enPassant);
          }
        }
      }
    }
    final last = game.history.last.move;
    if (last != null) {
      states[last.from.index].add(SquareState.lastMove);
      states[last.to.index].add(SquareState.lastMove);
    }
    if (inCheck(position)) {
      states[position.kingSquare(position.sideToMove).index].add(
        SquareState.inCheck,
      );
    }
    return SquareStates._(states);
  }

  final List<Set<SquareState>> _states;

  /// [square]'s states, in [SquareState]'s order.
  List<SquareState> at(Square square) => [
    for (final state in SquareState.values)
      if (_states[square.index].contains(state)) state,
  ];
}

/// [square]'s spoken label: its name and piece, then its [states] —
/// "e4, white knight, selected, last move".
String squareSpeech(Square square, Piece? piece, List<SquareState> states) => [
  squareLabel(square, piece),
  for (final state in states) state.words,
].join(', ');

/// The whole board's label: "Chess board, you play White" against the
/// computer, "Chess board, two players, White at the bottom" between two.
String boardLabel(GameMode mode, Colour bottom) => switch (mode) {
  VsComputer(:final playerColour) =>
    'Chess board, you play ${playerColour.label}',
  TwoPlayer() => 'Chess board, two players, ${bottom.label} at the bottom',
};

/// What a double-tap says while the board is locked: the computer choosing
/// its move, a pause or the game over; null for a lock nothing explains
/// (a promotion card waiting, a new game going in).
String? lockedSpeech(GameController controller) {
  final game = controller.game;
  final state = controller.state;
  if (state.over) return gameOverText;
  if (state.paused) return pausedText;
  final mode = game.mode;
  if (mode is VsComputer && game.sideToMove != mode.playerColour) {
    return thinkingSpeech(mode);
  }
  return null;
}

/// What double-tapping [square] would do, as its hint: "move here",
/// "select" or "put down"; null when it would do nothing but speak.
/// [states] are the game's [SquareStates].
String? tapHint(GameController controller, SquareStates states, Square square) {
  if (controller.inputLocked) return null;
  final here = states.at(square);
  if (here.contains(SquareState.selected)) return putDownText;
  if (here.contains(SquareState.legalMove) ||
      here.contains(SquareState.capture)) {
    return 'move here';
  }
  final piece = controller.state.position.pieceAt(square);
  if (piece != null && piece.colour == controller.game.sideToMove) {
    return 'select';
  }
  return null;
}

/// A double-tap on [square]: exactly the board's tap, then what it did in
/// words through [announcer] — "White knight selected", "put down", or,
/// on a locked board, why nothing happened. A move, a refusal and a
/// promotion card are spoken elsewhere: the feedback hub speaks the move
/// and the refusal, and the card reads itself.
void screenReaderTap(
  GameController controller,
  Square square,
  Announcer announcer,
) {
  if (controller.isIdle) return;
  if (controller.inputLocked) {
    final why = lockedSpeech(controller);
    if (why != null) announcer.announce(why);
    return;
  }
  final before = controller.state.selection;
  final plies = controller.game.history.length;
  controller.tapSquare(square);
  if (controller.game.history.length != plies) return;
  final state = controller.state;
  if (state.pendingPromotion != null) return;
  final after = state.selection;
  if (after != null && after != before) {
    announcer.announce(selectedSpeech(state.position.pieceAt(after)!));
  } else if (after == null && before != null && square == before) {
    announcer.announce(putDownText);
  }
}

/// The board's [SquareDescriber] over [controller]: each square's label
/// with its unfiltered states, its hint, and [screenReaderTap] speaking
/// through [announcer].
SquareDescriber describeSquares(
  GameController controller,
  Announcer announcer,
) {
  final states = SquareStates.of(controller.game, controller.state.selection);
  return (square, piece) => SquareSemantics(
    label: squareSpeech(square, piece, states.at(square)),
    onTap: () => screenReaderTap(controller, square, announcer),
    onTapHint: tapHint(controller, states, square),
  );
}
