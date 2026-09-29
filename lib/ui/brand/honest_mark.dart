import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import 'svg_path.dart';

/// One corner of the mark: its stroke colour and its SVG path data.
typedef MarkCorner = ({Color stroke, String d});

/// The Honest Arcade mark, drawn from the brand sources' own path data so
/// the in-app marks match the launcher icon and the native launch screen:
/// [HonestMark.arcade] is `assets/brand/STUDIO-MARK.svg`'s four corners,
/// [HonestMark.chess] the launcher's corners-and-rook group (the
/// `mark:begin` / `mark:end` block of `assets/brand/android-foreground.svg`).
/// test/ui/brand/honest_mark_test.dart holds these strings to the files.
/// The caller sizes it (already scaled); it is decoration, so it is
/// excluded from semantics.
class HonestMark extends StatelessWidget {
  /// The studio's four corners filling a [size] square.
  const HonestMark.arcade(this.size, {super.key}) : withRook = false;

  /// The four corners and the rook filling a [size] square.
  const HonestMark.chess(this.size, {super.key}) : withRook = true;

  final double size;
  final bool withRook;

  /// The SVGs' 64-unit view box.
  static const box = 64.0;

  /// The corners' stroke: width 6 in the box, round caps and joins.
  static const strokeWidth = 6.0;

  static const List<MarkCorner> corners = [
    (stroke: Color(0xFF00D6B4), d: 'M 3 21 L 3 10 A 7 7 0 0 1 10 3 L 21 3'),
    (stroke: Color(0xFF8448FC), d: 'M 61 21 L 61 10 A 7 7 0 0 0 54 3 L 43 3'),
    (stroke: Color(0xFF0076F1), d: 'M 61 43 L 61 54 A 7 7 0 0 1 54 61 L 43 61'),
    (stroke: Color(0xFF0F3E86), d: 'M 3 43 L 3 54 A 7 7 0 0 0 10 61 L 21 61'),
  ];

  static const rookFill = Color(0xFF00D6B4);

  /// The rook's scale about the box centre (32, 32), as the SVG's
  /// `translate(32,32) scale(1.32) translate(-32,-32)` transform.
  static const rookScale = 1.32;

  static const rookD =
      'M 22.6 15 H 26.5 V 18.8 H 29.9 V 15 H 34.1 V 18.8 H 37.5 V 15 H 41.4 '
      'V 23.1 L 38.4 25.6 V 35 L 41.4 39.2 V 42.2 H 43.1 V 48.2 H 20.9 '
      'V 42.2 H 22.6 V 39.2 L 25.6 35 V 25.6 L 22.6 23.1 Z';

  /// The corners' paths in the box, parsed once.
  static final List<Path> cornerPaths = [
    for (final c in corners) parseSvgPath(c.d),
  ];

  /// The rook's path in the box, scaled about its centre, parsed once.
  static final Path rookPath = parseSvgPath(rookD).transform(
    Float64List.fromList([
      rookScale, 0, 0, 0, //
      0, rookScale, 0, 0, //
      0, 0, 1, 0, //
      _rookShift, _rookShift, 0, 1,
    ]),
  );

  /// Where the scale about (32, 32) moves the origin.
  static const _rookShift = box / 2 * (1 - rookScale);

  /// How a corner is stroked, in the box's units.
  static Paint cornerPaint(Color colour) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = strokeWidth
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..color = colour;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(
      size: Size.square(size),
      painter: _MarkPainter(withRook: withRook),
    ),
  );
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter({required this.withRook});

  final bool withRook;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.shortestSide / HonestMark.box);
    for (final (i, corner) in HonestMark.corners.indexed) {
      canvas.drawPath(
        HonestMark.cornerPaths[i],
        HonestMark.cornerPaint(corner.stroke),
      );
    }
    if (withRook) {
      canvas.drawPath(
        HonestMark.rookPath,
        Paint()..color = HonestMark.rookFill,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.withRook != withRook;
}
