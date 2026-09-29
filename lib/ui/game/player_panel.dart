import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'package:honest_chess/engine/engine.dart';
import 'package:honest_chess/ui/game/game_controller.dart';
import 'package:honest_chess/ui/game/labels.dart';
import 'package:honest_chess/ui/theme/palette.dart';

/// A player panel's height (the design's panels), which a large system
/// text size may grow.
const double panelHeight = 52;

/// How often, at most, a running clock's spoken label follows its text; a
/// screen reader re-announcing every second would drown everything else.
const Duration clockSpeechInterval = Duration(seconds: 10);

/// Who plays [side] in [mode], as the panel names them: "You" and the
/// step's name against the computer, "White"/"Black" for two players.
String playerName(GameMode mode, Colour side) => switch (mode) {
  VsComputer(:final playerColour, :final step) =>
    side == playerColour ? 'You' : step.label,
  TwoPlayer() => side.label,
};

/// The panel's sub-line: who the player is, their colour and the time
/// control — "YOU · WHITE · RAPID 10+5".
String playerSubLine(GameMode mode, Colour side, TimeControl control) {
  final colour = side.label.toUpperCase();
  final who = switch (mode) {
    VsComputer(:final playerColour) =>
      side == playerColour ? 'YOU' : 'COMPUTER',
    TwoPlayer() => side == Colour.white ? 'PLAYER ONE' : 'PLAYER TWO',
  };
  return '$who · $colour · ${control.label}';
}

/// One side's panel above or below the board: the king chip in its colour,
/// the player's name and sub-line, and the clock. The side to move's panel
/// is lit while the game goes on; once it is over neither is.
class PlayerPanel extends StatelessWidget {
  const PlayerPanel({super.key, required this.controller, required this.side});

  final GameController controller;
  final Colour side;

  @override
  Widget build(BuildContext context) {
    final game = controller.game;
    final lit = !game.isOver && game.sideToMove == side;
    final name = playerName(game.mode, side);
    final thinking =
        controller.state.thinking &&
        game.mode is VsComputer &&
        side != (game.mode as VsComputer).playerColour;
    return Container(
      key: Key('panel-${side.name}'),
      // Taller when its text is: a large system text size may wrap the
      // sub-line.
      constraints: const BoxConstraints(minHeight: panelHeight),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: lit ? Palette.panelLit : Palette.panelDim,
        borderRadius: const BorderRadius.all(Radius.circular(14)),
        border: lit ? Border.all(color: Palette.panelLitEdge) : null,
      ),
      child: Row(
        children: [
          _KingChip(side: side),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  thinking ? '$name is thinking' : name,
                  key: Key('name-${side.name}'),
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: Fonts.outfit,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    height: 1,
                    color: Palette.pieceWhite,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  playerSubLine(game.mode, side, game.clock.control),
                  key: Key('sub-${side.name}'),
                  semanticsLabel: spokenCaps(
                    playerSubLine(game.mode, side, game.clock.control),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: Fonts.plexMono,
                    fontWeight: FontWeight.w500,
                    fontSize: 9,
                    height: 1,
                    letterSpacing: 9 * .14,
                    color: lit ? Palette.tealOnTint : Palette.textDim,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          ClockDisplay(controller: controller, side: side, lit: lit, who: name),
        ],
      ),
    );
  }
}

class _KingChip extends StatelessWidget {
  const _KingChip({required this.side});

  final Colour side;

  @override
  Widget build(BuildContext context) {
    final white = side == Colour.white;
    return ExcludeSemantics(
      child: Container(
        key: Key('chip-${side.name}'),
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: white ? Palette.kingChipLight : Palette.kingChipDark,
          borderRadius: const BorderRadius.all(Radius.circular(9)),
        ),
        // The piece font's kings, whatever the board's piece style.
        child: Text(
          white ? '♔\u{FE0E}' : '♚\u{FE0E}',
          style: TextStyle(
            fontFamily: Fonts.pieces,
            fontSize: 18,
            height: 1,
            color: white ? Palette.kingChipDark : Palette.kingChipLight,
          ),
        ),
      ),
    );
  }
}

/// [side]'s clock. While that clock runs, this widget's [Ticker] — the only
/// one on the screen — redraws its text whenever the shown value or the red
/// state changes, and asks the controller to check for a flag each frame.
/// Nothing else rebuilds as the time passes.
class ClockDisplay extends StatefulWidget {
  const ClockDisplay({
    super.key,
    required this.controller,
    required this.side,
    required this.lit,
    required this.who,
  });

  final GameController controller;
  final Colour side;
  final bool lit;

  /// The player's name, for the spoken label.
  final String who;

  @override
  State<ClockDisplay> createState() => _ClockDisplayState();
}

class _ClockDisplayState extends State<ClockDisplay>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);

  String _text = '';
  bool _red = false;
  String _spoken = '';

  /// The ticker's elapsed time at the last frame, and when [_spoken] last
  /// changed.
  Duration _elapsed = Duration.zero;
  Duration _spokenAt = Duration.zero;

  GameController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_sync);
    _update(speak: true);
    _runTicker();
  }

  @override
  void didUpdateWidget(ClockDisplay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_sync);
      widget.controller.addListener(_sync);
    }
    _update(speak: oldWidget.lit != widget.lit || oldWidget.who != widget.who);
    _runTicker();
  }

  @override
  void dispose() {
    _controller.removeListener(_sync);
    _ticker.dispose();
    super.dispose();
  }

  /// The game changed (a move, a pause, a flag, or only a selection): the
  /// text follows at once, and so does the spoken label unless this clock
  /// is still running — a stopped clock's value no longer changes.
  void _sync() {
    setState(() => _update(speak: !_controller.clockRunning(widget.side)));
    _runTicker();
  }

  /// The ticker runs only while this side's clock does.
  void _runTicker() {
    final running = _controller.clockRunning(widget.side);
    if (running && !_ticker.isActive) {
      _elapsed = _spokenAt = Duration.zero;
      _ticker.start();
    } else if (!running && _ticker.isActive) {
      _ticker.stop();
    }
  }

  /// Reads the clock; returns whether anything shown changed. The spoken
  /// label follows when [speak] says so, when the red state changes, or
  /// once [clockSpeechInterval] has passed since it last did.
  bool _update({required bool speak}) {
    final ms = _controller.remaining(widget.side)?.inMilliseconds;
    final text = clockText(ms);
    final red = ms != null && ms < lowTimeMs;
    final say =
        speak || red != _red || _elapsed - _spokenAt >= clockSpeechInterval;
    final spoken = say ? clockSemantics(widget.who, ms) : _spoken;
    if (say) _spokenAt = _elapsed;
    final changed = text != _text || red != _red || spoken != _spoken;
    _text = text;
    _red = red;
    _spoken = spoken;
    return changed;
  }

  void _tick(Duration elapsed) {
    _elapsed = elapsed;
    // Only a change the eye or a screen reader would notice rebuilds.
    if (_update(speak: false)) setState(() {});
    _controller.checkFlag();
  }

  @override
  Widget build(BuildContext context) {
    final lit = widget.lit;
    return Semantics(
      key: Key('clock-semantics-${widget.side.name}'),
      label: _spoken,
      excludeSemantics: true,
      child: Opacity(
        opacity: lit ? 1 : Palette.clockDimOpacity,
        child: Text(
          _text,
          key: Key('clock-${widget.side.name}'),
          maxLines: 1,
          softWrap: false,
          // The digits keep their size at any system text size, as the
          // board does.
          textScaler: TextScaler.noScaling,
          style: TextStyle(
            fontFamily: Fonts.plexMono,
            fontWeight: FontWeight.w600,
            fontSize: 20,
            height: 1,
            fontFeatures: const [FontFeature.tabularFigures()],
            color: _red
                ? Palette.dangerText
                : lit
                ? Palette.pieceWhite
                : Palette.textDim,
          ),
        ),
      ),
    );
  }
}
