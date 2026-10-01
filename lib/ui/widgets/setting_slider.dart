import 'package:flutter/material.dart';

import '../theme/palette.dart';

/// One stepped setting: its label and current value over its description,
/// and a slider across [steps]. Laid out as a `SettingRow`, on the same
/// card. A screen reader meets one node — the slider, labelled "label,
/// description" and valued in [spoken]'s words — which steps up and down;
/// the drawn texts are not read twice.
class SettingSlider extends StatelessWidget {
  const SettingSlider({
    super.key,
    required this.id,
    required this.label,
    required this.description,
    required this.steps,
    required this.value,
    required this.shown,
    required this.spoken,
    required this.onChanged,
    this.accent = Accent.teal,
  });

  /// The prefix of the value text's key (`<id>-value`) and the slider's
  /// (`<id>-slider`).
  final String id;

  final String label;
  final String description;

  /// The values the slider stops at, in order.
  final List<int> steps;

  /// The current value; one of [steps].
  final int value;

  /// A value as the row draws it ("Off", "3 s") and as a screen reader
  /// says it ("Off", "3 seconds").
  final String Function(int) shown;
  final String Function(int) spoken;

  /// A new value was chosen.
  final ValueChanged<int> onChanged;

  final Accent accent;

  /// The slider's height: the 48 dp touch target.
  static const height = 48.0;

  static const _labelStyle = TextStyle(
    fontFamily: Fonts.outfit,
    fontWeight: FontWeight.w600,
    fontSize: 12.5,
    height: 1,
    color: Color(0xFFFFFFFF),
  );

  @override
  Widget build(BuildContext context) {
    final index = steps.indexOf(value).clamp(0, steps.length - 1);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Palette.cardFill,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ExcludeSemantics(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label, style: _labelStyle),
                        const SizedBox(height: 5),
                        Text(
                          description,
                          style: const TextStyle(
                            fontFamily: Fonts.outfit,
                            fontWeight: FontWeight.w400,
                            fontSize: 10.5,
                            height: 1.35,
                            color: Palette.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    shown(steps[index]),
                    key: Key('$id-value'),
                    style: _labelStyle,
                  ),
                ],
              ),
            ),
            SizedBox(
              height: height,
              child: SliderTheme(
                data: SliderThemeData(
                  trackHeight: 4,
                  activeTrackColor: accent.main,
                  inactiveTrackColor: Palette.borderStrong,
                  activeTickMarkColor: Palette.onTeal,
                  inactiveTickMarkColor: Palette.textMuted,
                  thumbColor: const Color(0xFFFFFFFF),
                  overlayColor: accent.main.withValues(alpha: .16),
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 10,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: height / 2,
                  ),
                  trackShape: const RoundedRectSliderTrackShape(),
                  tickMarkShape: const RoundSliderTickMarkShape(
                    tickMarkRadius: 2,
                  ),
                  showValueIndicator: ShowValueIndicator.never,
                ),
                child: Slider(
                  key: Key('$id-slider'),
                  // Read as the slider's semantics label; never drawn,
                  // as the value indicator is off.
                  label: '$label, $description',
                  value: index.toDouble(),
                  max: (steps.length - 1).toDouble(),
                  divisions: steps.length - 1,
                  semanticFormatterCallback: (v) =>
                      spoken(steps[v.round().clamp(0, steps.length - 1)]),
                  onChanged: (v) {
                    final next = steps[v.round()];
                    if (next != value) onChanged(next);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
