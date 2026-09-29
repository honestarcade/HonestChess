import '../../engine/engine.dart';

/// How to play's title and its two tabs' labels.
const howToTitle = 'How to play';
const piecesTabLabel = 'The pieces';
const rulesTabLabel = 'The rules';

/// The kicker over the gesture rows.
const gesturesKicker = 'GESTURES';

/// One card: an upper-case [tag] and its [body].
typedef RuleText = ({String tag, String body});

/// How each piece moves, in the order the cards show them.
const Map<PieceKind, ({String name, String body})> pieceRules = {
  PieceKind.king: (
    name: 'King',
    body:
        'One square in any direction. Castles once per game with an unmoved '
        'rook, if nothing is between them and the king passes through no '
        'attacked square.',
  ),
  PieceKind.queen: (
    name: 'Queen',
    body:
        'Any distance along a rank, file or diagonal, until something blocks '
        'it.',
  ),
  PieceKind.rook: (
    name: 'Rook',
    body:
        'Any distance along a rank or file. Both rooks take part in '
        'castling.',
  ),
  PieceKind.bishop: (
    name: 'Bishop',
    body: 'Any distance diagonally. It never leaves the colour it started on.',
  ),
  PieceKind.knight: (
    name: 'Knight',
    body:
        'Two squares one way, one the other. The only piece that jumps over '
        'others.',
  ),
  PieceKind.pawn: (
    name: 'Pawn',
    body:
        'One square forward, or two from its starting rank. Captures '
        'diagonally, takes en passant, and promotes to any piece on the last '
        'rank.',
  ),
};

/// The rules that matter in this app, in display order.
const List<RuleText> ruleCards = [
  (
    tag: 'THE GOAL',
    body:
        'Trap the enemy king so that every square it could move to is '
        'attacked and nothing can block or capture the attacker. That is '
        'checkmate, and the game ends there.',
  ),
  (
    tag: 'CHECK',
    body:
        'A king under attack must be dealt with immediately — move it, block '
        'the line, or take the attacker. You may never leave your own king in '
        'check, so some legal-looking moves are not offered.',
  ),
  (
    tag: 'DRAWS',
    body:
        'Stalemate — no legal move but no check — is a draw. So are the same '
        'position three times, fifty moves each without a capture or a pawn '
        'move, and positions where neither side has enough material to mate. '
        'Each of these ends the game automatically.',
  ),
  (
    tag: 'THE CLOCK',
    body:
        'If a clock runs out, that side loses — unless the other side has no '
        'mating material, in which case it is a draw. The clocks start after '
        "White's first move, and the increment is added after each completed "
        'move from then on.',
  ),
  (
    tag: 'TAKEBACK',
    body:
        'Against the computer a takeback undoes both its reply and your move, '
        'so it is your turn again. In two-player either player can undo the '
        'last move.',
  ),
];

/// The gestures, chip first, in display order.
const List<RuleText> gestures = [
  (
    tag: 'TAP',
    body:
        'Tap a piece to pick it up, then tap one of its squares to move it — '
        'dotted when legal-move dots are on.',
  ),
  (tag: 'TAP AGAIN', body: 'Tap the same piece to put it down without moving.'),
  (
    tag: 'TAP KING',
    body: 'Select the king and tap two squares along to castle.',
  ),
  (
    tag: 'DRAG',
    body: 'Drag a piece to one of its squares; an illegal drop springs back.',
  ),
  (
    tag: 'UNDO',
    body: 'Takes back the last move — against the computer, its reply too.',
  ),
  (
    tag: 'PAUSE',
    body: 'Pause holds the clocks and hides nothing — the board stays visible.',
  ),
];
