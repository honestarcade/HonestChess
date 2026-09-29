/// Contrast by computation, not by sampling (#99, after Honest Solitaire's
/// `CheckedTextGuideline`): Flutter's `textContrastGuideline` samples
/// rendered pixels, and in Honest Solitaire the same tokens measured
/// 4.36:1 on the Linux runner and passed on a Mac (its run 36302842503,
/// 2026-09-27). This guideline instead requires every text colour drawn
/// on the screen to be the foreground of a `Palette.textPairs` row, each
/// of which test/guards/contrast_test.dart proves at its ratio by
/// arithmetic, on every machine alike.
library;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:honest_chess/ui/board/board_view.dart';
import 'package:honest_chess/ui/game/pause_overlay.dart';
import 'package:honest_chess/ui/game/tool_row.dart';
import 'package:honest_chess/ui/theme/contrast.dart';
import 'package:honest_chess/ui/theme/palette.dart';
import 'package:honest_chess/ui/widgets/time_control_picker.dart';

/// The opacities a disabled control is drawn at: exempt, as WCAG exempts
/// inactive components.
const List<double> disabledOpacities = [
  disabledToolOpacity,
  disabledPauseButtonOpacity,
  disabledStepperOpacity,
];

/// Every text colour the screen draws is a [Palette.textPairs] foreground
/// of its size class (a colour proven only as large text must be drawn
/// large). An ancestor [Opacity] is folded into the colour's alpha, as the
/// eye sees it. Exempt: piece glyphs (the piece font, or a [PieceGlyph]),
/// disabled controls, and text drawn fully transparent.
class CheckedTextGuideline extends AccessibilityGuideline {
  const CheckedTextGuideline();

  @override
  String get description =>
      'Every text colour is a Palette.textPairs foreground that '
      'test/guards/contrast_test.dart proves';

  @override
  Evaluation evaluate(WidgetTester tester) {
    final proven = <int, Set<TextSize>>{};
    for (final pair in Palette.textPairs) {
      proven.putIfAbsent(pair.fg.toARGB32(), () => {}).add(pair.size);
    }
    var result = const Evaluation.pass();
    final seen = <String>{};
    for (final element in find.byType(RichText).evaluate()) {
      final render = element.renderObject;
      if (render is! RenderParagraph || !render.attached) continue;
      var opacity = 1.0;
      var glyph = false;
      var disabled = false;
      element.visitAncestorElements((a) {
        final w = a.widget;
        if (w is PieceGlyph) glyph = true;
        if (w is Opacity) {
          if (disabledOpacities.contains(w.opacity)) disabled = true;
          opacity *= w.opacity;
        }
        return !glyph && !disabled;
      });
      if (glyph || disabled || opacity == 0) continue;

      void check(InlineSpan span, TextStyle inherited) {
        final style = inherited.merge(span.style);
        if (span is! TextSpan) return;
        final text = span.text ?? '';
        final colour = style.color;
        if (text.trim().isNotEmpty &&
            colour != null &&
            style.fontFamily != Fonts.pieces) {
          final shown = colour.withValues(alpha: colour.a * opacity);
          final size = TextSize.of(
            style.fontSize ?? 14,
            style.fontWeight ?? FontWeight.w400,
          );
          final sizes = proven[shown.toARGB32()];
          final ok =
              shown.a == 0 ||
              (sizes != null &&
                  (sizes.contains(TextSize.normal) || size == TextSize.large));
          final hex = shown.toARGB32().toRadixString(16).toUpperCase();
          if (!ok && seen.add('$hex:$text')) {
            result += Evaluation.fail(
              '"$text" is drawn in #$hex at ${style.fontSize} dp '
              '(${size.name}), which no Palette.textPairs row of its size '
              'proves\n',
            );
          }
        }
        for (final child in span.children ?? const <InlineSpan>[]) {
          check(child, style);
        }
      }

      check(render.text, const TextStyle());
    }
    return result;
  }
}
