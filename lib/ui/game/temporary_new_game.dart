import 'package:flutter/material.dart';

import 'package:honest_chess/engine/engine.dart';
import 'package:honest_chess/ui/game/defaults.dart';
import 'package:honest_chess/ui/game/labels.dart';
import 'package:honest_chess/ui/theme/palette.dart';

/// "Rapid 10+5", from the panel's "RAPID 10+5".
String _control(TimeControl control) {
  final label = control.label;
  return label[0] + label.substring(1).toLowerCase();
}

/// The picker's two games, each with its option's words.
final List<({Key key, String title, String meta, GameSetup setup})>
newGameChoices = [
  (
    key: const Key('new-vs-computer'),
    title: 'vs Computer',
    meta: [
      vsComputerDefault.strength!.label,
      vsComputerDefault.colour!.label,
      _control(vsComputerDefault.timeControl),
    ].join(' · '),
    setup: vsComputerDefault,
  ),
  (
    key: const Key('new-two-players'),
    title: 'Two players',
    meta: _control(twoPlayerDefault.timeControl),
    setup: twoPlayerDefault,
  ),
];

/// New's picker: a bottom sheet offering a game against the computer or
/// between two players, each with the design's default settings. Back or a
/// tap outside closes it with nothing chosen; the game underneath goes on,
/// clocks running, while it is open.
///
/// Replaced by M4's setup screens (epic #6).
class TemporaryNewGamePicker extends StatelessWidget {
  const TemporaryNewGamePicker({super.key});

  /// Opens the picker; completes with the chosen setup, or null when it
  /// was closed without a choice.
  static Future<GameSetup?> show(BuildContext context) =>
      showModalBottomSheet<GameSetup>(
        context: context,
        backgroundColor: Palette.card,
        barrierColor: Palette.scrim,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          side: BorderSide(color: Palette.cardEdge),
        ),
        builder: (_) => const TemporaryNewGamePicker(),
      );

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: const Text(
                'New game',
                style: TextStyle(
                  fontFamily: Fonts.outfit,
                  fontWeight: FontWeight.w600,
                  fontSize: 18,
                  height: 1,
                  color: Color(0xFFFFFFFF),
                ),
              ),
            ),
            for (final choice in newGameChoices) ...[
              const SizedBox(height: 12),
              _Choice(
                key: choice.key,
                title: choice.title,
                meta: choice.meta,
                onTap: () => Navigator.of(context).pop(choice.setup),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    super.key,
    required this.title,
    required this.meta,
    required this.onTap,
  });

  final String title;
  final String meta;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(13));
    return Semantics(
      button: true,
      label: '$title — $meta',
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: Palette.choiceFill,
        shape: const RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: Palette.choiceEdge),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: Fonts.outfit,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    height: 1,
                    color: Color(0xFFFFFFFF),
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  meta.toUpperCase(),
                  style: const TextStyle(
                    fontFamily: Fonts.plexMono,
                    fontWeight: FontWeight.w500,
                    fontSize: 10,
                    height: 1,
                    letterSpacing: 10 * .14,
                    color: Palette.textDim,
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
