import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../theme/palette.dart';

/// A CSS `radial-gradient(<rx> <ry> at <cx> <cy>, …)` as fractions of the
/// box it fills: the ellipse's [centre] and its [radii], and the colour
/// [stops] along the radius. Past the ellipse the last colour continues,
/// as CSS draws it.
class ScreenGradient {
  const ScreenGradient({
    required this.centre,
    required this.radii,
    required this.stops,
  });

  final Offset centre;
  final Size radii;
  final List<(Color, double)> stops;

  /// About Honest Arcade's: `110% 80% at 78% 12%`.
  static const aboutStudio = ScreenGradient(
    centre: Offset(0.78, 0.12),
    radii: Size(1.10, 0.80),
    stops: [
      (Palette.gradientInner, 0),
      (Palette.screenBg, .58),
      (Palette.gradientOuter, 1),
    ],
  );

  /// The menu's: `110% 90% at 24% 12%`.
  static const menu = ScreenGradient(
    centre: Offset(0.24, 0.12),
    radii: Size(1.10, 0.90),
    stops: [
      (Palette.gradientInner, 0),
      (Palette.screenBg, .58),
      (Palette.gradientOuter, 1),
    ],
  );

  /// The splash's: `120% 110% at 50% 18%`, [Palette.screenBg] at 55%.
  static const splash = ScreenGradient(
    centre: Offset(0.5, 0.18),
    radii: Size(1.20, 1.10),
    stops: [
      (Palette.gradientInner, 0),
      (Palette.screenBg, .55),
      (Palette.gradientOuter, 1),
    ],
  );

  /// The gradient over [rect]: a circle of radius rx × width about the
  /// centre, squashed vertically into the ellipse by a transform.
  RadialGradient over(Rect rect) {
    final rx = radii.width * rect.width;
    final ry = radii.height * rect.height;
    return RadialGradient(
      center: Alignment(centre.dx * 2 - 1, centre.dy * 2 - 1),
      radius: rect.shortestSide == 0 ? 0 : rx / rect.shortestSide,
      colors: [for (final (c, _) in stops) c],
      stops: [for (final (_, s) in stops) s],
      transform: _EllipseTransform(
        centre:
            rect.topLeft +
            Offset(centre.dx * rect.width, centre.dy * rect.height),
        yScale: rx == 0 ? 1 : ry / rx,
      ),
    );
  }
}

class _EllipseTransform extends GradientTransform {
  const _EllipseTransform({required this.centre, required this.yScale});

  final Offset centre;
  final double yScale;

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.fromFloat64List(
        Float64List.fromList([
          1, 0, 0, 0, //
          0, yScale, 0, 0, //
          0, 0, 1, 0, //
          0, centre.dy * (1 - yScale), 0, 1,
        ]),
      );
}

/// Paints [gradient] over the whole box behind [child]. The screens using
/// it fill the window, behind the system bars; their content keeps its own
/// safe-area padding inside.
class ScreenBackground extends StatelessWidget {
  const ScreenBackground({super.key, required this.gradient, this.child});

  final ScreenGradient gradient;
  final Widget? child;

  @override
  Widget build(BuildContext context) => SizedBox.expand(
    // Expanded so the gradient covers the window even when the content is
    // shorter than it.
    child: CustomPaint(painter: _GradientPainter(gradient), child: child),
  );
}

class _GradientPainter extends CustomPainter {
  const _GradientPainter(this.gradient);

  final ScreenGradient gradient;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()..shader = gradient.over(rect).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_GradientPainter old) => old.gradient != gradient;
}
