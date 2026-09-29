import 'package:flutter/material.dart';

import '../theme/palette.dart';

/// The back button's character, drawn in Outfit, which has it (the header
/// test reads Outfit's cmap).
const backGlyph = '‹';

/// The design's screen header: the ‹ back button and the title, with an
/// optional upper-case [kicker] line under the title in [kickerColor].
/// Back pops the route, returning to wherever the screen was opened from.
/// Its parts are keyed `<keyPrefix>-back`, `-title` and `-kicker`, the
/// prefix being the screen's id (`settings`, `csetup`…).
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({
    super.key,
    required this.title,
    required this.keyPrefix,
    this.kicker,
    this.kickerColor = Palette.kicker,
    this.onBack,
  });

  final String title;
  final String keyPrefix;
  final String? kicker;
  final Color kickerColor;

  /// Replaces the default pop.
  final VoidCallback? onBack;

  static const backSize = 34.0;

  @override
  Widget build(BuildContext context) {
    final kicker = this.kicker;
    final back = onBack ?? () => Navigator.maybePop(context);
    return Row(
      children: [
        Semantics(
          button: true,
          label: 'Back',
          onTap: back,
          excludeSemantics: true,
          child: GestureDetector(
            key: Key('$keyPrefix-back'),
            behavior: HitTestBehavior.opaque,
            onTap: back,
            // 48 dp to touch, 34 dp drawn at its left; the rest of the
            // touch area is the design's 13 dp gap before the title.
            child: SizedBox.square(
              dimension: 48,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  width: backSize,
                  height: backSize,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Palette.cardFill,
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: Palette.borderStrong),
                  ),
                  child: const Text(
                    backGlyph,
                    style: TextStyle(
                      fontFamily: Fonts.outfit,
                      fontWeight: FontWeight.w500,
                      fontSize: 16,
                      height: 1,
                      color: Color(0xFFFFFFFF),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                header: true,
                child: Text(
                  title,
                  key: Key('$keyPrefix-title'),
                  style: const TextStyle(
                    fontFamily: Fonts.outfit,
                    fontWeight: FontWeight.w600,
                    fontSize: 19,
                    height: 1,
                    color: Color(0xFFFFFFFF),
                  ),
                ),
              ),
              if (kicker != null) ...[
                const SizedBox(height: 6),
                Text(
                  kicker,
                  key: Key('$keyPrefix-kicker'),
                  style: TextStyle(
                    fontFamily: Fonts.plexMono,
                    fontWeight: FontWeight.w500,
                    fontSize: 9.5,
                    height: 1,
                    letterSpacing: 9.5 * .16,
                    color: kickerColor,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
