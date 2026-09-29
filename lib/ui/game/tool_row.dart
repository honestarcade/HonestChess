import 'package:flutter/material.dart';

import 'package:honest_chess/ui/game/game_controller.dart';
import 'package:honest_chess/ui/theme/palette.dart';

/// The tool row's height (the design's 62 px row around 50 px buttons).
const double toolRowHeight = 62;

/// A tool button's height and the gap between two buttons.
const double toolHeight = 50, toolGap = 8;

/// A disabled tool's opacity.
const double disabledToolOpacity = 0.4;

/// The four tools under the board, in the design's order.
enum Tool {
  takeback('↺', 'TAKEBACK', 'Take back'),
  restart('⟳', 'RESTART', 'Restart', fallback: Icons.refresh),
  resign('⚑', 'RESIGN', 'Resign', fallback: Icons.flag),
  newGame('✚', 'NEW', 'New game', fallback: Icons.add);

  const Tool(this.glyph, this.label, this.semantics, {this.fallback});

  /// The design's icon glyph, drawn in [toolGlyphFamily] when [fallback]
  /// is null.
  final String glyph;
  final String label;
  final String semantics;

  /// The Material icon drawn instead of [glyph] where the bundled fonts
  /// have no glyph for it, so Android never picks a system font for it.
  final IconData? fallback;

  Key get key => Key('tool-${this == newGame ? 'new' : name}');
}

/// The bundled family that draws the tool glyphs that have no [Tool.fallback];
/// Outfit, the design's face for them, has none of the four.
const String toolGlyphFamily = Fonts.plexMono;

/// Takeback, Restart, Resign and New, full width under the board. Takeback
/// is disabled when the game's option turns it off or there is nothing to
/// undo, Resign once the game is over; a disabled tool is dimmed and a tap
/// on it does nothing. [onNew] is New's action.
class ToolRow extends StatelessWidget {
  const ToolRow({super.key, required this.controller, required this.onNew});

  final GameController controller;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final game = controller.game;
        VoidCallback? action(Tool tool) => switch (tool) {
          Tool.takeback when game.canTakeBack => controller.takeBack,
          Tool.restart => controller.restart,
          Tool.resign when !game.isOver => controller.resign,
          Tool.newGame => onNew,
          _ => null,
        };
        return SizedBox(
          height: toolRowHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: toolGap),
            child: Row(
              children: [
                for (final tool in Tool.values) ...[
                  if (tool != Tool.takeback) const SizedBox(width: toolGap),
                  Expanded(
                    child: _ToolButton(tool: tool, onTap: action(tool)),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({required this.tool, required this.onTap});

  final Tool tool;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accent = tool == Tool.newGame;
    final ink = accent ? Palette.accentInk : Palette.toolInk;
    final fallback = tool.fallback;
    const radius = BorderRadius.all(Radius.circular(13));
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: tool.semantics,
      onTap: onTap,
      excludeSemantics: true,
      child: Opacity(
        opacity: onTap == null ? disabledToolOpacity : 1,
        child: SizedBox(
          height: toolHeight,
          child: Material(
            color: accent ? Palette.accentFill : Palette.toolFill,
            shape: RoundedRectangleBorder(
              borderRadius: radius,
              side: BorderSide(
                color: accent ? Palette.accentEdge : Palette.toolEdge,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: tool.key,
              onTap: onTap,
              borderRadius: radius,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (fallback == null)
                    Text(
                      tool.glyph,
                      key: Key('tool-glyph-${tool.name}'),
                      style: TextStyle(
                        fontFamily: toolGlyphFamily,
                        fontWeight: FontWeight.w500,
                        fontSize: 15,
                        height: 1,
                        color: ink,
                      ),
                    )
                  else
                    Icon(
                      fallback,
                      key: Key('tool-glyph-${tool.name}'),
                      size: 15,
                      color: ink,
                    ),
                  const SizedBox(height: 5),
                  Text(
                    tool.label,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.fade,
                    style: TextStyle(
                      fontFamily: Fonts.plexMono,
                      fontWeight: FontWeight.w500,
                      fontSize: 8.5,
                      height: 1,
                      letterSpacing: 8.5 * .1,
                      color: ink,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
