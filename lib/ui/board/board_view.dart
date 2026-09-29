import 'dart:math' as math;

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

/// The chessboard as the design draws it: [position]'s pieces on squares in
/// [options]' theme, surface and piece style, with [bottom]'s side at the
/// bottom and coordinates on the left-hand file and the bottom rank.
///
/// Every square is a child keyed `sq-<name>` and every piece `piece-<name>`
/// (e.g. `sq-e4`), so the play screen and its tests can find them.
class BoardView extends StatelessWidget {
  const BoardView({
    super.key,
    required this.position,
    required this.bottom,
    this.options = const BoardOptions(),
  });

  final Position position;
  final Colour bottom;
  final BoardOptions options;

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
      overlays.add(
        Positioned.fromRect(
          rect: rect,
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              if (column == 0)
                Positioned(
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
                  right: 2 * scale,
                  bottom: 1 * scale,
                  child: _coordinate(
                    'file-${square.name}',
                    square.name[0],
                    isLight,
                    scale,
                  ),
                ),
              if (piece != null)
                Positioned.fill(
                  child: Center(child: _piece(square, piece, side, scale)),
                ),
            ],
          ),
        ),
      );
    }
    final pattern = options.surface.pattern;
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
    return Text(
      text,
      key: Key(key),
      textScaler: TextScaler.noScaling,
      style: TextStyle(
        fontFamily: Fonts.plexMono,
        fontWeight: FontWeight.w600,
        fontSize: 8 * scale,
        height: 1,
        color: onLight ? Palette.coordOnLight : Palette.coordOnDark,
      ),
    );
  }

  Widget _piece(Square square, Piece piece, double side, double scale) {
    final flat = options.pieceStyle == PieceStyle.flat;
    final white = piece.colour == Colour.white;
    return ExcludeSemantics(
      child: Text(
        pieceGlyph(piece, options.pieceStyle),
        key: Key('piece-${square.name}'),
        textScaler: TextScaler.noScaling,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: flat ? Fonts.plexMono : Fonts.pieces,
          // Empty, so a missing glyph shows as missing rather than as a
          // system font's piece — on Android that would be colour emoji.
          fontFamilyFallback: const [],
          fontWeight: flat ? FontWeight.w600 : FontWeight.w400,
          fontSize: (side * (flat ? 0.62 : 0.92)).roundToDouble(),
          height: 1,
          color: white ? Palette.pieceWhite : Palette.pieceBlack,
          shadows: white ? _whiteShadows(scale) : _blackShadows(scale),
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
