import 'dart:math' as math;
import 'dart:ui' show SemanticsRole;

import 'package:flutter/material.dart';

import '../theme/palette.dart';
import 'option_button.dart';

/// What a screen reader says for the tab at [index] of [count]:
/// "The pieces, tab, 1 of 2". The label carries the position, as Flutter's
/// own TabBar's does, because Flutter 3.47.5's Android embedding gives the
/// tab role no Android class to speak (its RoleConfiguratorFactory, read
/// 2026-09-29).
String tabSpeech(String label, int index, int count) =>
    '$label, tab, ${index + 1} of $count';

/// The design's two-button tab pill (How to play's, Statistics'), a tab
/// bar to a screen reader: one tab per [values] entry, labelled by
/// [labelOf], the [selected] one filled teal. Tapping another calls [onChanged] at once; tapping the
/// selected one does nothing. Each tab is keyed `<keyPrefix>-tab-<name>`.
///
/// The pill is drawn at the design's size, scaled by [scale], and centred
/// in a slot at least [OptionButton.minTouch] tall; each tab's hit region is its half of
/// that slot, so a screen placing the pill shrinks its gaps above and below
/// by [overhang] to keep the drawn pill where the design has it.
class SegmentedTabs<T extends Enum> extends StatelessWidget {
  const SegmentedTabs({
    super.key,
    required this.values,
    required this.labelOf,
    required this.selected,
    required this.onChanged,
    required this.keyPrefix,
    this.scale = 1,
  });

  final List<T> values;
  final String Function(T) labelOf;
  final T selected;
  final ValueChanged<T> onChanged;
  final String keyPrefix;
  final double scale;

  /// The design's numbers: the pill's padding, the gap between buttons, a
  /// button's vertical padding and label size.
  static const pillPadding = 4.0;
  static const buttonGap = 7.0;
  static const buttonPadding = 10.0;
  static const labelSize = 12.5;

  /// The pill's drawn height at [scale].
  static double drawnHeight(double scale) =>
      (2 * pillPadding + 2 * buttonPadding + labelSize) * scale;

  /// The slot's height at [scale]: the drawn pill, or [OptionButton.minTouch]
  /// if taller.
  static double slotHeight(double scale) =>
      math.max(OptionButton.minTouch, drawnHeight(scale));

  /// How far the slot reaches past the drawn pill, above and below.
  static double overhang(double scale) =>
      (slotHeight(scale) - drawnHeight(scale)) / 2;

  @override
  Widget build(BuildContext context) {
    final slot = slotHeight(scale);
    final drawn = drawnHeight(scale);
    final edge = pillPadding * scale;
    final halfGap = buttonGap * scale / 2;
    return SizedBox(
      height: slot,
      child: Stack(
        children: [
          Positioned.fill(
            child: Center(
              child: Container(
                height: drawn,
                decoration: BoxDecoration(
                  color: Palette.cardFill,
                  borderRadius: BorderRadius.circular(12 * scale),
                ),
              ),
            ),
          ),
          Semantics(
            container: true,
            explicitChildNodes: true,
            role: SemanticsRole.tabBar,
            child: Row(
              children: [
                for (final (i, value) in values.indexed)
                  Expanded(
                    child: _Tab(
                      key: Key('$keyPrefix-tab-${value.name}'),
                      label: labelOf(value),
                      spoken: tabSpeech(labelOf(value), i, values.length),
                      selected: value == selected,
                      onTap: value == selected ? null : () => onChanged(value),
                      padding: EdgeInsets.only(
                        left: i == 0 ? edge : halfGap,
                        right: i == values.length - 1 ? edge : halfGap,
                      ),
                      buttonHeight: drawn - 2 * edge,
                      scale: scale,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Tab extends StatefulWidget {
  const _Tab({
    super.key,
    required this.label,
    required this.spoken,
    required this.selected,
    required this.onTap,
    required this.padding,
    required this.buttonHeight,
    required this.scale,
  });

  final String label;
  final String spoken;
  final bool selected;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final double buttonHeight;
  final double scale;

  @override
  State<_Tab> createState() => _TabState();
}

class _TabState extends State<_Tab> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final ink = selected
        ? Palette.onTeal
        : _pressed
        ? Palette.teal
        : Palette.textBody;
    return Semantics(
      container: true,
      role: SemanticsRole.tab,
      inMutuallyExclusiveGroup: true,
      selected: selected,
      label: widget.spoken,
      onTap: widget.onTap ?? () {},
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap ?? () {},
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        child: Padding(
          padding: widget.padding,
          child: Center(
            child: Container(
              height: widget.buttonHeight,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? Palette.teal : null,
                borderRadius: BorderRadius.circular(9 * widget.scale),
              ),
              child: Text(
                widget.label,
                maxLines: 1,
                style: TextStyle(
                  fontFamily: Fonts.outfit,
                  fontWeight: FontWeight.w600,
                  fontSize: SegmentedTabs.labelSize * widget.scale,
                  height: 1,
                  leadingDistribution: TextLeadingDistribution.even,
                  color: ink,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
