import 'package:flutter/widgets.dart';

import 'package:honest_chess/a11y/announcer.dart';
import 'package:honest_chess/engine/engine.dart';
import 'package:honest_chess/ui/board/board_semantics.dart';
import 'package:honest_chess/ui/board/board_view.dart';
import 'package:honest_chess/ui/board/move_animation.dart';
import 'package:honest_chess/ui/game/game_controller.dart';
import 'package:honest_chess/ui/motion.dart';
import 'package:honest_chess/ui/theme/palette.dart';

/// How far above the finger a dragged piece floats, so the finger does not
/// hide it.
const double dragLift = 24;

/// How much bigger a dragged piece is drawn than on its square.
const double dragScale = 1.3;

/// How long a piece dropped where it cannot go takes to fly back.
const Duration springBackDuration = Duration(milliseconds: 150);

/// The ring widths at the design's width: the selected square's is the
/// thicker, so it never looks like a capture target's without colour.
const double selectedRingWidth = 4;
const double captureRingWidth = 3;

/// The last move's corner mark: a right triangle this long in each leg,
/// at the design's width.
const double lastMoveMarkSize = 8;

/// A king in check's badge, as fractions of a square: the circle's
/// diameter and the "!"'s size.
const double checkBadgeDiameter = 0.34;
const double checkBadgeGlyph = 0.22;

/// The shapes that tell each highlight apart without colour (#100).
enum BoardShape { selectedRing, lastMoveMark, moveDot, captureRing, checkBadge }

/// The shapes drawn on a square with [tint] and [mark], whose king is in
/// check when [inCheck]. The check's badge does not depend on the tint, so
/// it stays when the checked king is selected.
Set<BoardShape> shapesFor(
  SquareTint tint,
  SquareMark mark, {
  required bool inCheck,
}) => {
  if (tint == SquareTint.selected) BoardShape.selectedRing,
  if (tint == SquareTint.lastMove) BoardShape.lastMoveMark,
  if (mark == SquareMark.dot) BoardShape.moveDot,
  if (mark == SquareMark.ring) BoardShape.captureRing,
  if (inCheck) BoardShape.checkBadge,
};

/// The last move's corner mark: a right triangle whose legs lie along the
/// square's left and bottom edges.
class CornerMarkPainter extends CustomPainter {
  const CornerMarkPainter(this.colour);

  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(0, size.height)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = colour);
  }

  @override
  bool shouldRepaint(CornerMarkPainter oldDelegate) =>
      oldDelegate.colour != colour;
}

/// The playable board: #71's [BoardView] showing [controller]'s position
/// with its highlights, taking taps and drags as the player's moves.
///
/// Tap a piece to pick it up and a target to move it; or drag it and drop
/// it on a target. A drop anywhere else — on the board or off it — flies
/// the piece back to its square and moves nothing.
///
/// Each move slides by [slides] (#98); without one the board runs its own.
///
/// For a screen reader (#102) the board is one labelled node holding a node
/// per square, whose double-tap is the tap above and speaks what it did
/// through [announcer] (by default nobody).
class BoardInteraction extends StatefulWidget {
  const BoardInteraction({
    super.key,
    required this.controller,
    required this.bottom,
    this.slides,
    this.announcer = const NoAnnouncer(),
  });

  final Announcer announcer;

  final GameController controller;

  /// The slide shared with the play screen, which holds the board's
  /// orientation while it runs.
  final MoveAnimation? slides;

  /// The side drawn at the bottom.
  final Colour bottom;

  @override
  State<BoardInteraction> createState() => _BoardInteractionState();
}

class _BoardInteractionState extends State<BoardInteraction>
    with TickerProviderStateMixin {
  late final AnimationController _spring = AnimationController(
    vsync: this,
    duration: springBackDuration,
  );
  OverlayEntry? _springEntry;

  /// The square whose piece is flying back; it is hidden there meanwhile.
  Square? _springing;

  /// The square of the piece being dragged. While one drag is running no
  /// other piece can be dragged and taps are ignored: the first pointer
  /// drives the board.
  Square? _dragging;

  /// The square under the dragged piece, whether or not it would take it;
  /// null off the board. A refused drop is reported with it. Each pointer
  /// move clears it and the targets under the pointer set it again, because
  /// a target's leave also fires at the drop and cannot tell the two apart.
  Square? _hovered;

  /// The drag's pointer was cancelled rather than lifted: the drag ends
  /// with no drop, so nothing was refused.
  bool _pointerCancelled = false;

  /// The pointer that went down last while no drag ran, which is the one a
  /// drag starting next belongs to; and the running drag's pointer.
  int? _lastDown;
  int? _dragPointer;

  GameController get _controller => widget.controller;

  /// The board's own slide, when none is given.
  MoveAnimation? _ownSlides;

  MoveAnimation get _slides =>
      widget.slides ??
      (_ownSlides ??= MoveAnimation(vsync: this, controller: _controller));

  bool _still = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final motion = Motion.of(context);
    _still = motion.isOff;
    _slides.motion = motion;
  }

  @override
  void dispose() {
    _springEntry?.remove();
    _spring.dispose();
    _ownSlides?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slides = _slides;
    return ListenableBuilder(
      listenable: Listenable.merge([_controller, slides]),
      builder: (context, _) {
        final state = _controller.state;
        final hidden = slides.current?.hidden ?? const <Square>{};
        // The listener sees each pointer event before the drag's own
        // recogniser does.
        return Listener(
          onPointerDown: (event) {
            if (_dragging == null) _lastDown = event.pointer;
          },
          onPointerMove: (event) {
            if (event.pointer == _dragPointer) _hovered = null;
          },
          onPointerCancel: (event) {
            if (event.pointer == _dragPointer) _pointerCancelled = true;
          },
          child: Semantics(
            container: true,
            explicitChildNodes: true,
            label: boardLabel(_controller.game.mode, widget.bottom),
            child: BoardView(
              position: state.position,
              bottom: widget.bottom,
              options: _controller.options,
              decorate: (square, side, scale) =>
                  _highlights(state, square, side, scale),
              decorateAbove: (square, side, scale) =>
                  _overPiece(state, square, side, scale),
              wrapPiece: (square, piece, child, side) => _draggable(
                square,
                piece,
                hidden.contains(square)
                    ? Opacity(opacity: 0, child: child)
                    : child,
                side,
              ),
              wrapSquare: _target,
              above: (cell, side, scale) => MoveSlideLayer(
                animation: slides,
                style: _controller.options.pieceStyle,
                cell: cell,
                side: side,
                scale: scale,
              ),
              describe: describeSquares(_controller, widget.announcer),
            ),
          ),
        );
      },
    );
  }

  /// The layers under the coordinates and the piece, bottom to top: the
  /// tint, the last move's corner mark, a capture's ring or a quiet move's
  /// dot, and a king in check's badge.
  List<Widget> _highlights(
    GameViewState state,
    Square square,
    double side,
    double scale,
  ) {
    final name = square.name;
    final tint = state.tintAt(square);
    final shapes = _shapesAt(state, square);
    final dot = (side * 0.3).roundToDouble();
    return [
      if (tint != SquareTint.none)
        Positioned.fill(
          key: const ValueKey(#tint),
          child: ColoredBox(key: Key('tint-$name'), color: _tintColour(tint)),
        ),
      if (shapes.contains(BoardShape.lastMoveMark))
        Positioned(
          key: const ValueKey(#lastMoveMark),
          left: 0,
          bottom: 0,
          child: _shape(
            CustomPaint(
              key: Key('mark-last-$name'),
              size: Size.square(lastMoveMarkSize * scale),
              painter: CornerMarkPainter(
                square.isLight
                    ? Palette.lastMoveMarkOnLight
                    : Palette.lastMoveMarkOnDark,
              ),
            ),
          ),
        ),
      if (shapes.contains(BoardShape.captureRing))
        Positioned.fill(
          key: const ValueKey(#captureRing),
          child: _shape(
            _ring(
              'ring-capture-$name',
              Palette.captureRing,
              captureRingWidth * scale,
            ),
          ),
        ),
      if (shapes.contains(BoardShape.moveDot))
        Center(
          key: const ValueKey(#dot),
          child: _shape(
            SizedBox.square(
              key: Key('dot-$name'),
              dimension: dot,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  color: Palette.moveDot,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ),
      if (shapes.contains(BoardShape.checkBadge))
        Positioned(
          key: const ValueKey(#checkBadge),
          top: 0,
          right: 0,
          child: _shape(_checkBadge(name, side)),
        ),
    ];
  }

  /// The layer over the piece: the selected square's ring, so the piece
  /// never covers it.
  List<Widget> _overPiece(
    GameViewState state,
    Square square,
    double side,
    double scale,
  ) => [
    if (_shapesAt(state, square).contains(BoardShape.selectedRing))
      _shape(
        _ring(
          'ring-selected-${square.name}',
          Palette.selectedRing,
          selectedRingWidth * scale,
        ),
        key: const ValueKey(#selectedRing),
      ),
  ];

  static Set<BoardShape> _shapesAt(GameViewState state, Square square) =>
      shapesFor(
        state.tintAt(square),
        state.markAt(square),
        inCheck: state.inCheck == square,
      );

  /// A shape only draws what the square's own label already says.
  static Widget _shape(Widget child, {Key? key}) => ExcludeSemantics(
    key: key,
    child: IgnorePointer(child: child),
  );

  static Widget _checkBadge(String name, double side) {
    final diameter = side * checkBadgeDiameter;
    return SizedBox.square(
      key: Key('badge-check-$name'),
      dimension: diameter,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: Palette.danger,
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Text(
            '!',
            textScaler: TextScaler.noScaling,
            style: TextStyle(
              fontFamily: Fonts.outfit,
              fontWeight: FontWeight.w700,
              fontSize: side * checkBadgeGlyph,
              height: 1,
              color: Palette.checkBadgeInk,
            ),
          ),
        ),
      ),
    );
  }

  static Color _tintColour(SquareTint tint) => switch (tint) {
    SquareTint.selected => Palette.selectedTint,
    SquareTint.check => Palette.checkTint,
    SquareTint.lastMove => Palette.lastMoveTint,
    SquareTint.none => const Color(0x00000000),
  };

  /// A CSS inset box-shadow ring: a border drawn inside the square.
  static Widget _ring(String key, Color colour, double width) => DecoratedBox(
    key: Key(key),
    decoration: BoxDecoration(
      border: Border.fromBorderSide(BorderSide(color: colour, width: width)),
    ),
  );

  Widget _target(Square square, Widget child) {
    return DragTarget<int>(
      onWillAcceptWithDetails: (details) =>
          _controller.canDrop(Square.values[details.data], square),
      onAcceptWithDetails: (details) =>
          _controller.drop(Square.values[details.data], square),
      onMove: (_) => _hovered = square,
      builder: (context, candidates, rejected) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (_dragging == null) _controller.tapSquare(square);
        },
        child: child,
      ),
    );
  }

  Widget _draggable(Square square, Piece piece, Widget child, double side) {
    final hidden = _springing == square;
    final shown = hidden ? Opacity(opacity: 0, child: child) : child;
    final free = _dragging == null || _dragging == square;
    return Builder(
      builder: (cellContext) => Draggable<int>(
        // Square is an extension type, not an Object a drag can carry.
        data: square.index,
        maxSimultaneousDrags: free && _controller.canDrag(square) ? 1 : 0,
        dragAnchorStrategy: (draggable, context, position) =>
            Offset(side / 2, side / 2 + dragLift),
        feedback: IgnorePointer(
          child: SizedBox.square(
            key: const Key('drag-feedback'),
            dimension: side,
            child: Transform.scale(scale: dragScale, child: child),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.3, child: child),
        onDragStarted: () {
          _hovered = null;
          _pointerCancelled = false;
          _dragPointer = _lastDown;
          setState(() => _dragging = square);
          _controller.pickUp(square);
        },
        onDragEnd: (_) {
          _dragPointer = null;
          if (mounted) setState(() => _dragging = null);
        },
        onDraggableCanceled: (velocity, offset) {
          if (_pointerCancelled) {
            _controller.abandonDrag(square);
          } else {
            _controller.drop(square, _hovered);
          }
          _hovered = null;
          _pointerCancelled = false;
          if (mounted) _springBack(square, cellContext, offset, child, side);
        },
        child: shown,
      ),
    );
  }

  /// Flies [child] from where it was dropped, [from] (global), back to its
  /// square, drawn over everything in the overlay.
  void _springBack(
    Square square,
    BuildContext cellContext,
    Offset from,
    Widget child,
    double side,
  ) {
    // With motion off the piece is simply back on its square.
    if (!cellContext.mounted || _still) return;
    final overlay = Overlay.of(context);
    final overlayBox = overlay.context.findRenderObject() as RenderBox?;
    final cellBox = cellContext.findRenderObject() as RenderBox?;
    if (overlayBox == null || cellBox == null || !cellBox.attached) return;
    final tween = Tween(
      begin: overlayBox.globalToLocal(from),
      end: overlayBox.globalToLocal(cellBox.localToGlobal(Offset.zero)),
    ).chain(CurveTween(curve: Curves.easeOut));
    _springEntry?.remove();
    final entry = OverlayEntry(
      builder: (_) => AnimatedBuilder(
        animation: _spring,
        builder: (_, flying) {
          final at = tween.evaluate(_spring);
          return Positioned(left: at.dx, top: at.dy, child: flying!);
        },
        child: IgnorePointer(
          child: SizedBox.square(
            key: const Key('spring-back'),
            dimension: side,
            child: child,
          ),
        ),
      ),
    );
    _springEntry = entry;
    overlay.insert(entry);
    setState(() => _springing = square);
    _spring.forward(from: 0).whenComplete(() {
      if (_springEntry != entry) return;
      entry.remove();
      _springEntry = null;
      if (mounted) setState(() => _springing = null);
    });
  }
}
