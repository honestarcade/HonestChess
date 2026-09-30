import 'package:flutter/material.dart';

import '../game/labels.dart';
import '../navigation.dart';
import '../theme/palette.dart';

/// The back button's character, drawn in Outfit, which has it (the header
/// test reads Outfit's cmap).
const backGlyph = '‹';

/// The ‹'s font size. Outfit's ‹ is small for its size (see
/// [backGlyphLift]'s bounds), so it is set larger than the 34 dp box and
/// its line box spills past the box (#165).
const backGlyphSize = 40.0;

/// How far ‹ is lifted, as a share of [backGlyphSize], so that its ink,
/// not its line box, is centred in the box: at height 1 the baseline
/// sits 1000/1260 of the way down and the ink spans 81–403 of 1000 units
/// above it (Outfit-Medium.ttf's hhea and glyph bounds, read with
/// fontTools' BoundsPen on 2026-09-30).
const backGlyphLift = 1000 / 1260 - (81 + 403) / 2000 - .5;

/// The design's screen header: the ‹ back button and the title, with an
/// optional upper-case [kicker] line under the title in [kickerColor].
/// Back is [goBack], the phone's back button's own path, returning to
/// wherever the screen was opened from;
/// while pressed its border is the [accent]'s.
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
    this.accent = Accent.teal,
  });

  final String title;
  final String keyPrefix;
  final String? kicker;
  final Color kickerColor;

  /// Replaces the default pop.
  final VoidCallback? onBack;

  /// The back button's border while pressed: the accent's main colour.
  final Accent accent;

  static const backSize = 34.0;

  @override
  Widget build(BuildContext context) {
    final kicker = this.kicker;
    final back = onBack ?? () => goBack(context);
    return Row(
      children: [
        _BackButton(keyPrefix: keyPrefix, onBack: back, accent: accent),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                container: true,
                header: true,
                headingLevel: 1,
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
                // Its own node, so a screen reader reads it after the
                // heading (#147).
                Semantics(
                  container: true,
                  child: Text(
                    kicker,
                    key: Key('$keyPrefix-kicker'),
                    semanticsLabel: spokenCaps(kicker),
                    style: TextStyle(
                      fontFamily: Fonts.plexMono,
                      fontWeight: FontWeight.w500,
                      fontSize: 9.5,
                      height: 1,
                      letterSpacing: 9.5 * .16,
                      color: kickerColor,
                    ),
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

class _BackButton extends StatefulWidget {
  const _BackButton({
    required this.keyPrefix,
    required this.onBack,
    required this.accent,
  });

  final String keyPrefix;
  final VoidCallback onBack;
  final Accent accent;

  @override
  State<_BackButton> createState() => _BackButtonState();
}

class _BackButtonState extends State<_BackButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      label: 'Back',
      onTap: widget.onBack,
      excludeSemantics: true,
      child: GestureDetector(
        key: Key('${widget.keyPrefix}-back'),
        behavior: HitTestBehavior.opaque,
        onTap: widget.onBack,
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        // 48 dp to touch, 34 dp drawn at its left; the rest of the touch
        // area is the design's 13 dp gap before the title.
        child: SizedBox.square(
          dimension: 48,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Container(
              key: Key('${widget.keyPrefix}-back-box'),
              width: ScreenHeader.backSize,
              height: ScreenHeader.backSize,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Palette.cardFill,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(
                  color: _pressed ? widget.accent.main : Palette.borderStrong,
                ),
              ),
              // The glyph is a drawing in a fixed box, so it does not grow
              // with the text size; its line box is let spill past the box
              // rather than clip the ink.
              child: OverflowBox(
                maxWidth: double.infinity,
                maxHeight: double.infinity,
                child: Transform.translate(
                  offset: const Offset(0, -backGlyphLift * backGlyphSize),
                  child: const Text(
                    backGlyph,
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(
                      fontFamily: Fonts.outfit,
                      fontWeight: FontWeight.w500,
                      fontSize: backGlyphSize,
                      height: 1,
                      color: Color(0xFFFFFFFF),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
