import 'package:flutter/foundation.dart';

import 'package:honest_chess/engine/engine.dart';
import 'package:honest_chess/ui/board/board_options.dart';

/// A square's background layer, as the design's `hl`: at most one shows,
/// in this order of precedence — the selected piece, a king in check, then
/// the last move.
enum SquareTint { none, selected, check, lastMove }

/// A square's target mark while a piece is selected: a dot for a quiet
/// move, a ring for a capture (en passant: on the square the pawn lands).
enum SquareMark { none, dot, ring }

/// A promotion waiting for its piece: the pawn's move from [from] to [to].
typedef PendingPromotion = ({Square from, Square to});

/// What the play screen draws, derived from the [Game] and the display
/// options. It holds only the highlights that should show: an option that
/// is off has already been applied.
@immutable
final class GameViewState {
  const GameViewState({
    required this.position,
    required this.selection,
    required this.tints,
    required this.marks,
    required this.lastMove,
    required this.pendingPromotion,
    required this.thinking,
    required this.paused,
    required this.over,
  });

  final Position position;

  /// The square of the picked-up piece, or null.
  final Square? selection;

  /// Indexed by [Square.index].
  final List<SquareTint> tints;

  /// Indexed by [Square.index].
  final List<SquareMark> marks;

  /// The move that led to [position], whether or not it is tinted; null at
  /// the start of the game.
  final Move? lastMove;

  final PendingPromotion? pendingPromotion;

  /// The computer is choosing a move.
  final bool thinking;

  final bool paused;

  /// The game has ended.
  final bool over;

  SquareTint tintAt(Square square) => tints[square.index];
  SquareMark markAt(Square square) => marks[square.index];
}

/// The play screen's state over the engine's [Game]: it applies the
/// player's taps and drops as moves, keeps the selection, and derives the
/// board's highlights.
///
/// Every action that is refused — not your turn, an illegal move, the game
/// over or input otherwise locked — is a silent no-op returning `false`;
/// the engine's [GameActionError] never reaches the UI.
class GameController extends ChangeNotifier {
  /// A new game in [mode] under [timeControl], from the start position or
  /// from [fen]. [now] is the clock's time source (default a monotonic
  /// stopwatch); tests pass a fake.
  ///
  /// [thinking] is for tests only, until #75's computer player sets it: it
  /// shows the computer as choosing a move.
  GameController({
    String? fen,
    GameMode mode = const TwoPlayer(),
    TimeControl timeControl = const Untimed(),
    BoardOptions options = const BoardOptions(),
    TimeSource? now,
    this._thinking = false,
  }) : _options = options,
       _game = Game.start(
         mode,
         timeControl,
         options: GameOptions(takebackAllowed: options.takebackAllowed),
         fen: fen,
         time: now,
       ) {
    _refresh();
  }

  Game _game;
  BoardOptions _options;
  final bool _thinking;
  bool _paused = false;
  Square? _selection;
  PendingPromotion? _pendingPromotion;
  late List<Move> _legal;
  late GameViewState _state;

  Game get game => _game;
  GameViewState get state => _state;
  BoardOptions get options => _options;

  /// New display options take effect at once; takeback's setting applies
  /// from the next game, which fixes it at its start.
  set options(BoardOptions value) {
    if (value == _options) return;
    _options = value;
    _state = _viewState();
    notifyListeners();
  }

  /// Whether the board ignores the player entirely: the computer's turn or
  /// its thinking, a pause, a promotion waiting for its piece, or the game
  /// over. Later reasons are added here, not as guards of their own.
  bool get inputLocked =>
      _state.thinking ||
      _state.paused ||
      _state.pendingPromotion != null ||
      _state.over ||
      !_playersTurn;

  bool get _playersTurn => switch (_game.mode) {
    VsComputer(:final playerColour) => _game.sideToMove == playerColour,
    TwoPlayer() => true,
  };

  bool _isMovable(Square square) =>
      _game.position.pieceAt(square)?.colour == _game.sideToMove;

  Iterable<Move> _movesFrom(Square from) => _legal.where((m) => m.from == from);

  bool _isTarget(Square from, Square to) =>
      _movesFrom(from).any((m) => m.to == to);

  /// The design's tap rule. With a piece selected, a tap on one of its
  /// targets plays the move; on the piece itself puts it down; on another
  /// piece of the side to move switches to it; anywhere else clears the
  /// selection. With nothing selected, a tap on a piece of the side to move
  /// picks it up. Returns whether anything changed.
  bool tapSquare(Square square) {
    if (inputLocked) return false;
    final selected = _selection;
    if (selected != null && _isTarget(selected, square)) {
      return move(selected, square);
    }
    final next = _isMovable(square) && square != selected ? square : null;
    if (next == selected) return false;
    _select(next);
    return true;
  }

  /// Whether a drag may start from [square]: input is open and a piece of
  /// the side to move stands there.
  bool canDrag(Square square) => !inputLocked && _isMovable(square);

  /// A drag starts from [square]: the piece is selected (never toggled off,
  /// as a tap would) so its targets show.
  bool pickUp(Square square) {
    if (!canDrag(square)) return false;
    if (_selection != square) _select(square);
    return true;
  }

  /// Whether the piece dragged from [from] may be dropped on [to]: one of
  /// its targets, or its own square. A drag that outlived a position change
  /// no longer owns the selection and is refused.
  bool canDrop(Square from, Square to) =>
      !inputLocked && _selection == from && (to == from || _isTarget(from, to));

  /// The piece dragged from [from] is dropped on [to], or off the board
  /// when [to] is null. A drop on a target plays the move; on its own
  /// square keeps the selection; anywhere else clears it. Returns whether a
  /// move was played or a promotion opened.
  bool drop(Square from, Square? to) {
    if (to != null && canDrop(from, to)) {
      return to == from ? false : move(from, to);
    }
    if (!inputLocked && _selection != null) _select(null);
    return false;
  }

  /// Plays the legal move from [from] to [to]. A pawn reaching its last
  /// rank becomes a queen at once when [BoardOptions.autoQueen] is on;
  /// otherwise it opens a pending promotion, the pawn still selected on its
  /// square, and waits for [choosePromotion] or [cancelPromotion].
  bool move(Square from, Square to) {
    if (inputLocked) return false;
    final moves = [
      for (final m in _movesFrom(from))
        if (m.to == to) m,
    ];
    if (moves.isEmpty) return false;
    if (moves.first.promotion != null) {
      if (_options.autoQueen) {
        return _play(moves.firstWhere((m) => m.promotion == PieceKind.queen));
      }
      _selection = from;
      _pendingPromotion = (from: from, to: to);
      _state = _viewState();
      notifyListeners();
      return true;
    }
    return _play(moves.single);
  }

  /// Completes the pending promotion with [kind]. Refused when nothing is
  /// pending or [kind] is not a piece a pawn can become. The mover's clock
  /// ran all the while the choice was open.
  bool choosePromotion(PieceKind kind) {
    final pending = _pendingPromotion;
    if (pending == null || _state.thinking || _state.paused || _state.over) {
      return false;
    }
    for (final m in _movesFrom(pending.from)) {
      if (m.to == pending.to && m.promotion == kind) return _play(m);
    }
    return false;
  }

  /// Drops the pending promotion: the pawn stays where it was, put down,
  /// and it is still the same side's move.
  bool cancelPromotion() {
    if (_pendingPromotion == null) return false;
    _pendingPromotion = null;
    _select(null);
    return true;
  }

  /// [side]'s time left now; null in an untimed game.
  Duration? remaining(Colour side) {
    final ms = _game.remaining(side);
    return ms == null ? null : Duration(milliseconds: ms);
  }

  /// Whether [side]'s clock is counting down: a timed game under way (from
  /// White's first move), not paused, not over, and [side] to move.
  bool clockRunning(Colour side) {
    final clock = _game.clock;
    return clock.control is Timed &&
        clock.phase == ClockPhase.running &&
        clock.runningSide == side;
  }

  /// Ends the game on time if the running clock has reached zero; the
  /// panels' ticker calls it every frame. Returns whether the game ended.
  bool checkFlag() {
    if (_game.isOver) return false;
    final next = _game.flag();
    if (identical(next, _game)) return false;
    _game = next;
    _refresh();
    notifyListeners();
    return true;
  }

  /// Holds both clocks and locks the board; a pending promotion is dropped.
  /// Refused once the game is over or while already paused.
  bool pause() {
    if (_paused || _game.isOver) return false;
    _paused = true;
    _game = _game.pause();
    _refresh();
    notifyListeners();
    return true;
  }

  /// Restarts the clock that was running when [pause] held it.
  bool resume() {
    if (!_paused) return false;
    _paused = false;
    _game = _game.resume();
    _refresh();
    notifyListeners();
    return true;
  }

  /// Plays [move]. When a flag fell before it, the game the engine hands
  /// back is the flag-ended one without the move: it is taken, and the move
  /// counts as refused.
  bool _play(Move move) {
    final Game next;
    try {
      next = _game.play(move);
    } on GameActionError {
      return false;
    }
    final played = next.history.length > _game.history.length;
    _game = next;
    _refresh();
    notifyListeners();
    return played;
  }

  void _select(Square? square) {
    _selection = square;
    _state = _viewState();
    notifyListeners();
  }

  /// Re-derives everything after the game changed: any position change
  /// drops the selection and a pending promotion.
  void _refresh() {
    _selection = null;
    _pendingPromotion = null;
    _legal = _game.isOver ? const [] : legalMoves(_game.position);
    _state = _viewState();
  }

  GameViewState _viewState() {
    final position = _game.position;
    final tints = List.filled(64, SquareTint.none);
    final marks = List.filled(64, SquareMark.none);
    final lastMove = _game.history.last.move;
    if (lastMove != null && _options.lastMoveHighlight) {
      tints[lastMove.from.index] = SquareTint.lastMove;
      tints[lastMove.to.index] = SquareTint.lastMove;
    }
    if (_options.flagCheck && inCheck(position)) {
      tints[position.kingSquare(position.sideToMove).index] = SquareTint.check;
    }
    final selected = _selection;
    if (selected != null) {
      tints[selected.index] = SquareTint.selected;
      if (_options.legalMoveDots) {
        for (final m in _movesFrom(selected)) {
          marks[m.to.index] = m.isCapture ? SquareMark.ring : SquareMark.dot;
        }
      }
    }
    return GameViewState(
      position: position,
      selection: selected,
      tints: List.unmodifiable(tints),
      marks: List.unmodifiable(marks),
      lastMove: lastMove,
      pendingPromotion: _pendingPromotion,
      thinking: _thinking,
      paused: _paused,
      over: _game.isOver,
    );
  }
}
