import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:honest_chess/data/game_event.dart';
import 'package:honest_chess/data/play_mode.dart';
import 'package:honest_chess/data/recorded_state.dart';
import 'package:honest_chess/engine/engine.dart';
import 'package:honest_chess/ui/board/board_options.dart';
import 'package:honest_chess/ui/game/computer_turns.dart';
import 'package:honest_chess/ui/game/defaults.dart';
import 'package:honest_chess/ui/game/refusal.dart';

/// A square's background layer, as the design's `hl`: at most one shows,
/// in this order of precedence — the selected piece, a king in check, then
/// the last move.
enum SquareTint { none, selected, check, lastMove }

/// A square's target mark while a piece is selected: a dot for a quiet
/// move, a ring for a capture (en passant: on the square the pawn lands).
enum SquareMark { none, dot, ring }

/// A promotion waiting for its piece: the pawn's move from [from] to [to].
typedef PendingPromotion = ({Square from, Square to});

/// How long the pause card shows a declined draw before play resumes.
const Duration drawDeclineShown = Duration(seconds: 2);

/// Whether a draw can be offered from the pause card now, or why not.
enum DrawOffer {
  /// The offer can be made.
  open,

  /// Each side has not yet moved once in this game.
  tooEarly,

  /// The computer declined an offer at this move; you must move again.
  afterNextMove,

  /// The computer is considering an offer.
  asking,

  /// The game is over.
  over,
}

/// One step run by [GameController.restart] and [GameController.newGame]
/// before the new game goes in: [outgoing] is the game being replaced,
/// frozen (null while the controller is idle), [outgoingRecorded] its
/// statistics state, and [incoming] the new game's mode.
typedef ReplaceStage = Future<void> Function(
  Game? outgoing,
  RecordedState? outgoingRecorded,
  PlayMode incoming,
);

/// How a finished game is shown: the result [card] over the board, or
/// the final [board] under a slim result bar.
enum ResultView { card, board }

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
    required this.computerFailed,
    required this.paused,
    required this.drawAsking,
    required this.drawDeclined,
    required this.over,
    required this.resultView,
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

  /// It is the computer's turn and it is choosing a move.
  final bool thinking;

  /// The computer could not move this turn; [GameController.retryComputer]
  /// asks again.
  final bool computerFailed;

  final bool paused;

  /// The computer is considering your draw offer.
  final bool drawAsking;

  /// The computer declined your draw offer, and the pause card says so
  /// until play resumes.
  final bool drawDeclined;

  /// The game has ended.
  final bool over;

  /// How the result is shown; null while the game goes on.
  final ResultView? resultView;

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
  /// Against the computer, [computer] builds its opponent for each game;
  /// without it the computer never moves (a board to look at, or a test).
  GameController({
    String? fen,
    GameMode mode = const TwoPlayer(),
    TimeControl timeControl = const Untimed(),
    BoardOptions options = const BoardOptions(),
    TimeSource? now,
    this._computer,
    this._newGameId = newGameId,
  }) : _options = options,
       _seedOverride = null,
       _fen = fen,
       _now = now,
       _current = Game.start(
         mode,
         timeControl,
         options: GameOptions(takebackAllowed: options.takebackAllowed),
         fen: fen,
         time: now,
       ) {
    _recordedState = RecordedState.fresh(_newGameId);
    _turns = _turnsFor(mode);
    _refresh();
  }

  /// A controller with no game yet, as the app root holds it until a game
  /// is started ([newGame]) or restored ([restore]). While idle there is
  /// nothing to show: [game] and [state] throw [StateError], and every
  /// action is refused.
  ///
  /// [newGameId] draws each game's statistics id (default [newGameId]);
  /// tests pass a counter. [seed], when set, is every new game's computer
  /// seed where [newGame] is given none — the device test's fixed seed.
  GameController.idle({
    this._now,
    ComputerFactory? computerFactory,
    this._options = const BoardOptions(),
    this._newGameId = newGameId,
    int? seed,
  }) : _computer = computerFactory,
       _seedOverride = seed;

  final int? _seedOverride;
  String? _fen;
  final String Function() _newGameId;
  final TimeSource? _now;
  final ComputerFactory? _computer;
  Game? _current;
  GameViewState? _view;

  /// Delivered synchronously once each change and its notifyListeners are
  /// done; see [_emit] for events raised during a delivery.
  final _events = StreamController<GameEvent>.broadcast(sync: true);
  final _undelivered = <GameEvent>[];

  /// A broadcast rather than a listenable, so two identical refusals in a
  /// row are each heard.
  final _refusals = StreamController<Refusal>.broadcast(sync: true);
  bool _delivering = false;
  RecordedState? _recordedState;
  final _replaceStages = <ReplaceStage>[];

  /// A [restart] or [newGame] is running its stages; the old game is
  /// frozen until the new one goes in.
  bool _replacing = false;
  BoardOptions _options;
  ComputerTurns? _turns;
  bool _disposed = false;
  bool _paused = false;

  /// The pause was made by leaving the app: a declined draw then leaves
  /// the card up rather than resuming by itself.
  bool _held = false;
  bool _drawAsking = false;
  bool _drawDeclined = false;
  Timer? _declineTimer;

  /// The ply at which the computer last declined a draw; no offer is made
  /// again until the game has moved past it.
  int? _declinedAtPly;
  Square? _selection;
  PendingPromotion? _pendingPromotion;
  ResultView? _resultView;
  List<Move> _legal = const [];

  Game get _game =>
      _current ?? (throw StateError('No game: the controller is idle.'));
  set _game(Game game) => _current = game;
  GameViewState get _state =>
      _view ?? (throw StateError('No game: the controller is idle.'));
  set _state(GameViewState view) => _view = view;

  /// The game on the board; throws [StateError] while [isIdle].
  Game get game => _game;

  /// What the board shows; throws [StateError] while [isIdle].
  GameViewState get state => _state;
  BoardOptions get options => _options;

  /// Whether no game has been started or restored yet.
  bool get isIdle => _current == null;

  /// Every change of game, for the saved games (#81) and statistics (#82).
  Stream<GameEvent> get events => _events.stream;

  /// Every tap or drop the board refused (#97), for the feedback hub.
  Stream<Refusal> get refusals => _refusals.stream;

  /// The statistics' state of the game on the board ([RecordedState]),
  /// carried as a map into every event and saved beside the game; empty
  /// while idle.
  Map<String, Object?> get recorded => _recorded;

  Map<String, Object?> get _recorded => _recordedState?.toJson() ?? const {};

  /// Adds a step that [restart] and [newGame] run, in registration order,
  /// before the new game goes in.
  void addReplaceStage(ReplaceStage stage) => _replaceStages.add(stage);

  void removeReplaceStage(ReplaceStage stage) => _replaceStages.remove(stage);

  /// Marks the game on the board as counted by the statistics, when [id] is
  /// still its id; a game started since is left alone. Raises no event:
  /// the next save carries it.
  void markRecorded(String id) {
    final state = _recordedState;
    if (_disposed || state == null || state.id != id) return;
    _recordedState = state.copyWith(outcome: true);
  }

  /// New display options take effect at once; takeback's setting applies
  /// from the next game, which fixes it at its start.
  set options(BoardOptions value) {
    if (value == _options) return;
    _options = value;
    if (isIdle) return;
    _state = _viewState();
    notifyListeners();
  }

  /// Whether the board ignores the player entirely: the computer's turn or
  /// its thinking, a pause, a promotion waiting for its piece, or the game
  /// over. Later reasons are added here, not as guards of their own.
  bool get inputLocked =>
      isIdle ||
      _replacing ||
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
    if (selected != null && !_isMovable(square)) {
      _refuse(selected, square, RefusalVia.tap);
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
    // Only a drag that still owns the selection was refused; one that
    // outlived a position change, or a lock, just ends.
    if (!inputLocked && _selection == from) _refuse(from, to, RefusalVia.drop);
    if (!inputLocked && _selection != null) _select(null);
    return false;
  }

  /// A drag from [from] ended without being let go (a pointer cancel):
  /// the selection clears as for a drop off the board, and nothing is
  /// refused.
  void abandonDrag(Square from) {
    if (!inputLocked && _selection != null) _select(null);
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
    if (isIdle) return null;
    final ms = _game.remaining(side);
    return ms == null ? null : Duration(milliseconds: ms);
  }

  /// Whether [side]'s clock is counting down: a timed game under way (from
  /// White's first move), not paused, not over, and [side] to move.
  bool clockRunning(Colour side) {
    if (isIdle) return false;
    final clock = _game.clock;
    return clock.control is Timed &&
        clock.phase == ClockPhase.running &&
        clock.runningSide == side;
  }

  /// Ends the game on time if the running clock has reached zero; the
  /// panels' ticker calls it every frame. Returns whether the game ended.
  bool checkFlag() {
    if (isIdle || _replacing || _game.isOver) return false;
    final before = _game;
    final next = _game.flag();
    if (identical(next, _game)) return false;
    _game = next;
    _refresh();
    notifyListeners();
    _announce(before);
    return true;
  }

  /// Holds both clocks and locks the board; a pending promotion is dropped.
  /// Refused once the game is over or while already paused.
  bool pause() {
    if (isIdle || _replacing || _paused || _game.isOver) return false;
    final before = _game;
    _paused = true;
    _game = _game.pause();
    _refresh();
    notifyListeners();
    _announce(before, GamePaused.new);
    return true;
  }

  /// Restarts the clock that was running when [pause] held it. Refused
  /// while the computer considers a draw offer.
  bool resume() {
    if (!_paused || _drawAsking || _replacing) return false;
    final before = _game;
    _endPause();
    // A game left for the menu gets a new computer, with its own step and
    // seed, when it is played on.
    _turns ??= _turnsFor(_game.mode);
    _game = _game.resume();
    _refresh();
    notifyListeners();
    _announce(before, GameResumed.new);
    return true;
  }

  /// The app was left mid-game: pauses it, or, already paused, keeps the
  /// pause card up — a declined draw's message no longer resumes play by
  /// itself. A finished game is left alone. Returns whether this paused
  /// the game.
  bool autoPause() {
    if (isIdle || _replacing || _game.isOver) return false;
    final paused = !_paused && pause();
    _held = true;
    _declineTimer?.cancel();
    _declineTimer = null;
    return paused;
  }

  /// Keeps the pause card up past a declined draw: the "declines — play
  /// on" message and the timer that would resume play both go, so play
  /// resumes only on [resume]. Refused unless paused, and while the
  /// computer considers a draw offer.
  bool keepPaused() {
    if (!_paused || _drawAsking) return false;
    _declineTimer?.cancel();
    _declineTimer = null;
    if (_drawDeclined) {
      _drawDeclined = false;
      _state = _viewState();
      notifyListeners();
    }
    return true;
  }

  /// The board is left for the menu: the computer is stopped for good
  /// (#75's leaving rule) and the game stays as it is. Resuming the game
  /// builds a new computer, as [restore] does.
  void leave() {
    if (_turns == null) return;
    _turns?.dispose();
    _turns = null;
    if (_disposed) return;
    _state = _viewState();
    notifyListeners();
  }

  int get _ply => _game.history.length - 1;

  /// Whether a draw can be offered now, or why not.
  DrawOffer get drawOffer {
    if (isIdle || _game.isOver) return DrawOffer.over;
    if (_drawAsking) return DrawOffer.asking;
    if (!_game.canAgreeDraw) return DrawOffer.tooEarly;
    final declined = _declinedAtPly;
    if (declined != null && _ply <= declined) return DrawOffer.afterNextMove;
    return DrawOffer.open;
  }

  /// Offers a draw from the pause card. Between two players both are at
  /// the device, so the game ends drawn by agreement at once. Against the
  /// computer — whose search the pause has already cancelled — it asks
  /// the computer, which answers honestly (#67): yes ends the game drawn;
  /// no, or an error, is a decline, shown on the card for
  /// [drawDeclineShown] before play resumes, and no offer is made again
  /// until you have moved. Completes with whether the game ended drawn.
  Future<bool> offerDraw() async {
    if (!_paused || _replacing || drawOffer != DrawOffer.open) return false;
    final turns = _turns;
    if (_game.mode is TwoPlayer) return _agreeDraw();
    if (turns == null) return false;
    final asked = _game;
    _drawAsking = true;
    _drawDeclined = false;
    _held = false;
    _state = _viewState();
    notifyListeners();
    bool accepted;
    try {
      accepted = await turns.opponent.acceptsDraw(asked);
    } on Object {
      accepted = false;
    }
    if (_disposed || _replacing || !identical(_game, asked) || !_drawAsking) {
      return false;
    }
    _drawAsking = false;
    if (accepted) return _agreeDraw();
    _declinedAtPly = _ply;
    _drawDeclined = true;
    if (!_held) _declineTimer = Timer(drawDeclineShown, resume);
    _state = _viewState();
    notifyListeners();
    return false;
  }

  bool _agreeDraw() {
    final before = _game;
    final Game next;
    try {
      next = _game.agreeDraw();
    } on GameActionError {
      return false;
    }
    _game = next;
    _endPause();
    _refresh();
    notifyListeners();
    _announce(before);
    return _game.status == const Draw(GameEndReason.agreement);
  }

  /// View board: hides the result card, leaving the final position under
  /// the result bar. Refused unless the card is up.
  bool viewBoard() => _showAs(ResultView.card, ResultView.board);

  /// Brings the result card back from the result bar. Refused unless the
  /// bar is up.
  bool showResult() => _showAs(ResultView.board, ResultView.card);

  bool _showAs(ResultView from, ResultView to) {
    if (_resultView != from) return false;
    _resultView = to;
    _state = _viewState();
    notifyListeners();
    return true;
  }

  /// Leaves the pause and everything a draw offer left on its card.
  void _endPause() {
    _paused = false;
    _held = false;
    _drawAsking = false;
    _drawDeclined = false;
    _declineTimer?.cancel();
    _declineTimer = null;
  }

  /// Takes back the last move — against the computer, back to your turn,
  /// cancelling its search if it was thinking. Refused when the game's
  /// options turn takeback off or there is nothing to undo.
  bool takeBack() {
    if (isIdle || _replacing || !_game.canTakeBack) return false;
    final before = _game;
    _game = _game.takeBack();
    _refresh();
    notifyListeners();
    _announce(before, GameTookBack.new);
    return true;
  }

  /// Starts the same kind of game again from the same position, with the
  /// same time control; the computer is a new one with a fresh seed. The
  /// takeback option applies from here. Completes with true once the new
  /// game is in place, as [newGame] describes; refused while idle.
  Future<bool> restart() {
    if (isIdle || _replacing) return Future.value(false);
    final mode = switch (_game.mode) {
      VsComputer(:final playerColour, :final step) => VsComputer.newGame(
        playerColour: playerColour,
        step: step,
      ),
      final other => other,
    };
    return _replace(mode, _game.clock.control, fen: _fen);
  }

  /// Starts a new game from [setup] at the standard start position; against
  /// the computer the seed is [seed], else the controller's own override,
  /// else a fresh one. The takeback option
  /// applies from here.
  ///
  /// The game it replaces is frozen at once — its search cancelled, its
  /// clock held, the board locked, with no event and no save — while the
  /// replace stages run, and the new game goes in after the last one; a
  /// stage that throws is logged and the replacement goes ahead. Completes
  /// with true once the new game is in place, and with false, changing
  /// nothing, while another replacement is running.
  Future<bool> newGame(GameSetup setup, {int? seed}) {
    if (_replacing) return Future.value(false);
    return _replace(
      modeFor(setup, seed: seed ?? _seedOverride),
      setup.timeControl,
      fen: null,
    );
  }

  Future<bool> _replace(GameMode mode, TimeControl timeControl, {String? fen}) {
    final outgoing = _freeze();
    final outgoingRecorded = outgoing == null ? null : _recordedState;
    final stages = List.of(_replaceStages);
    // With no stages the new game goes in within the call, so a controller
    // nothing listens to stays synchronous.
    if (stages.isEmpty) {
      _start(outgoing, mode, timeControl, fen);
      return Future.value(true);
    }
    return () async {
      for (final stage in stages) {
        try {
          await stage(outgoing, outgoingRecorded, PlayMode.of(mode));
        } on Object catch (e) {
          debugPrint('controller: a replace stage failed: $e');
        }
      }
      if (_disposed) return false;
      _start(outgoing, mode, timeControl, fen);
      return true;
    }();
  }

  /// Holds the game on the board still for a replacement and answers it:
  /// the computer stopped, the clock paused inside the game, input locked.
  /// Null while idle.
  Game? _freeze() {
    _replacing = true;
    final current = _current;
    if (current == null) return null;
    _turns?.dispose();
    _turns = null;
    _declineTimer?.cancel();
    _declineTimer = null;
    _drawAsking = false;
    if (!current.isOver) _game = current.pause();
    _refresh();
    notifyListeners();
    return _game;
  }

  void _start(
    Game? outgoing,
    GameMode mode,
    TimeControl timeControl,
    String? fen,
  ) {
    if (outgoing != null && !outgoing.isOver) {
      _emit(GameAbandoned(outgoing, _recorded));
    }
    _replacing = false;
    _fen = fen;
    _recordedState = RecordedState.fresh(_newGameId);
    _game = Game.start(
      mode,
      timeControl,
      options: GameOptions(takebackAllowed: _options.takebackAllowed),
      fen: _fen,
      time: _now,
    );
    _endPause();
    _declinedAtPly = null;
    _resultView = null;
    _turns = _turnsFor(mode);
    _refresh();
    notifyListeners();
    _emit(GameStarted(_game, _recorded));
  }

  /// Puts a saved, unfinished [game] on the board, paused, with the
  /// [recorded] map saved beside it; the pause card shows until [resume].
  /// It resets as [newGame] does — any search cancelled, the old computer
  /// stopped — and, against the computer, builds one with the game's own
  /// step and seed, which asks for a move only once play resumes. A
  /// finished game is refused. Emits only [GameRestored].
  /// The map becomes the game's [RecordedState] ([RecordedState.fromJson]),
  /// so a resumed game keeps its statistics id.
  bool restore(Game game, {Map<String, Object?> recorded = const {}}) {
    if (game.isOver || _replacing) return false;
    _turns?.dispose();
    _recordedState = RecordedState.fromJson(recorded, game, newId: _newGameId);
    _fen = game.history.first.position.toFen();
    _endPause();
    _paused = true;
    _game = game.pause();
    _declinedAtPly = null;
    _resultView = null;
    _turns = _turnsFor(game.mode);
    _refresh();
    notifyListeners();
    _emit(GameRestored(_game, _recorded));
    return true;
  }

  /// Resigns for you against the computer, or for the side to move between
  /// two players; a pause ends with it. Refused once the game is over, and
  /// while the computer considers a draw offer.
  bool resign() {
    if (isIdle || _drawAsking || _replacing) return false;
    final before = _game;
    final side = switch (_game.mode) {
      VsComputer(:final playerColour) => playerColour,
      TwoPlayer() => _game.sideToMove,
    };
    final Game next;
    try {
      next = _game.resign(side);
    } on GameActionError {
      return false;
    }
    _game = next;
    _endPause();
    _refresh();
    notifyListeners();
    _announce(before);
    return true;
  }

  /// Asks the computer again after it could not move.
  bool retryComputer() => _turns?.retry() ?? false;

  @override
  void dispose() {
    _disposed = true;
    _declineTimer?.cancel();
    _turns?.dispose();
    _events.close();
    _refusals.close();
    super.dispose();
  }

  /// Raises [event], or, for a change of the game with [kind], that event
  /// and then [GameEnded] if the change ended the game that stood [before].
  void _announce(
    Game before, [
    GameEvent Function(Game, Map<String, Object?>)? kind,
  ]) {
    if (kind != null) _emit(kind(_game, _recorded));
    if (!before.isOver && _game.isOver) _emit(GameEnded(_game, _recorded));
  }

  /// Delivers [event]. One raised by a listener while another is being
  /// delivered waits until that delivery is done, so the synchronous stream
  /// is never re-entered and events arrive in the order they happened.
  void _emit(GameEvent event) {
    if (_disposed) return;
    _undelivered.add(event);
    if (_delivering) return;
    _delivering = true;
    try {
      while (_undelivered.isNotEmpty && !_disposed) {
        _events.add(_undelivered.removeAt(0));
      }
    } finally {
      _delivering = false;
    }
  }

  ComputerTurns? _turnsFor(GameMode mode) {
    final factory = _computer;
    if (mode is! VsComputer || factory == null) return null;
    return ComputerTurns(
      factory(mode.step, mode.seed),
      play: _playComputer,
      changed: () {
        if (_disposed) return;
        _state = _viewState();
        notifyListeners();
      },
    );
  }

  /// Plays the computer's [move], as a player's move lands.
  bool _playComputer(Move move) {
    if (_disposed || _replacing) return false;
    return _play(move, byComputer: true);
  }

  /// Plays [move]. When a flag fell before it, the game the engine hands
  /// back is the flag-ended one without the move: it is taken, and the move
  /// counts as refused.
  bool _play(Move move, {bool byComputer = false}) {
    final before = _game;
    final Game next;
    try {
      next = _game.play(move, byComputer: byComputer);
    } on GameActionError {
      return false;
    }
    final played = next.history.length > _game.history.length;
    final state = _recordedState;
    // Set before `moved` is raised, so the save of this very move says so.
    if (played &&
        state != null &&
        !state.started &&
        isQualifyingMove(next.mode, before.sideToMove)) {
      _recordedState = state.copyWith(started: true);
    }
    _game = next;
    _refresh();
    notifyListeners();
    _announce(before, played ? GameMoved.new : null);
    return played;
  }

  void _refuse(Square from, Square? to, RefusalVia via) {
    if (_disposed) return;
    final piece = _game.position.pieceAt(from);
    if (piece == null) return;
    _refusals.add(Refusal(kind: piece.kind, from: from, to: to, via: via));
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
    // A finished game opens on its card; a re-opened one drops the result.
    _resultView = _game.isOver ? (_resultView ?? ResultView.card) : null;
    _legal = _game.isOver ? const [] : legalMoves(_game.position);
    final declined = _declinedAtPly;
    // A takeback to before the declined offer's move frees the offer.
    if (declined != null && _ply < declined) _declinedAtPly = null;
    _turns?.follow(_game, paused: _paused);
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
      thinking: _turns?.thinking ?? false,
      computerFailed: _turns?.failed ?? false,
      paused: _paused,
      drawAsking: _drawAsking,
      drawDeclined: _drawDeclined,
      over: _game.isOver,
      resultView: _resultView,
    );
  }
}
