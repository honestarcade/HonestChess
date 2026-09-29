import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:honest_chess/ui/board/board_interaction.dart';
import 'package:honest_chess/ui/board/board_options.dart';
import 'package:honest_chess/ui/board/orientation.dart';
import 'package:honest_chess/ui/board/promotion_sheet.dart';
import 'package:honest_chess/ui/game/game_controller.dart';
import 'package:honest_chess/ui/theme/palette.dart';

/// The play screen: a two-player game on the playable board.
class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.options, this.fen});

  final BoardOptions options;

  /// The position the game starts from; the standard start when null.
  final String? fen;

  @override
  State<GameScreen> createState() => GameScreenState();
}

class GameScreenState extends State<GameScreen> {
  late final GameController controller = GameController(
    options: widget.options,
    fen: widget.fen,
  );

  @override
  void didUpdateWidget(GameScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    controller.options = widget.options;
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Palette.navy,
      ),
      child: Scaffold(
        backgroundColor: Palette.navy,
        body: SafeArea(
          // Overlays are layers over the board rather than routes, so the
          // screen's own controls above them stay live.
          child: Stack(
            fit: StackFit.expand,
            children: [
              ListenableBuilder(
                listenable: controller,
                builder: (context, _) => BoardInteraction(
                  controller: controller,
                  bottom: boardBottomOf(
                    controller.game,
                    rotate: controller.options.rotateEachTurn,
                  ),
                ),
              ),
              PromotionSheet(controller: controller),
            ],
          ),
        ),
      ),
    );
  }
}
