import 'dart:math' as math;

import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';

import 'package:honest_chess/engine/engine.dart';
import 'package:honest_chess/ui/board/board_options.dart';
import 'package:honest_chess/ui/theme/palette.dart';

/// The width of the design's phone frame; sizes inside the board scale by
/// `width / designWidth`.
const double designWidth = 390;

/// The design's margin either side of the board (`boardX`).
const double boardMargin = 8;

/// The design's board corner radius.
const double boardRadius = 10;

/// The side of one square for a board given [size]: the full width less the
/// design's margins, in whole pixels so the squares tile without seams, or
/// the height's eighth when the height is the tighter bound.
double squareSide(Size size) {
  var side = ((size.width - 2 * boardMargin) / 8).floorToDouble();
  if (size.height.isFinite && size.height < side * 8) {
    side = (size.height / 8).floorToDouble();
  }
  return math.max(side, 0);
}

/// The character drawn for [piece] in [style]. The chess symbols carry
/// U+FE0E, the text-presentation selector, so no platform reads them as
/// emoji; the flat style's letters need none.
String pieceGlyph(Piece piece, PieceStyle style) => switch (style) {
  PieceStyle.classic => '${_filled[piece.kind.index]}\u{FE0E}',
  PieceStyle.outline => '${_hollow[piece.kind.index]}\u{FE0E}',
  PieceStyle.flat => piece.kind.letter.toUpperCase(),
};

// Indexed by PieceKind: pawn, knight, bishop, rook, queen, king.
const _filled = ['♟', '♞', '♝', '♜', '♛', '♚'];
const _hollow = ['♙', '♘', '♗', '♖', '♕', '♔'];

/// A face's line metrics, in thousandths of an em.
final class _Face {
  const _Face({required this.ascent, required this.descent});

  final int ascent;
  final int descent;

  /// Where the baseline falls in a `height: 1` line, from its top, in ems:
  /// the line is one em and the face's ascent and descent share it.
  double get baseline => ascent / (ascent + descent);
}

/// One glyph's advance and ink box, in thousandths of an em, y up from
/// the baseline.
typedef _Ink = ({int advance, int left, int bottom, int right, int top});

// hhea ascent/descent and each glyph's outline bounds, read from
// assets/fonts/pieces/HonestPieces.ttf and IBMPlexMono-SemiBold.ttf (the
// flat style's w600) with fontTools' BoundsPen on 2026-09-30. The filled
// and hollow symbols share their boxes. Indexed by PieceKind.
const _pieceFace = _Face(ascent: 1069, descent: 630);
const _symbolInk = <_Ink>[
  (advance: 1000, left: 186, bottom: 0, right: 814, top: 755),
  (advance: 1000, left: 160, bottom: 0, right: 840, top: 767),
  (advance: 1000, left: 153, bottom: -49, right: 847, top: 741),
  (advance: 1000, left: 176, bottom: 0, right: 825, top: 719),
  (advance: 1000, left: 125, bottom: -34, right: 875, top: 767),
  (advance: 1000, left: 203, bottom: -34, right: 797, top: 753),
];
const _letterFace = _Face(ascent: 1025, descent: 275);
const _letterInk = <_Ink>[
  (advance: 600, left: 80, bottom: 0, right: 555, top: 698),
  (advance: 600, left: 67, bottom: 0, right: 533, top: 698),
  (advance: 600, left: 80, bottom: 0, right: 552, top: 698),
  (advance: 600, left: 80, bottom: 0, right: 567, top: 698),
  (advance: 600, left: 36, bottom: -183, right: 564, top: 710),
  (advance: 600, left: 73, bottom: 0, right: 596, top: 698),
];

/// How far [piece]'s glyph in [style] must move, in ems, for the centre of
/// its ink to land on the centre of its one-line, `height: 1` text box —
/// the box the board centres in the square. Each face's ascent is most of
/// its line, so without it the baseline sits low in the box and the ink
/// rides high (#163).
Offset pieceInkShift(Piece piece, PieceStyle style) {
  final flat = style == PieceStyle.flat;
  final face = flat ? _letterFace : _pieceFace;
  final ink = (flat ? _letterInk : _symbolInk)[piece.kind.index];
  final inkCentreX = (ink.left + ink.right) / 2000;
  final inkCentreY = face.baseline - (ink.bottom + ink.top) / 2000;
  return Offset(ink.advance / 2000 - inkCentreX, 0.5 - inkCentreY);
}

/// Layers drawn on [square] under its coordinates and piece; [side] is the
/// square's size and [scale] the board's scale from the design. Each layer
/// needs a key of its own among the square's layers.
typedef SquareDecorator = List<Widget> Function(
  Square square,
  double side,
  double scale,
);

/// Wraps the square-sized widget holding [square]'s [piece].
typedef PieceWrapper = Widget Function(
  Square square,
  Piece piece,
  Widget child,
  double side,
);

/// Wraps everything drawn on [square] above the board's colours.
typedef SquareWrapper = Widget Function(Square square, Widget child);

/// A layer over the whole board, above every square's layers and inside
/// the board's clip; [cell] is where a square is drawn, [side] a square's
/// size and [scale] the board's scale from the design.
typedef BoardLayer = Widget Function(
  Rect Function(Square square) cell,
  double side,
  double scale,
);

/// What a screen reader gets for one square in place of [squareLabel]: the
/// [label] it reads, the [onTap] a double-tap runs and, when there is one,
/// the [onTapHint] naming what it does ("select", "move here").
@immutable
class SquareSemantics {
  const SquareSemantics({
    required this.label,
    required this.onTap,
    this.onTapHint,
  });

  final String label;
  final VoidCallback onTap;
  final String? onTapHint;
}

/// [square]'s semantics, given its [piece].
typedef SquareDescriber = SquareSemantics Function(Square square, Piece? piece);

/// Tags each square's semantics node as the one tap target allowed under
/// 48 × 48 dp: eight squares must fit across the phone, so a square cannot
/// grow without the board shrinking (owner, #104's approval gate,
/// 2026-09-28). The accessibility tests exempt only nodes carrying it.
const SemanticsTag a11yExemptSquare = SemanticsTag('a11yExemptSquare');

/// What a screen reader says for [square]: its name and what stands on it.
String squareLabel(Square square, Piece? piece) => piece == null
    ? '${square.name}, empty'
    : '${square.name}, ${piece.colour.name} ${piece.kind.name}';

/// The chessboard as the design draws it: [position]'s pieces on squares in
/// [options]' theme, surface and piece style, with [bottom]'s side at the
/// bottom and coordinates on the left-hand file and the bottom rank.
///
/// Every square is a child keyed `sq-<name>`, the layer above it that takes
/// taps `cell-<name>`, and every piece `piece-<name>` (e.g. `sq-e4`), so the
/// play screen and its tests can find them.
///
/// The board knows nothing of a game. The play screen's highlights and
/// gestures come in through hooks, each called per square: [decorate] adds
/// layers under the coordinates and the piece, [decorateAbove] layers over
/// the piece, each filling the square and taking no touches, [wrapPiece] wraps the square's piece
/// and [wrapSquare] the whole square; [above] is one layer over all of
/// them, which takes no touches.
///
/// Each square is one semantics node, read in the order the squares are
/// seen — rank by rank from the top, left to right, whichever way the board
/// faces. [describe] replaces its plain [squareLabel] with a label, a tap
/// action and its hint, and then everything inside the square is left out
/// of the semantics tree, so the node is the square's only one.
class BoardView extends StatelessWidget {
  const BoardView({
    super.key,
    required this.position,
    required this.bottom,
    this.options = const BoardOptions(),
    this.decorate,
    this.decorateAbove,
    this.wrapPiece,
    this.wrapSquare,
    this.above,
    this.describe,
  });

  final Position position;
  final Colour bottom;
  final BoardOptions options;
  final SquareDecorator? decorate;
  final SquareDecorator? decorateAbove;
  final PieceWrapper? wrapPiece;
  final SquareWrapper? wrapSquare;
  final BoardLayer? above;
  final SquareDescriber? describe;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = squareSide(constraints.biggest);
        final scale = constraints.maxWidth / designWidth;
        final board = side * 8;
        return Center(
          child: SizedBox.square(
            key: const Key('board'),
            dimension: board,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                borderRadius: BorderRadius.all(Radius.circular(boardRadius)),
                boxShadow: [
                  BoxShadow(
                    color: Palette.boardShadow,
                    offset: Offset(0, 12),
                    blurRadius: 30,
                  ),
                ],
              ),
              position: DecorationPosition.background,
              child: ClipRRect(
                borderRadius: const BorderRadius.all(
                  Radius.circular(boardRadius),
                ),
                child: _board(side, scale),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _board(double side, double scale) {
    final squares = <Widget>[];
    final overlays = <Widget>[];
    for (final square in Square.values) {
      final (column, row) = _viewCell(square);
      final isLight = square.isLight;
      final piece = position.pieceAt(square);
      final rect = Rect.fromLTWH(column * side, row * side, side, side);
      squares.add(
        Positioned.fromRect(
          key: Key('sq-${square.name}'),
          rect: rect,
          child: ColoredBox(
            color: isLight ? options.theme.light : options.theme.dark,
          ),
        ),
      );
      Widget? pieceLayer;
      if (piece != null) {
        pieceLayer = Center(child: _piece(square, piece, side, scale));
        final wrap = wrapPiece;
        if (wrap != null) pieceLayer = wrap(square, piece, pieceLayer, side);
      }
      // Every layer is keyed, so layers coming and going around the piece
      // never make it a new widget: a drag in progress lives in there.
      Widget cell = Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          ...?decorate?.call(square, side, scale),
          if (column == 0)
            Positioned(
              key: const ValueKey(#rankLabel),
              left: 2 * scale,
              top: 1 * scale,
              child: _coordinate(
                'rank-${square.name}',
                '${square.rank + 1}',
                isLight,
                scale,
              ),
            ),
          if (row == 7)
            Positioned(
              key: const ValueKey(#fileLabel),
              right: 2 * scale,
              bottom: 1 * scale,
              child: _coordinate(
                'file-${square.name}',
                square.name[0],
                isLight,
                scale,
              ),
            ),
          if (pieceLayer != null)
            Positioned.fill(key: const ValueKey(#piece), child: pieceLayer),
          // Over the piece, so a layer here would otherwise take the touch
          // that starts the piece's drag.
          for (final layer
              in decorateAbove?.call(square, side, scale) ?? const <Widget>[])
            Positioned.fill(
              key: ValueKey((#above, layer.key)),
              child: IgnorePointer(child: layer),
            ),
        ],
      );
      cell = wrapSquare?.call(square, cell) ?? cell;
      final described = describe?.call(square, piece);
      cell = Semantics(
        container: true,
        sortKey: OrdinalSortKey((row * 8 + column).toDouble()),
        label: described?.label ?? squareLabel(square, piece),
        onTap: described?.onTap,
        onTapHint: described?.onTapHint,
        child: described == null ? cell : ExcludeSemantics(child: cell),
      );
      overlays.add(
        Positioned.fromRect(
          key: Key('cell-${square.name}'),
          rect: rect,
          child: cell,
        ),
      );
    }
    final pattern = options.surface.pattern;
    final layer = above;
    return Stack(
      children: [
        ...squares,
        if (pattern != null)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                key: const Key('surface'),
                painter: SurfacePainter(pattern, scale),
              ),
            ),
          ),
        ...overlays,
        if (layer != null)
          Positioned.fill(
            child: IgnorePointer(
              child: layer(
                (square) {
                  final (column, row) = _viewCell(square);
                  return Rect.fromLTWH(column * side, row * side, side, side);
                },
                side,
                scale,
              ),
            ),
          ),
        // The design's ring sits on the board's edge; drawn over the
        // squares it stays visible inside the clip.
        const Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              key: Key('board-ring'),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.all(Radius.circular(boardRadius)),
                border: Border.fromBorderSide(
                  BorderSide(color: Palette.boardRing),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// The column (0 = left) and row (0 = top) [square] is drawn in.
  (int, int) _viewCell(Square square) => bottom == Colour.white
      ? (square.file, 7 - square.rank)
      : (7 - square.file, square.rank);

  Widget _coordinate(String key, String text, bool onLight, double scale) {
    // The square's own label already names it.
    return ExcludeSemantics(
      child: Text(
        text,
        key: Key(key),
        textScaler: TextScaler.noScaling,
        style: TextStyle(
          fontFamily: Fonts.plexMono,
          fontWeight: FontWeight.w600,
          fontSize: 8 * scale,
          height: 1,
          color: onLight
              ? options.theme.labelOnLight
              : options.theme.labelOnDark,
        ),
      ),
    );
  }

  Widget _piece(Square square, Piece piece, double side, double scale) =>
      boardPiece(
        piece,
        options.pieceStyle,
        side,
        scale,
        textKey: Key('piece-${square.name}'),
      );
}

/// [piece] as the board draws it on a square of [side] in [style].
PieceGlyph boardPiece(
  Piece piece,
  PieceStyle style,
  double side,
  double scale, {
  Key? textKey,
}) {
  final flat = style == PieceStyle.flat;
  return PieceGlyph(
    piece: piece,
    style: style,
    fontSize: (side * (flat ? 0.62 : 0.92)).roundToDouble(),
    scale: scale,
    textKey: textKey,
  );
}

/// One piece as the board draws it: [piece]'s glyph in [style] at
/// [fontSize], in its side's colour with the design's outline or halo,
/// whose widths scale by [scale]. [textKey] keys the glyph's [Text].
/// [colour] and [shadows] replace the side's ink and outline, for a sample
/// drawn off the board (Settings' piece styles).
class PieceGlyph extends StatelessWidget {
  const PieceGlyph({
    super.key,
    required this.piece,
    required this.style,
    required this.fontSize,
    this.scale = 1,
    this.textKey,
    this.colour,
    this.shadows,
  });

  final Piece piece;
  final PieceStyle style;
  final double fontSize;
  final double scale;
  final Key? textKey;
  final Color? colour;
  final List<Shadow>? shadows;

  @override
  Widget build(BuildContext context) {
    final flat = style == PieceStyle.flat;
    final white = piece.colour == Colour.white;
    return ExcludeSemantics(
      child: Transform.translate(
        offset: pieceInkShift(piece, style) * fontSize,
        child: Text(
          pieceGlyph(piece, style),
          key: textKey,
          textScaler: TextScaler.noScaling,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: flat ? Fonts.plexMono : Fonts.pieces,
            fontWeight: flat ? FontWeight.w600 : FontWeight.w400,
            fontSize: fontSize,
            height: 1,
            color: colour ?? (white ? Palette.pieceWhite : Palette.pieceBlack),
            shadows:
                shadows ??
                (white ? _whiteShadows(scale) : _blackShadows(scale)),
          ),
        ),
      ),
    );
  }
}

/// The design's outline for white pieces: a dark hairline all round and a
/// soft drop shadow, CSS blur px taken as `blurRadius`.
List<Shadow> _whiteShadows(double s) => [
  Shadow(color: Palette.pieceBlack, blurRadius: 1 * s),
  Shadow(color: const Color(0xE612181F), blurRadius: 2 * s),
  for (final (dx, dy) in const [(1, 1), (-1, 1), (1, -1), (-1, -1)])
    Shadow(color: Palette.pieceBlack, offset: Offset(dx * s, dy * s)),
  Shadow(
    color: const Color(0x66000000),
    offset: Offset(0, 2 * s),
    blurRadius: 4 * s,
  ),
];

/// The design's faint light halo for black pieces.
List<Shadow> _blackShadows(double s) => [
  Shadow(color: const Color(0x80FFFFFF), blurRadius: 1 * s),
  Shadow(
    color: const Color(0x47FFFFFF),
    offset: Offset(0, 1 * s),
    blurRadius: 1 * s,
  ),
];

/// Draws a surface's stripes once across the whole board, their widths
/// scaled by [scale].
class SurfacePainter extends CustomPainter {
  SurfacePainter(this.pattern, this.scale);

  final StripePattern pattern;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    final period = pattern.period * scale;
    if (period <= 0) return;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate(size.width / 2, size.height / 2);
    // CSS measures a gradient's angle clockwise from "up"; after this turn
    // the gradient line runs along +x and every stripe is vertical.
    canvas.rotate((pattern.angleDegrees - 90) * math.pi / 180);
    final reach = size.longestSide;
    final paint = Paint();
    for (var x = -(reach / period).ceil() * period; x < reach; x += period) {
      var at = x;
      for (final band in pattern.bands) {
        final width = band.width * scale;
        paint.color = band.colour;
        canvas.drawRect(Rect.fromLTWH(at, -reach, width, 2 * reach), paint);
        at += width;
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(SurfacePainter oldDelegate) =>
      oldDelegate.pattern != pattern || oldDelegate.scale != scale;
}
