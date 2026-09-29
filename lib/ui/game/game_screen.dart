import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:honest_chess/data/game_event.dart';
import 'package:honest_chess/engine/engine.dart';
import 'package:honest_chess/ui/board/board_interaction.dart';
import 'package:honest_chess/ui/board/board_options.dart';
import 'package:honest_chess/ui/board/board_view.dart' show boardMargin;
import 'package:honest_chess/ui/board/orientation.dart';
import 'package:honest_chess/ui/board/promotion_sheet.dart';
import 'package:honest_chess/ui/game/computer_turns.dart';
import 'package:honest_chess/ui/game/defaults.dart';
import 'package:honest_chess/ui/game/game_controller.dart';
import 'package:honest_chess/ui/game/labels.dart';
import 'package:honest_chess/ui/game/pause_overlay.dart';
import 'package:honest_chess/ui/game/player_panel.dart';
import 'package:honest_chess/ui/game/result_overlay.dart';
import 'package:honest_chess/ui/game/temporary_new_game.dart';
import 'package:honest_chess/ui/game/tool_row.dart';
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

/// The pause pill's title: "vs Club", or "Two players".
String gameTitle(GameMode mode) => switch (mode) {
  VsComputer(:final step) => 'vs ${step.label}',
  TwoPlayer() => 'Two players',
};

/// The play screen: the top bar, the two player panels with their clocks
/// and the playable board between them, over the design's radial gradient.
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

class GameScreenState extends State<GameScreen> {
  late final GameController controller = widget.controller ?? _newGame();

  /// Leaving the app — another app, a call, the screen off — pauses the
  /// game; coming back leaves it paused.
  late final AppLifecycleListener _lifecycle;

  /// Whether the new-game picker is open over the screen.
  bool _picking = false;

  late bool _idle = controller.isIdle;
  late final StreamSubscription<GameEvent> _events;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onStateChange: _left);
    controller.addListener(_idleChanged);
    // A restored game replaces whatever the picker was choosing for.
    _events = controller.events.listen((event) {
      if (event is GameRestored) _closePicker();
    });
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
    if (!controller.isIdle && controller.state.paused) _closePicker();
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

  /// New's action until M4's setup screens: the temporary picker, and the
  /// chosen game. Closing the picker without a choice changes nothing.
  Future<void> _pickNewGame() async {
    _picking = true;
    final GameSetup? setup;
    try {
      setup = await TemporaryNewGamePicker.show(context);
    } finally {
      _picking = false;
    }
    if (setup == null || !mounted) return;
    controller.newGame(setup, seed: widget.seed);
  }

  /// The pause pill: pauses the game and opens the pause card.
  void _pause() {
    if (controller.pause()) _closePicker();
  }

  /// A pause closes the new-game picker with nothing chosen, as it closes
  /// the promotion card.
  void _closePicker() {
    if (!_picking || !mounted) return;
    final screen = ModalRoute.of(context);
    Navigator.of(context).popUntil((route) => route == screen);
  }

  @override
  void didUpdateWidget(GameScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    controller.options = widget.options;
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _events.cancel();
    controller.removeListener(_idleChanged);
    if (widget.controller == null) controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_idle) return const ColoredBox(color: Palette.screenBg);
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
            child: Stack(
              fit: StackFit.expand,
              children: [
                Column(
                  children: [
                    const SizedBox(height: topBarHeight + barGap),
                    Expanded(
                      child: _PanelsAndBoard(
                        controller: controller,
                        onNew: _pickNewGame,
                      ),
                    ),
                  ],
                ),
                PromotionSheet(controller: controller),
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: topBarHeight,
                  child: _TopBar(controller: controller, onPause: _pause),
                ),
                PauseOverlay(controller: controller),
                ResultOverlay(controller: controller),
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
  colors: [Palette.navyLight, Palette.screenBg, Palette.navyDeep],
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
          return const SizedBox.shrink();
        }
        final failed = state.computerFailed && !game.isOver;
        final text = statusText(
          game,
          thinking: state.thinking,
          computerFailed: failed,
        );
        final (fill, ink) = switch (game.status) {
          _ when game.isOver => (Palette.statusOverFill, Palette.teal),
          _ when failed => (Palette.statusCheckFill, Palette.alarm),
          Ongoing(inCheck: true) when !state.thinking => (
            Palette.statusCheckFill,
            Palette.alarm,
          ),
          _ => (Palette.statusFill, Palette.choiceLabel),
        };
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Semantics(
                  button: true,
                  enabled: !game.isOver,
                  label: 'Pause',
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
                        maxLines: 1,
                        softWrap: false,
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
                        maxLines: 2,
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
        );
      },
    );
  }
}

/// The opponent's panel, the board and your panel, top to bottom, each
/// following the board's orientation, then the tool row.
class _PanelsAndBoard extends StatelessWidget {
  const _PanelsAndBoard({required this.controller, required this.onNew});

  final GameController controller;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final spare = height - 2 * panelHeight - toolRowHeight;
        final board = math.max(
          0.0,
          math.min(width - 2 * boardMargin, spare - 3 * minBoardGap),
        );
        final gap = ((spare - board) / 3).clamp(minBoardGap, boardGap);
        return ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            final bottom = boardBottomOf(
              controller.game,
              rotate: controller.options.rotateEachTurn,
            );
            Widget panel(Colour side) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: boardMargin),
              child: PlayerPanel(controller: controller, side: side),
            );
            return Column(
              children: [
                panel(bottom.opponent),
                SizedBox(height: gap),
                SizedBox(
                  width: width,
                  height: board,
                  // The ticking clocks never repaint the board.
                  child: RepaintBoundary(
                    child: BoardInteraction(
                      controller: controller,
                      bottom: bottom,
                    ),
                  ),
                ),
                SizedBox(height: gap),
                panel(bottom),
                SizedBox(height: gap),
                ToolRow(controller: controller, onNew: onNew),
              ],
            );
          },
        );
      },
    );
  }
}
