import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:honest_chess/data/play_mode.dart';
import 'package:honest_chess/data/recorded_state.dart';
import 'package:honest_chess/data/stats.dart' show isAbandonable;
import 'package:honest_chess/engine/engine.dart';
import 'package:honest_chess/ui/board/board_interaction.dart';
import 'package:honest_chess/ui/board/board_options.dart';
import 'package:honest_chess/ui/board/board_view.dart' show boardMargin;
import 'package:honest_chess/ui/board/move_animation.dart';
import 'package:honest_chess/ui/board/orientation.dart';
import 'package:honest_chess/ui/app_scope.dart';
import 'package:honest_chess/ui/board/promotion_sheet.dart';
import 'package:honest_chess/ui/game/computer_turns.dart';
import 'package:honest_chess/ui/game/defaults.dart';
import 'package:honest_chess/ui/game/game_controller.dart';
import 'package:honest_chess/ui/game/labels.dart';
import 'package:honest_chess/ui/game/pause_overlay.dart';
import 'package:honest_chess/ui/game/player_panel.dart';
import 'package:honest_chess/ui/game/result_overlay.dart';
import 'package:honest_chess/ui/game/tool_row.dart';
import 'package:honest_chess/ui/motion.dart';
import 'package:honest_chess/ui/navigation.dart';
import 'package:honest_chess/ui/screens/how_to_play_screen.dart' show HowToTab;
import 'package:honest_chess/ui/theme/palette.dart';

/// The top bar's height.
const double topBarHeight = 52;

/// The design's gaps: top bar to the opponent's panel, and a panel to the
/// board or your panel to the tool row — the latter shrinking, never below
/// [minBoardGap], on a phone too short for them.
const double barGap = 12, boardGap = 48, minBoardGap = 8;

/// The status chip's text when the computer could not move; the chip then
/// asks again when tapped.
const String computerFailedText = 'The computer could not move — tap to retry';

/// What a screen reader says for the pause pill (#102).
const String pausePillLabel = 'Pause game';

/// The status chip's text: the ending word once the game is over, else
/// [computerFailedText] when the computer could not move, else THINKING…
/// while it chooses, else who is in check, else who is to move.
String statusText(
  Game game, {
  required bool thinking,
  bool computerFailed = false,
}) {
  final ending = game.status.endingWord;
  if (ending != null) return ending;
  if (computerFailed) return computerFailedText;
  if (thinking) return 'THINKING…';
  final side = game.sideToMove.label.toUpperCase();
  return switch (game.status) {
    Ongoing(inCheck: true) => '$side IN CHECK',
    _ => '$side TO MOVE',
  };
}

/// What Restart says when the game it replaced counted as a loss.
const String restartLossText = 'Your previous game counted as a loss.';

/// How long [restartLossText] shows.
const Duration restartLossShown = Duration(seconds: 3);

/// The pause pill's title: "vs Club", or "Two players".
String gameTitle(GameMode mode) => switch (mode) {
  VsComputer(:final step) => 'vs ${step.label}',
  TwoPlayer() => 'Two players',
};

/// The play screen: the top bar, the two player panels with their clocks
/// and the playable board between them, over the design's radial gradient.
///
/// Android's back never leaves it by itself: on a live game it opens the
/// pause card — or cancels an open promotion, or waits while the computer
/// answers a draw offer — and on the pause card it resumes; on a finished
/// game it shows a result card still waiting to appear, then does what
/// View board does, and from the final position goes to the menu through
/// `leaveToMenu`. While the app's navigating flag is set it does nothing.
/// The screen reads the app's `AppScope` whenever a button or back leads
/// off the board.
class GameScreen extends StatefulWidget {
  const GameScreen({
    super.key,
    required this.options,
    this.fen,
    this.controller,
    this.setup,
    this.seed,
    this.computerFactory = ComputerPlayerOpponent.new,
  });

  final BoardOptions options;

  /// The position the game starts from; the standard start when null.
  final String? fen;

  /// A game to show instead of a new one from [setup]; its owner disposes
  /// it. While it is idle the screen is a plain navy frame.
  final GameController? controller;

  /// The game the screen starts; an untimed two-player game when null.
  final GameSetup? setup;

  /// The computer's seed for a game against it; fresh when null.
  final int? seed;

  /// Builds the computer for a game against it. The screen's own game
  /// cancels its search, and stops it, when the screen is disposed.
  final ComputerFactory computerFactory;

  @override
  State<GameScreen> createState() => GameScreenState();
}

class GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin {
  late final GameController controller = widget.controller ?? _newGame();

  /// Each move's slide, shared by the board and the orientation it holds.
  late final MoveAnimation _slides = MoveAnimation(
    vsync: this,
    controller: controller,
  );

  /// Leaving the app — another app, a call, the screen off — pauses the
  /// game; coming back leaves it paused.
  late final AppLifecycleListener _lifecycle;

  late bool _idle = controller.isIdle;

  final _result = GlobalKey<ResultOverlayState>();

  /// Set once Main menu, or back from the final position, starts leaving
  /// for the menu: from then on the screen takes no touches.
  bool _leaving = false;

  /// Whether [restartLossText] shows, and what hides it.
  bool _lossShown = false;
  Timer? _lossTimer;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onStateChange: _left);
    controller.addListener(_idleChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _slides.motion = Motion.of(context);
  }

  void _idleChanged() {
    if (_idle != controller.isIdle) setState(() => _idle = controller.isIdle);
  }

  /// The app root does the same and then saves; both are safe to run, in
  /// either order, since a second pause changes nothing.
  void _left(AppLifecycleState state) {
    if (state != AppLifecycleState.inactive &&
        state != AppLifecycleState.hidden) {
      return;
    }
    controller.checkFlag();
    controller.autoPause();
  }

  GameController _newGame() {
    final setup = widget.setup;
    if (setup == null) {
      return GameController(
        options: widget.options,
        fen: widget.fen,
        computer: widget.computerFactory,
      );
    }
    return GameController(
      mode: modeFor(setup, seed: widget.seed),
      timeControl: setup.timeControl,
      options: widget.options,
      fen: widget.fen,
      computer: widget.computerFactory,
    );
  }

  bool get _navigating => AppScope.of(context).navigation.busy;

  /// Android's back, as the class describes.
  void _back() {
    if (_leaving || _navigating) return;
    if (controller.isIdle) {
      _leave();
      return;
    }
    final state = controller.state;
    if (state.over) {
      if (state.resultView == ResultView.board) {
        _leave();
      } else if (!(_result.currentState?.showNow() ?? false)) {
        controller.viewBoard();
      }
    } else if (state.pendingPromotion != null) {
      controller.cancelPromotion();
    } else if (state.drawAsking) {
      return;
    } else if (state.paused) {
      controller.resume();
    } else {
      controller.pause();
    }
  }

  /// Main menu, and back from the final position.
  Future<void> _leave() async {
    if (_leaving || _navigating) return;
    setState(() => _leaving = true);
    final left = await leaveToMenu(context);
    if (!left && mounted) setState(() => _leaving = false);
  }

  /// A pause card button opening [open]'s screen over the board: the card,
  /// cleared of a declined draw's message, is there on return.
  void _fromPause(Future<bool> Function(BuildContext) open) {
    if (_leaving || _navigating) return;
    controller.keepPaused();
    open(context).ignore();
  }

  void _seeStatistics() {
    if (_leaving || _navigating || controller.isIdle) return;
    openStats(context, openOn: PlayMode.of(controller.game.mode)).ignore();
  }

  /// New: the setup screen for this game's kind, the game paused first —
  /// or, once it is over, its result card shown, so either card is there
  /// on return.
  void _new() {
    if (_leaving || _navigating) return;
    final game = controller.game;
    if (game.isOver) {
      if (!(_result.currentState?.showNow() ?? false)) {
        controller.showResult();
      }
    } else {
      controller.pause();
    }
    openSetup(context, PlayMode.of(game.mode)).ignore();
  }

  /// Restart, saying so for [restartLossShown] when the game it replaced
  /// counted as a loss.
  Future<void> _restart() async {
    final game = controller.game;
    final loss = isAbandonable(
      game,
      RecordedState.fromJson(controller.recorded, game),
    );
    if (!await controller.restart() || !loss || !mounted) return;
    _lossTimer?.cancel();
    _lossTimer = Timer(restartLossShown, () {
      if (mounted) setState(() => _lossShown = false);
    });
    setState(() => _lossShown = true);
  }

  @override
  void didUpdateWidget(GameScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    controller.options = widget.options;
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _lossTimer?.cancel();
    _slides.dispose();
    controller.removeListener(_idleChanged);
    if (widget.controller == null) controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: IgnorePointer(
        ignoring: _leaving,
        child: _idle ? const ColoredBox(color: Palette.screenBg) : _screen(),
      ),
    );
  }

  Widget _screen() {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Palette.screenBg,
      ),
      child: Scaffold(
        backgroundColor: Palette.screenBg,
        body: DecoratedBox(
          decoration: const BoxDecoration(gradient: _screenGradient),
          child: SafeArea(
            // Overlays are layers over the board rather than routes, so the
            // top bar above them stays live.
            child: CustomMultiChildLayout(
              delegate: _ScreenLayout(),
              children: [
                LayoutId(
                  id: _Slot.panels,
                  child: _PanelsAndBoard(
                    controller: controller,
                    slides: _slides,
                    onNew: _new,
                    onRestart: () => _restart().ignore(),
                  ),
                ),
                LayoutId(
                  id: _Slot.promotion,
                  child: PromotionSheet(controller: controller),
                ),
                LayoutId(
                  id: _Slot.top,
                  child: _TopBar(
                    controller: controller,
                    onPause: controller.pause,
                  ),
                ),
                if (_lossShown)
                  LayoutId(id: _Slot.loss, child: const _LossNotice()),
                LayoutId(
                  id: _Slot.pause,
                  child: PauseOverlay(
                    controller: controller,
                    onRules: () => _fromPause(
                      (context) =>
                          openHowTo(context, initialTab: HowToTab.rules),
                    ),
                    onSettings: () => _fromPause(openSettings),
                    onMainMenu: _leave,
                  ),
                ),
                LayoutId(
                  id: _Slot.result,
                  child: ResultOverlay(
                    key: _result,
                    controller: controller,
                    onSeeStatistics: _seeStatistics,
                    onMainMenu: _leave,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The design's `radial-gradient(120% 80% at 50% 0%, …)`: an ellipse
/// centred on the top edge, 1.2 widths across and 0.8 heights down.
const _screenGradient = RadialGradient(
  center: Alignment.topCenter,
  radius: 1.2,
  colors: [Palette.gradientInner, Palette.screenBg, Palette.gradientOuter],
  stops: [0, 0.52, 1],
  transform: _Ellipse(),
);

/// Stretches a [RadialGradient] sized on the width (radius 1.2 of the
/// shortest side, the width on a phone) into the design's ellipse, whose
/// vertical radius is 0.8 of the height.
class _Ellipse extends GradientTransform {
  const _Ellipse();

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    final horizontal = 1.2 * bounds.shortestSide;
    final vertical = 0.8 * bounds.height;
    final top = bounds.topCenter;
    return Matrix4.identity()
      ..translateByDouble(top.dx, top.dy, 0, 1)
      ..scaleByDouble(1, vertical / horizontal, 1, 1)
      ..translateByDouble(-top.dx, -top.dy, 0, 1);
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.controller, required this.onPause});

  final GameController controller;
  final VoidCallback onPause;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final game = controller.game;
        final state = controller.state;
        // The result bar takes the top bar's place.
        if (state.resultView == ResultView.board) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: boardMargin),
            child: ResultBar(controller: controller),
          );
        }
        final failed = state.computerFailed && !game.isOver;
        final text = statusText(
          game,
          thinking: state.thinking,
          computerFailed: failed,
        );
        final (fill, ink) = switch (game.status) {
          _ when game.isOver => (Palette.statusOverFill, Palette.tealOnTint),
          _ when failed => (Palette.statusCheckFill, Palette.dangerText),
          Ongoing(inCheck: true) when !state.thinking => (
            Palette.statusCheckFill,
            Palette.dangerText,
          ),
          _ => (Palette.statusFill, Palette.textBody),
        };
        return ConstrainedBox(
          constraints: const BoxConstraints(minHeight: topBarHeight),
          child: Align(
            heightFactor: 1,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Semantics(
                      button: true,
                      enabled: !game.isOver,
                      label: pausePillLabel,
                      onTap: game.isOver ? null : onPause,
                      excludeSemantics: true,
                      child: GestureDetector(
                        onTap: game.isOver ? null : onPause,
                        child: Container(
                          key: const Key('pause-pill'),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 11,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Palette.pillFill,
                            borderRadius: const BorderRadius.all(
                              Radius.circular(10),
                            ),
                            border: Border.all(color: Palette.pillEdge),
                          ),
                          child: Text(
                            '❚❚ ${gameTitle(game.mode)}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: Fonts.outfit,
                              fontWeight: FontWeight.w500,
                              fontSize: 11.5,
                              height: 1,
                              color: Palette.pieceWhite,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Semantics(
                      button: failed,
                      child: GestureDetector(
                        onTap: failed ? controller.retryComputer : null,
                        child: Container(
                          key: const Key('status-chip'),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: fill,
                            borderRadius: const BorderRadius.all(
                              Radius.circular(9),
                            ),
                          ),
                          child: Text(
                            text,
                            key: const Key('status-text'),
                            semanticsLabel: spokenCaps(text),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.end,
                            style: TextStyle(
                              fontFamily: Fonts.plexMono,
                              fontWeight: FontWeight.w500,
                              fontSize: 10,
                              height: 1,
                              letterSpacing: 10 * .08,
                              color: ink,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The opponent's panel, the board and your panel, top to bottom, each
/// following the board's orientation, then the tool row.
class _PanelsAndBoard extends StatelessWidget {
  const _PanelsAndBoard({
    required this.controller,
    required this.slides,
    required this.onNew,
    required this.onRestart,
  });

  final GameController controller;
  final MoveAnimation slides;
  final VoidCallback onNew;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([controller, slides]),
      builder: (context, _) {
        final game = controller.game;
        final rotate = controller.options.rotateEachTurn;
        // A turning board turns once the move has slid: meanwhile it
        // faces the side that moved.
        final bottom = slides.sliding
            ? boardBottom(game.mode, game.sideToMove.opponent, rotate: rotate)
            : boardBottomOf(game, rotate: rotate);
        Widget panel(Colour side) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: boardMargin),
          child: PlayerPanel(controller: controller, side: side),
        );
        return CustomMultiChildLayout(
          delegate: _BoardColumnLayout(),
          children: [
            LayoutId(id: _Part.opponent, child: panel(bottom.opponent)),
            LayoutId(
              id: _Part.board,
              // The ticking clocks never repaint the board.
              child: RepaintBoundary(
                child: BoardInteraction(
                  controller: controller,
                  bottom: bottom,
                  slides: slides,
                  announcer: AppScope.of(context).announcer,
                ),
              ),
            ),
            LayoutId(id: _Part.you, child: panel(bottom)),
            LayoutId(
              id: _Part.tools,
              child: ToolRow(
                controller: controller,
                onNew: onNew,
                onRestart: onRestart,
              ),
            ),
          ],
        );
      },
    );
  }
}

enum _Part { opponent, board, you, tools }

/// The column under the top bar: the panels and the tool row take the
/// height their text needs, and the board, as wide as the screen allows,
/// gives up whatever height they took, so the screen never scrolls. The
/// gaps between them shrink first, from [boardGap] down to [minBoardGap].
class _BoardColumnLayout extends MultiChildLayoutDelegate {
  _BoardColumnLayout();

  @override
  void performLayout(Size size) {
    final width = size.width;
    final loose = BoxConstraints(
      minWidth: width,
      maxWidth: width,
      maxHeight: size.height,
    );
    final opponent = layoutChild(_Part.opponent, loose).height;
    final you = layoutChild(_Part.you, loose).height;
    final tools = layoutChild(_Part.tools, loose).height;
    final spare = size.height - opponent - you - tools;
    final board = math.max(
      0.0,
      math.min(width - 2 * boardMargin, spare - 3 * minBoardGap),
    );
    final gap = ((spare - board) / 3).clamp(minBoardGap, boardGap);
    layoutChild(_Part.board, BoxConstraints.tight(Size(width, board)));
    var y = 0.0;
    for (final (part, height) in [
      (_Part.opponent, opponent),
      (_Part.board, board),
      (_Part.you, you),
      (_Part.tools, tools),
    ]) {
      positionChild(part, Offset(0, y));
      y += height + gap;
    }
  }

  @override
  bool shouldRelayout(_BoardColumnLayout oldDelegate) => false;
}

enum _Slot { top, panels, promotion, loss, pause, result }

/// The play screen's layers: the top bar at the top, at least
/// [topBarHeight] tall and taller when its text needs it; the panels and
/// board below it; the cards over everything; and the Restart notice just
/// under the top bar.
class _ScreenLayout extends MultiChildLayoutDelegate {
  _ScreenLayout();

  @override
  void performLayout(Size size) {
    final top = layoutChild(
      _Slot.top,
      BoxConstraints(
        minWidth: size.width,
        maxWidth: size.width,
        maxHeight: size.height,
      ),
    ).height;
    // The design's place for the panels, unless a grown top bar or result
    // bar needs more; the result bar is the taller, by what it takes from
    // the gap.
    final below = math.max(
      topBarHeight + barGap,
      top + barGap - (resultBarHeight - topBarHeight),
    );
    layoutChild(
      _Slot.panels,
      BoxConstraints.tight(Size(size.width, math.max(0, size.height - below))),
    );
    positionChild(_Slot.panels, Offset(0, below));
    for (final layer in [_Slot.promotion, _Slot.pause, _Slot.result]) {
      layoutChild(layer, BoxConstraints.tight(size));
    }
    if (hasChild(_Slot.loss)) {
      final width = math.max(0.0, size.width - 2 * boardMargin);
      layoutChild(_Slot.loss, BoxConstraints(minWidth: width, maxWidth: width));
      positionChild(_Slot.loss, Offset(boardMargin, below));
    }
  }

  @override
  bool shouldRelayout(_ScreenLayout oldDelegate) => false;
}

/// [restartLossText] in a card over the opponent's panel, read out as it
/// appears; it takes no touches.
class _LossNotice extends StatelessWidget {
  const _LossNotice();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Semantics(
        liveRegion: true,
        container: true,
        child: Container(
          key: const Key('restart-loss'),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: const BoxDecoration(
            color: Palette.cardSurface,
            borderRadius: BorderRadius.all(Radius.circular(14)),
            border: Border.fromBorderSide(BorderSide(color: Palette.cardEdge)),
          ),
          child: const Text(
            restartLossText,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: Fonts.outfit,
              fontWeight: FontWeight.w500,
              fontSize: 13,
              height: 1.2,
              color: Color(0xFFFFFFFF),
            ),
          ),
        ),
      ),
    );
  }
}
