import 'package:flutter/widgets.dart';

import '../motion.dart';
import '../theme/palette.dart';

/// The design's switch: a 46×26 track, [Accent.main] when on and
/// [Palette.borderStrong] when off, with a 20 dp white knob at 23 dp (on)
/// or 3 dp (off) from its left. It only draws: the row holding it owns the
/// tap and the semantics, so a tap on the switch toggles exactly once.
class ToggleSwitch extends StatelessWidget {
  const ToggleSwitch({
    super.key,
    required this.value,
    this.accent = Accent.teal,
  });

  final bool value;
  final Accent accent;

  static const width = 46.0;
  static const height = 26.0;
  static const knobSize = 20.0;
  static const knobOn = 23.0;
  static const knobOff = 3.0;

  /// How long the knob slides and the track changes colour.
  static const slideDuration = Duration(milliseconds: 150);

  /// The knob's key, for tests that read where it is drawn.
  static const knobKey = Key('toggle-knob');

  @override
  Widget build(BuildContext context) {
    final duration = Motion.of(context).isOff ? Duration.zero : slideDuration;
    // Implicit animations retarget from wherever they are, so a tap during
    // a slide turns the knob round instead of restarting it.
    return ExcludeSemantics(
      child: AnimatedContainer(
        duration: duration,
        curve: Curves.easeOut,
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: value ? accent.main : Palette.borderStrong,
          borderRadius: BorderRadius.circular(height / 2),
        ),
        child: Stack(
          children: [
            AnimatedPositioned(
              duration: duration,
              curve: Curves.easeOut,
              top: (height - knobSize) / 2,
              left: value ? knobOn : knobOff,
              child: const SizedBox.square(
                key: knobKey,
                dimension: knobSize,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color(0xFFFFFFFF),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
