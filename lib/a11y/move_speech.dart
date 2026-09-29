/// What TalkBack says about the game (#102): a move in words, and the
/// sentences for the game's other changes, the board's refusals and its
/// taps. Pure functions of the game, so every wording is unit-tested; the
/// feedback hub and the board decide when each is spoken. Strings stay
/// English.
library;

import 'package:honest_chess/engine/engine.dart';
import 'package:honest_chess/ui/game/labels.dart';
import 'package:honest_chess/ui/game/player_panel.dart';
import 'package:honest_chess/ui/game/result_text.dart';

/// "White knight", "black pawn": a piece as the spoken text names it.
String pieceWords(Piece piece, {bool capital = true}) =>
    '${capital ? piece.colour.label : piece.colour.name} ${piece.kind.name}';

/// [move], played from [before], without what it did to the other king:
/// "White knight to f3", "White knight takes black pawn on e5", "White pawn
/// takes black pawn en passant on d6", "White castles king side", "White
/// pawn to e8, promotes to queen". The colour is always the subject.
String moveWords(Move move, Position before) {
  final mover = before.pieceAt(move.from);
  if (mover == null) {
    throw ArgumentError.value(move, 'move', 'no piece on ${move.from.name}');
  }
  if (move.isCastling) {
    final wing = move.to.file > move.from.file ? 'king' : 'queen';
    return '${mover.colour.label} castles $wing side';
  }
  final to = move.to.name;
  final String words;
  if (move.isEnPassant) {
    final taken = Piece.of(mover.colour.opponent, PieceKind.pawn);
    words =
        '${pieceWords(mover)} takes ${pieceWords(taken, capital: false)} '
        'en passant on $to';
  } else if (move.isCapture) {
    final taken = before.pieceAt(move.to)!;
    words =
        '${pieceWords(mover)} takes ${pieceWords(taken, capital: false)} '
        'on $to';
  } else {
    words = '${pieceWords(mover)} to $to';
  }
  final promotion = move.promotion;
  return promotion == null ? words : '$words, promotes to ${promotion.name}';
}

/// [move] in words, from [before] to [after], then ", check" when it gives
/// check or ", checkmate" when it mates.
String moveSpeech(Move move, Position before, Position after) {
  final words = moveWords(move, before);
  if (!inCheck(after)) return words;
  return legalMoves(after).isEmpty ? '$words, checkmate' : '$words, check';
}

/// A finished [game]'s result as its card shows it, tag then title: "You
/// win. White delivers checkmate."
String resultSpeech(Game game) {
  final text = describeResult(game.status, game.mode, resultYou(game));
  final tag = text.tag.toLowerCase();
  return '${tag[0].toUpperCase()}${tag.substring(1)}. ${text.title}.';
}

/// Who is playing, as the start of a game says it: "you play White" or
/// "two players".
String _players(GameMode mode) => switch (mode) {
  VsComputer(:final playerColour) => 'you play ${playerColour.label}',
  TwoPlayer() => 'two players',
};

/// A new game going in: "New game, you play Black", or, for Restart and
/// Rematch, "Game restarted, two players".
String startSpeech(Game game, {required bool restart}) =>
    '${restart ? 'Game restarted' : 'New game'}, ${_players(game.mode)}';

/// A saved game back on the board: "Game restored, White to move".
String restoreSpeech(Game game) =>
    'Game restored, ${game.sideToMove.label} to move';

/// A takeback from [before] to [after]: "Took back White knight to f3",
/// naming the earliest move undone — against the computer, your own move,
/// which is yours to play again. Just "Took back" when [before] is unknown.
String takebackSpeech(Game after, Game? before) {
  final kept = after.history.length;
  if (before == null || before.history.length <= kept) return 'Took back';
  final undone = before.history[kept].move!;
  return 'Took back ${moveWords(undone, after.position)}';
}

const pausedText = 'Paused';
const resumedText = 'Resumed';
const gameOverText = 'Game over';

/// Putting the selected piece down.
const putDownText = 'put down';

/// A refused move of a [kind]: "Knight can't move there, put down".
String refusalSpeech(PieceKind kind) =>
    '${kind.name[0].toUpperCase()}${kind.name.substring(1)} '
    "can't move there, $putDownText";

/// Picking up [piece]: "White knight selected".
String selectedSpeech(Piece piece) => '${pieceWords(piece)} selected';

/// The computer choosing its move in [mode]: "Club is thinking".
String thinkingSpeech(VsComputer mode) =>
    '${playerName(mode, mode.playerColour.opponent)} is thinking';
