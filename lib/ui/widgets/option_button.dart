import 'package:flutter/material.dart';

import '../theme/palette.dart';

/// Which of the design's bordered-choice looks an [OptionButton] takes.
enum OptionLook {
  /// Settings' swatches and surfaces: a soft idle border, and the fill
  /// unchanged when chosen.
  settings,

  /// Settings' piece styles: a soft idle border, and teal .12 when chosen.
  settingsFilled,

  /// The setup screens' choices: a firmer idle border, and the accent's
  /// fill when chosen.
  setup,
}

/// One bordered choice of a group where exactly one is chosen. The chosen
/// one has the accent's border and label colour; the label colour reaches
/// [child] through [DefaultTextStyle]. Each caller passes the design's own
/// [padding] and [radius] for its instance.
class OptionButton extends StatefulWidget {
  const OptionButton({
    super.key,
    required this.selected,
    required this.onPressed,
    required this.child,
    required this.padding,
    this.radius = 12,
    this.look = OptionLook.settings,
    this.accent = Accent.teal,
  });

  final bool selected;
  final VoidCallback onPressed;
  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final OptionLook look;
  final Accent accent;

  /// The border's width.
  static const borderWidth = 1.5;

  /// The smallest touch target, whatever the drawn size.
  static const minTouch = 48.0;

  @override
  State<OptionButton> createState() => _OptionButtonState();
}

class _OptionButtonState extends State<OptionButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final look = widget.look;
    final accent = widget.accent;
    final selected = widget.selected;
    final idleBorder = look == OptionLook.setup
        ? Palette.borderIdle
        : Palette.borderSoft;
    final fill = !selected
        ? Palette.optionFill
        : switch (look) {
            OptionLook.settings => Palette.optionFill,
            OptionLook.settingsFilled => Palette.accentFill,
            OptionLook.setup => accent.fillSelected,
          };
    final idleText = look == OptionLook.setup
        ? Palette.textChoice
        : Palette.textMuted;
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: OptionButton.minTouch,
            minHeight: OptionButton.minTouch,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(widget.radius),
              border: Border.all(
                color: selected || _pressed ? accent.main : idleBorder,
                width: OptionButton.borderWidth,
              ),
            ),
            child: Padding(
              padding: widget.padding,
              child: DefaultTextStyle.merge(
                style: TextStyle(color: selected ? accent.text : idleText),
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
