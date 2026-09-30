// Every piece sits in the middle of its square (#163): each glyph, in each
// piece style, is drawn to an image and the centre of its ink — the pixels
// it actually paints — must land on the square's centre, with all of the
// ink inside the square. The complement: a glyph laid out on its font's
// own baseline, unshifted, is off centre by more than the tolerance.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:honest_chess/engine/engine.dart';
import 'package:honest_chess/ui/board/board_options.dart';
import 'package:honest_chess/ui/board/board_view.dart';

/// Image pixels per logical pixel, so the ink box is measured to a quarter
/// of a logical pixel.
const _ratio = 4.0;

/// The farthest an ink centre may sit from the square's centre, as a share
/// of the square's side.
const _tolerance = 0.02;

/// Square sides to draw at: the smallest the guidelines suite allows, the
/// 360-wide phone's, the design's and a tablet's.
const _sides = [30.0, 39.0, 46.0, 60.0];

/// [piece]'s ink box, in logical pixels from the square's top left, when
/// the board draws it on a square of [side] in [style]. With [shifted]
/// false, the glyph is laid out as the text engine places it, unmoved.
Future<Rect> inkBox(
  WidgetTester tester,
  Piece piece,
  PieceStyle style,
  double side, {
  bool shifted = true,
}) async {
  final boundary = GlobalKey();
  final drawn = boardPiece(piece, style, side, 1);
  // Black on nothing, with no outline or halo: every opaque pixel is ink.
  Widget glyph = PieceGlyph(
    piece: piece,
    style: style,
    fontSize: drawn.fontSize,
    colour: const Color(0xFF000000),
    shadows: const [],
  );
  if (!shifted) {
    glyph = Transform.translate(
      offset: -pieceInkShift(piece, style) * drawn.fontSize,
      child: glyph,
    );
  }
  // A canvas twice the square's side, so ink spilling out of the square is
  // measured rather than cut off; the square is its middle.
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: RepaintBoundary(
          key: boundary,
          child: SizedBox.square(
            dimension: side * 2,
            child: Center(
              child: SizedBox.square(
                dimension: side,
                child: Center(child: glyph),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  final render =
      boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final (width, height, pixels) = (await tester.runAsync(() async {
    final image = await render.toImage(pixelRatio: _ratio);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return (image.width, image.height, bytes!);
  }))!;
  var (left, top, right, bottom) = (width, height, -1, -1);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      if (pixels.getUint8((y * width + x) * 4 + 3) < 128) continue;
      if (x < left) left = x;
      if (x > right) right = x;
      if (y < top) top = y;
      if (y > bottom) bottom = y;
    }
  }
  expect(right, greaterThanOrEqualTo(0), reason: 'centring: $piece has ink');
  return Rect.fromLTRB(
    left / _ratio - side / 2,
    top / _ratio - side / 2,
    (right + 1) / _ratio - side / 2,
    (bottom + 1) / _ratio - side / 2,
  );
}

void main() {
  for (final style in PieceStyle.values) {
    testWidgets('every ${style.name} piece is centred in its square', (
      tester,
    ) async {
      for (final side in _sides) {
        for (final kind in PieceKind.values) {
          final piece = Piece.of(Colour.black, kind);
          final ink = await inkBox(tester, piece, style, side);
          final at = '${kind.name}, ${style.name}, ${side.toInt()} dp square';
          final off = ink.center - Offset(side / 2, side / 2);
          expect(
            off.dx.abs(),
            lessThanOrEqualTo(side * _tolerance),
            reason: 'centring: ink centred across the square ($at, $ink)',
          );
          expect(
            off.dy.abs(),
            lessThanOrEqualTo(side * _tolerance),
            reason: 'centring: ink centred down the square ($at, $ink)',
          );
          expect(
            ink.left >= 0 &&
                ink.top >= 0 &&
                ink.right <= side &&
                ink.bottom <= side,
            isTrue,
            reason: 'centring: no ink outside the square ($at, $ink)',
          );
        }
      }
    });

    testWidgets('unshifted, some ${style.name} piece is off centre '
        '(the complement)', (tester) async {
      var worst = 0.0;
      for (final kind in PieceKind.values) {
        final ink = await inkBox(
          tester,
          Piece.of(Colour.black, kind),
          style,
          46,
          shifted: false,
        );
        final off = ink.center - const Offset(23, 23);
        worst = [
          worst,
          off.dx.abs(),
          off.dy.abs(),
        ].reduce((a, b) => a > b ? a : b);
      }
      expect(
        worst,
        greaterThan(46 * _tolerance),
        reason:
            'centring: the font\'s own baseline is off centre, so the '
            'test can see a glyph that is',
      );
    });
  }
}
