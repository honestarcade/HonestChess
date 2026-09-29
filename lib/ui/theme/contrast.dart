/// WCAG 2.x contrast arithmetic, and the rule that moves a failing design
/// colour just far enough to pass (#99, after Honest Solitaire's
/// contrast.dart).
library;

import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// Where WCAG 2.x's sRGB transfer function switches from its linear part
/// to its power part (the value the WCAG 2.x text gives).
const double wcagLinearLimit = 0.03928;

/// Body text: WCAG 2.x AA.
const double normalTextRatio = 4.5;

/// Large text (18 dp and up, or bold at 14 dp and up): WCAG 2.x AA.
const double largeTextRatio = 3.0;

/// A board's light square against its dark square: the brand sheet's
/// promise for every board pair.
const double boardPairRatio = 4.0;

/// How far past its threshold a moved colour lands, so rounding the ratio
/// for display can never show a passing colour as failing.
const double shiftMargin = 0.05;

/// The size class a text colour is held to.
enum TextSize {
  normal(normalTextRatio),
  large(largeTextRatio);

  const TextSize(this.minRatio);

  final double minRatio;

  /// The class of text drawn at [fontSize] dp in [weight]: large at 18 dp
  /// and up, or at 14 dp and up when bold.
  static TextSize of(double fontSize, FontWeight weight) =>
      fontSize >= 18 || (fontSize >= 14 && weight.value >= 700)
      ? large
      : normal;
}

/// One text colour on one background: [fg] (translucent or not) drawn over
/// [on], a stack of fills from the opaque bottom one up, each translucent
/// fill composited over the ones below it.
final class TextPair {
  const TextPair(this.name, this.fg, this.on, {this.size = TextSize.normal});

  final String name;
  final Color fg;
  final List<Color> on;
  final TextSize size;

  /// The opaque colour [fg] sits on.
  Color get background => surfaceOf(on);

  /// [fg] as the eye sees it on [background].
  Color get seen => composite(fg, background);

  double get ratio => contrastRatio(seen, background);
}

double _linear(double channel) => channel <= wcagLinearLimit
    ? channel / 12.92
    : math.pow((channel + 0.055) / 1.055, 2.4).toDouble();

/// WCAG relative luminance of [c], whose alpha is ignored.
double relativeLuminance(Color c) =>
    0.2126 * _linear(c.r) + 0.7152 * _linear(c.g) + 0.0722 * _linear(c.b);

/// The WCAG contrast ratio of two opaque colours, 1 to 21.
double contrastRatio(Color a, Color b) {
  final la = relativeLuminance(a);
  final lb = relativeLuminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// [fg] alpha-blended over the opaque [bg], rounded to 8-bit channels as
/// the screen shows it.
Color composite(Color fg, Color bg) {
  final a = fg.a;
  int mix(double f, double b) => ((f * a + b * (1 - a)) * 255).round();
  return Color.fromARGB(255, mix(fg.r, bg.r), mix(fg.g, bg.g), mix(fg.b, bg.b));
}

/// The opaque colour of [layers], an opaque bottom fill with translucent
/// fills over it in order.
Color surfaceOf(List<Color> layers) {
  if (layers.isEmpty || layers.first.a < 1) {
    throw ArgumentError.value(
      layers,
      'layers',
      'must start with an opaque fill',
    );
  }
  return layers.skip(1).fold(layers.first, (bg, fill) => composite(fill, bg));
}

// CIELAB (D65), for moving a colour's lightness at a fixed hue and chroma.

const double _xn = 0.95047, _yn = 1.0, _zn = 1.08883;
const double _delta = 6 / 29;

double _srgbToLinear(double c) =>
    c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

double _linearToSrgb(double c) =>
    c <= 0.0031308 ? 12.92 * c : 1.055 * math.pow(c, 1 / 2.4) - 0.055;

double _f(double t) => t > _delta * _delta * _delta
    ? math.pow(t, 1 / 3).toDouble()
    : t / (3 * _delta * _delta) + 4 / 29;

double _fInverse(double t) =>
    t > _delta ? t * t * t : 3 * _delta * _delta * (t - 4 / 29);

/// [c] as CIE L*C*h (lightness, chroma, hue in radians).
({double l, double c, double h}) toLch(Color c) {
  final r = _srgbToLinear(c.r), g = _srgbToLinear(c.g), b = _srgbToLinear(c.b);
  final x = 0.4124 * r + 0.3576 * g + 0.1805 * b;
  final y = 0.2126 * r + 0.7152 * g + 0.0722 * b;
  final z = 0.0193 * r + 0.1192 * g + 0.9505 * b;
  final fx = _f(x / _xn), fy = _f(y / _yn), fz = _f(z / _zn);
  final aStar = 500 * (fx - fy), bStar = 200 * (fy - fz);
  return (
    l: 116 * fy - 16,
    c: math.sqrt(aStar * aStar + bStar * bStar),
    h: math.atan2(bStar, aStar),
  );
}

(double, double, double) _linearRgb(double l, double chroma, double h) {
  final fy = (l + 16) / 116;
  final fx = fy + chroma * math.cos(h) / 500;
  final fz = fy - chroma * math.sin(h) / 200;
  final x = _xn * _fInverse(fx),
      y = _yn * _fInverse(fy),
      z = _zn * _fInverse(fz);
  return (
    3.2406 * x - 1.5372 * y - 0.4986 * z,
    -0.9689 * x + 1.8758 * y + 0.0415 * z,
    0.0557 * x - 0.2040 * y + 1.0570 * z,
  );
}

bool _inGamut((double, double, double) rgb) =>
    rgb.$1 >= -1e-9 &&
    rgb.$1 <= 1 + 1e-9 &&
    rgb.$2 >= -1e-9 &&
    rgb.$2 <= 1 + 1e-9 &&
    rgb.$3 >= -1e-9 &&
    rgb.$3 <= 1 + 1e-9;

/// The opaque 8-bit colour at L*C*h, with its chroma reduced as little as
/// needed to stay inside sRGB.
Color fromLch(double l, double chroma, double h) {
  var rgb = _linearRgb(l, chroma, h);
  if (!_inGamut(rgb)) {
    var lo = 0.0, hi = chroma;
    for (var i = 0; i < 40; i++) {
      final mid = (lo + hi) / 2;
      if (_inGamut(_linearRgb(l, mid, h))) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    rgb = _linearRgb(l, lo, h);
  }
  int channel(double v) =>
      (_linearToSrgb(v.clamp(0.0, 1.0)) * 255).round().clamp(0, 255);
  return Color.fromARGB(255, channel(rgb.$1), channel(rgb.$2), channel(rgb.$3));
}

/// One background a colour must read on: [minRatio] over [background],
/// with the colour drawn at [opacity] (an ancestor's fade, 1 for none).
typedef ContrastTarget = ({Color background, double minRatio, double opacity});

/// Whether [colour] reaches each target's ratio plus [shiftMargin].
bool clearsAll(Color colour, Iterable<ContrastTarget> targets) =>
    targets.every((t) {
      final shown = composite(
        colour.withValues(alpha: colour.a * t.opacity),
        t.background,
      );
      return contrastRatio(shown, t.background) >= t.minRatio + shiftMargin;
    });

/// [design] moved in CIELAB lightness, 0.1 at a time (lighter when
/// [lighter]), at its own hue and chroma, to the first 8-bit colour that
/// clears every one of [targets]; [design] itself when it already does.
Color shiftLightness(
  Color design,
  Iterable<ContrastTarget> targets, {
  required bool lighter,
}) {
  final lch = toLch(design);
  var colour = design;
  var l = lch.l;
  while (!clearsAll(colour, targets)) {
    l += lighter ? 0.1 : -0.1;
    if (l < 0 || l > 100) {
      throw StateError('no lightness of $design clears $targets');
    }
    colour = fromLch(l, lch.c, lch.h);
  }
  return colour;
}

/// Translucent fill [design] moved in CIELAB lightness, 0.1 at a time
/// (lighter when [lighter]), at its own hue, chroma and alpha, to the
/// first 8-bit colour for which [clears] holds (the text drawn over the
/// fill reaching its ratios); [design] itself when it already does.
Color shiftFillLightness(
  Color design,
  bool Function(Color fill) clears, {
  required bool lighter,
}) {
  final lch = toLch(design);
  var colour = design;
  var l = lch.l;
  while (!clears(colour)) {
    l += lighter ? 0.1 : -0.1;
    if (l < 0 || l > 100) {
      throw StateError('no lightness of $design clears its text');
    }
    colour = fromLch(l, lch.c, lch.h).withValues(alpha: design.a);
  }
  return colour;
}

/// Translucent [design] made more opaque, one 8-bit alpha step at a time,
/// to the first alpha that clears every one of [targets]; its colour is
/// kept.
Color raiseAlpha(Color design, Iterable<ContrastTarget> targets) {
  var alpha = (design.a * 255).round();
  var colour = design;
  while (!clearsAll(colour, targets)) {
    alpha++;
    if (alpha > 255) {
      throw StateError('no alpha of $design clears $targets');
    }
    colour = design.withAlpha(alpha);
  }
  return colour;
}
