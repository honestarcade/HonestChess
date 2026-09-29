import 'package:honest_chess/engine/engine.dart';
import 'package:honest_chess/ui/game/labels.dart';

/// The result card's words for one ending: the kicker [tag], the [title]
/// and the [body] sentence explaining the rule. [lost] is true when you
/// lost to the computer, and the kicker turns red.
typedef ResultText = ({String tag, String title, String body, bool lost});

/// Whose view the result takes: against the computer, your colour; between
/// two players, the side to move when the game ended — the side the
/// Resign tool resigns for.
Colour resultYou(Game game) => switch (game.mode) {
  VsComputer(:final playerColour) => playerColour,
  TwoPlayer() => game.sideToMove,
};

/// The card's words for [result], a finished game's [Win] or [Draw], in
/// [mode]; [you] is as [resultYou] gives it, and names the side that
/// resigned in a drawn resignation. Throws an [ArgumentError] for an
/// [Ongoing] result.
ResultText describeResult(GameStatus result, GameMode mode, Colour you) {
  switch (result) {
    case Ongoing():
      throw ArgumentError.value(result, 'result', 'the game is not over');
    case Win(:final winner, :final reason):
      final loser = winner.opponent.label;
      final vsComputer = mode is VsComputer;
      final lost = vsComputer && winner != you;
      final tag = vsComputer
          ? (lost ? 'YOU LOSE' : 'YOU WIN')
          : '${winner.label.toUpperCase()} WINS';
      final (title, body) = switch (reason) {
        GameEndReason.checkmate => (
          '${winner.label} delivers checkmate',
          'The king has no legal square, nothing blocks the check and the '
              'attacker cannot be taken.',
        ),
        GameEndReason.flag => (
          '$loser ran out of time',
          'The clock hit zero with mating material still on the board.',
        ),
        _ => ('$loser resigned', 'Resignation ends the game at once.'),
      };
      return (tag: tag, title: title, body: body, lost: lost);
    case Draw(:final reason):
      final (title, body) = switch (reason) {
        GameEndReason.stalemate => (
          'Stalemate — no legal move',
          'The side to move is not in check but has no legal move at all. '
              'That is a draw, not a win.',
        ),
        GameEndReason.fiftyMoves => (
          'Draw by the fifty-move rule',
          'Fifty moves each with no capture or pawn move — the game is '
              'drawn automatically.',
        ),
        GameEndReason.insufficientMaterial => (
          'Draw — not enough material',
          'Neither side has the material to force mate, so the game is '
              'drawn on the spot.',
        ),
        GameEndReason.threefoldRepetition => (
          'Draw by repetition',
          'The same position came up three times.',
        ),
        GameEndReason.flagNoMatingMaterial => (
          'Flag fell, but no mating material',
          'The clock ran out, but the other side could never have mated. '
              'Drawn.',
        ),
        GameEndReason.resignationNoMatingMaterial => (
          '${you.label} resigned — drawn',
          'The other side had no way left to checkmate, so the game is a '
              'draw.',
        ),
        _ => ('Draw agreed', 'Both players agreed to split the point.'),
      };
      return (tag: 'DRAWN', title: title, body: body, lost: false);
  }
}

/// Whether [game] ended on the board — mate, stalemate or an automatic
/// draw — rather than by resignation, agreement or a flag.
bool endedByMove(Game game) => game.history.last.status.isOver;

/// One of the card's four numbers: its [label] as the tile writes it, its
/// [value], and what a screen reader says for the tile.
typedef ResultStat = ({String label, String value, String spoken});

/// The time control as the CLOCK tile names it: "Rapid 10+5", "Untimed",
/// or "15+10" for a custom control.
String clockName(TimeControl control) => switch (control) {
  Untimed() => 'Untimed',
  final Timed t => [
    if (t.preset case final preset?)
      '${preset.name[0].toUpperCase()}${preset.name.substring(1)}',
    '${t.minutes}+${t.incrementSeconds}',
  ].join(' '),
};

/// The finished [game]'s numbers: MOVES (the moves White made), CAPTURES
/// (both sides, over the moves still in the game's history), LEVEL
/// against the computer or CLOCK between two players, and TIME LEFT —
/// your clock against the computer, else the winner's, or White's on a
/// draw; "—" untimed, 0:00 for a side whose flag fell.
List<ResultStat> resultStats(Game game) {
  final history = game.history;
  var whiteMoves = 0, captures = 0;
  for (var i = 1; i < history.length; i++) {
    if (history[i - 1].position.sideToMove == Colour.white) whiteMoves++;
    if (history[i].move!.isCapture) captures++;
  }
  final (kind, level) = switch (game.mode) {
    VsComputer(:final step) => ('LEVEL', step.label),
    TwoPlayer() => ('CLOCK', clockName(game.clock.control)),
  };
  final timed = switch (game.mode) {
    VsComputer(:final playerColour) => playerColour,
    TwoPlayer() => switch (game.status) {
      Win(:final winner) => winner,
      _ => Colour.white,
    },
  };
  final ms = game.remaining(timed);
  final time = ms == null ? '—' : (ms <= 0 ? '0:00' : clockText(ms));
  String spoken(String label, String value) => '$label, $value';
  return [
    (
      label: 'MOVES',
      value: '$whiteMoves',
      spoken: spoken('Moves', '$whiteMoves'),
    ),
    (
      label: 'CAPTURES',
      value: '$captures',
      spoken: spoken('Captures', '$captures'),
    ),
    (
      label: kind,
      value: level,
      spoken: spoken(kind == 'LEVEL' ? 'Level' : 'Clock', level),
    ),
    (label: 'TIME LEFT', value: time, spoken: clockSemantics('Time left', ms)),
  ];
}
