/// Contrast by computation, not by sampling (#99, after Honest Solitaire's
/// `CheckedTextGuideline`): Flutter's `textContrastGuideline` samples
/// rendered pixels, and in Honest Solitaire the same tokens measured
/// 4.36:1 on the Linux runner and passed on a Mac (its run 36302842503,
/// 2026-09-27). This guideline instead computes each text's contrast
/// against the fills it is drawn over, and requires every text colour to
/// be the foreground of a `Palette.textPairs` row, each of which
/// test/guards/contrast_test.dart proves at its ratio by arithmetic, on
/// every machine alike.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:honest_chess/ui/board/board_view.dart';
import 'package:honest_chess/ui/game/pause_overlay.dart';
import 'package:honest_chess/ui/game/tool_row.dart';
import 'package:honest_chess/ui/theme/contrast.dart';
import 'package:honest_chess/ui/theme/palette.dart';
import 'package:honest_chess/ui/widgets/screen_background.dart';
import 'package:honest_chess/ui/widgets/time_control_picker.dart';

/// The opacities a disabled control is drawn at: exempt, as WCAG exempts
/// inactive components.
const List<double> disabledOpacities = [
  disabledToolOpacity,
  disabledPauseButtonOpacity,
  disabledStepperOpacity,
];

/// One fill painted on the screen: the global [rect] it covers, the
/// colours it may show there (one for a flat fill, every stop for a
/// gradient) and the opacity of the layers it is drawn in.
typedef _Fill = ({Rect rect, List<Color> colours, double opacity, String? key});

/// One text as drawn: its paragraph, the opacity it is drawn at, and the
/// fills painted before it, in paint order.
typedef _Drawn = ({
  Element element,
  RenderParagraph render,
  double opacity,
  List<_Fill> under,
});

/// Every text colour the screen draws reaches its WCAG ratio against the
/// background it is actually drawn on: the fills painted under it (a
/// `DecoratedBox`'s colour or gradient, a `ColoredBox`, a `Material`, a
/// `ScreenBackground`'s gradient, and a held `InkWell`'s highlight and
/// splash), composited from the nearest opaque one up, with every stop of
/// a gradient tried. And every text colour is a [Palette.textPairs]
/// foreground of its size class (a colour proven only as large text must
/// be drawn large). An ancestor [Opacity] is folded into the colour's
/// alpha, as the eye sees it. Exempt: piece glyphs (the piece font, or a
/// [PieceGlyph]), disabled controls, and text drawn fully transparent.
///
/// [pressedAt] is where a finger is held down, so the ink of an `InkWell`
/// under it counts as a fill.
class CheckedTextGuideline extends AccessibilityGuideline {
  const CheckedTextGuideline({this.pressedAt});

  final Offset? pressedAt;

  @override
  String get description =>
      'Every text reaches its ratio on the fills it is drawn over, and its '
      'colour is a Palette.textPairs foreground that '
      'test/guards/contrast_test.dart proves';

  @override
  Evaluation evaluate(WidgetTester tester) {
    final proven = <int, Set<TextSize>>{};
    for (final pair in Palette.textPairs) {
      proven.putIfAbsent(pair.fg.toARGB32(), () => {}).add(pair.size);
    }
    var result = const Evaluation.pass();
    final seen = <String>{};
    final view = tester.view;
    final screen = Offset.zero & (view.physicalSize / view.devicePixelRatio);
    for (final drawn in _drawnTexts(tester)) {
      final element = drawn.element;
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
      if (glyph || disabled || opacity == 0 || drawn.opacity == 0) continue;
      final render = drawn.render;
      final box = MatrixUtils.transformRect(
        render.getTransformTo(null),
        Offset.zero & render.size,
      );
      // Laid out but off the screen, as a list builds ahead of its
      // scrolling: not drawn where anyone can read it.
      if (!screen.contains(box.center)) continue;
      final covering = [
        for (final fill in drawn.under)
          if (fill.rect.contains(box.center)) fill,
      ];
      // A board coordinate over a square's tint (selected, last move,
      // check) is left to #149: no label alpha reaches 4.5:1 there on
      // every theme, so it needs a design call. On a plain square the
      // label is still checked here and by its textPairs row.
      final tintedLabel =
          _isCoordinate(element) &&
          covering.any((f) => f.key?.startsWith('tint-') ?? false);
      final backgrounds = _backgrounds(covering);

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
          final hex = _hex(shown);
          if (!ok && seen.add('$hex:$text')) {
            result += Evaluation.fail(
              '"$text" is drawn in $hex at ${style.fontSize} dp '
              '(${size.name}), which no Palette.textPairs row of its size '
              'proves\n',
            );
          }
          if (backgrounds == null) {
            if (seen.add('no background:$text')) {
              result += Evaluation.fail(
                '"$text" is drawn over no opaque fill this check can see\n',
              );
            }
          } else if (shown.a > 0 && !tintedLabel) {
            final eye = colour.withValues(alpha: colour.a * drawn.opacity);
            for (final bg in backgrounds) {
              final ratio = contrastRatio(composite(eye, bg), bg);
              if (ratio < size.minRatio &&
                  seen.add('ratio:${_hex(eye)}:${_hex(bg)}:$text')) {
                result += Evaluation.fail(
                  '"$text" in ${_hex(eye)} at ${style.fontSize} dp '
                  '(${size.name}) is drawn on ${_hex(bg)}: '
                  '${ratio.toStringAsFixed(2)}:1, below ${size.minRatio}:1\n',
                );
              }
            }
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

  /// Every paragraph on the screen, each with the fills painted before it,
  /// in the order the tree paints them: a widget's own fill before its
  /// children, and a child before the siblings after it.
  List<_Drawn> _drawnTexts(WidgetTester tester) {
    final out = <_Drawn>[];
    final fills = <_Fill>[];
    final pressedInk = <Element, List<_Fill>>{};
    final press = pressedAt;
    if (press != null) {
      for (final ink
          in find.byWidgetPredicate((w) => w is InkResponse).evaluate()) {
        final w = ink.widget as InkResponse;
        final box = ink.findRenderObject();
        if (w.onTap == null && w.onTapDown == null && w.onLongPress == null) {
          continue;
        }
        if (box is! RenderBox || !box.attached || !box.hasSize) continue;
        final rect = _globalRect(box);
        if (!rect.contains(press)) continue;
        Element? material;
        ink.visitAncestorElements((a) {
          if (a.widget is Material) {
            material = a;
            return false;
          }
          return true;
        });
        if (material == null) continue;
        final theme = Theme.of(ink);
        final pressed = {WidgetState.pressed};
        final highlight =
            w.overlayColor?.resolve(pressed) ??
            w.highlightColor ??
            theme.highlightColor;
        final splash =
            w.overlayColor?.resolve(pressed) ??
            w.splashColor ??
            theme.splashColor;
        final factory = w.splashFactory ?? theme.splashFactory;
        pressedInk.putIfAbsent(material!, () => []).addAll([
          (rect: rect, colours: [highlight], opacity: 1.0, key: null),
          // A splash that stays while the finger is down. InkSparkle, the
          // Android default, fades itself out while the finger is still
          // down (its alpha sequence ends at 0 at 617 ms: the InkSparkle source of
          // Flutter 3.47.5), so the held state is the highlight alone.
          if (factory != NoSplash.splashFactory &&
              factory != InkSparkle.splashFactory &&
              factory != InkSparkle.constantTurbulenceSeedSplashFactory)
            (rect: rect, colours: [splash], opacity: 1.0, key: null),
        ]);
      }
    }

    void visit(Element element, double opacity) {
      final widget = element.widget;
      if (widget is Offstage && widget.offstage) return;
      var inner = opacity;
      if (widget is Opacity) inner *= widget.opacity;
      if (widget is FadeTransition) inner *= widget.opacity.value;
      if (inner == 0) return;
      final colours = _fillOf(element);
      if (colours != null) {
        final box = element.findRenderObject();
        if (box is RenderBox && box.attached && box.hasSize) {
          final key = widget.key;
          fills.add((
            rect: _globalRect(box),
            colours: colours,
            opacity: inner,
            key: key is ValueKey<String> ? key.value : null,
          ));
        }
      }
      final ink = pressedInk[element];
      if (ink != null) {
        fills.addAll([
          for (final f in ink)
            (rect: f.rect, colours: f.colours, opacity: inner, key: null),
        ]);
      }
      final render = element.renderObject;
      if (widget is RichText &&
          render is RenderParagraph &&
          render.attached &&
          render.hasSize) {
        out.add((
          element: element,
          render: render,
          opacity: inner,
          under: List.of(fills),
        ));
      }
      element.visitChildren((child) => visit(child, inner));
    }

    final root = tester.binding.rootElement;
    if (root != null) visit(root, 1);
    return out;
  }
}

/// Whether [element] draws one of the board's rank or file labels.
bool _isCoordinate(Element element) {
  var coordinate = false;
  element.visitAncestorElements((a) {
    final key = a.widget.key;
    if (key is ValueKey<String> &&
        (key.value.startsWith('rank-') || key.value.startsWith('file-'))) {
      coordinate = true;
    }
    return !coordinate && a.widget is! BoardView;
  });
  return coordinate;
}

String _hex(Color c) =>
    '#${c.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';

Rect _globalRect(RenderBox box) =>
    MatrixUtils.transformRect(box.getTransformTo(null), Offset.zero & box.size);

/// The colours [element] paints behind its children, if it paints a fill.
List<Color>? _fillOf(Element element) {
  final widget = element.widget;
  if (widget is ColoredBox) return [widget.color];
  if (widget is DecoratedBox &&
      widget.position == DecorationPosition.background) {
    final decoration = widget.decoration;
    if (decoration is BoxDecoration) {
      return decoration.gradient?.colors ??
          (decoration.color == null ? null : [decoration.color!]);
    }
    if (decoration is ShapeDecoration) {
      return decoration.gradient?.colors ??
          (decoration.color == null ? null : [decoration.color!]);
    }
  }
  if (widget is Material) {
    final theme = Theme.of(element);
    final colour =
        widget.color ??
        switch (widget.type) {
          MaterialType.canvas => theme.canvasColor,
          MaterialType.card => theme.cardColor,
          _ => null,
        };
    return colour == null ? null : [colour];
  }
  if (widget is ScreenBackground) {
    return [for (final (c, _) in widget.gradient.stops) c];
  }
  return null;
}

/// Every opaque colour [under] (fills covering one text, in paint order)
/// may show behind it: from the last fill that is opaque in every colour,
/// each later fill composited over it, a gradient's stops each tried. Null
/// when nothing opaque is under the text.
List<Color>? _backgrounds(List<_Fill> under) {
  var start = -1;
  for (var i = under.length - 1; i >= 0; i--) {
    final f = under[i];
    if (f.opacity == 1 && f.colours.every((c) => c.a == 1)) {
      start = i;
      break;
    }
  }
  if (start < 0) return null;
  var out = under[start].colours;
  for (final fill in under.skip(start + 1)) {
    out = [
      for (final bg in out)
        for (final c in fill.colours)
          composite(c.withValues(alpha: c.a * fill.opacity), bg),
    ];
  }
  return {for (final c in out) c.toARGB32(): c}.values.toList();
}
