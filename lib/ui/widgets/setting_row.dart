import 'package:flutter/widgets.dart';

import '../theme/palette.dart';
import 'toggle_switch.dart';

/// One on/off setting: its label over its description, and a
/// [ToggleSwitch]. The whole row is the tap target and one semantics node
/// ("label, description", toggled), and the row's [key] is on it.
class SettingRow extends StatelessWidget {
  const SettingRow({
    super.key,
    required this.label,
    required this.description,
    required this.value,
    required this.onChanged,
    this.accent = Accent.teal,
  });

  final String label;
  final String description;
  final bool value;

  /// The row was tapped. The owner flips the value it keeps rather than
  /// [value], so taps landing before a rebuild each count.
  final VoidCallback onChanged;

  final Accent accent;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      toggled: value,
      label: '$label, $description',
      onTap: onChanged,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onChanged,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Palette.cardFill,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          fontFamily: Fonts.outfit,
                          fontWeight: FontWeight.w600,
                          fontSize: 12.5,
                          height: 1,
                          color: Color(0xFFFFFFFF),
                        ),
                      ),
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
                ToggleSwitch(value: value, accent: accent),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
