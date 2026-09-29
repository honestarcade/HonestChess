import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:honest_chess/ui/board/board_interaction.dart';
import 'package:honest_chess/ui/board/board_options.dart';
import 'package:honest_chess/ui/board/orientation.dart';
import 'package:honest_chess/ui/game/game_controller.dart';
import 'package:honest_chess/ui/theme/palette.dart';

/// The play screen: a two-player game on the playable board.
class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.options});

  final BoardOptions options;

  @override
  State<GameScreen> createState() => GameScreenState();
}

class GameScreenState extends State<GameScreen> {
  late final GameController controller = GameController(
    options: widget.options,
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
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) => BoardInteraction(
              controller: controller,
              bottom: boardBottomOf(
                controller.game,
                rotate: controller.options.rotateEachTurn,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
