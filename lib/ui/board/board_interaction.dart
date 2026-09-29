import 'package:flutter/widgets.dart';

import 'package:honest_chess/engine/engine.dart';
import 'package:honest_chess/ui/board/board_view.dart';
import 'package:honest_chess/ui/game/game_controller.dart';
import 'package:honest_chess/ui/theme/palette.dart';

/// How far above the finger a dragged piece floats, so the finger does not
/// hide it.
const double dragLift = 24;

/// How much bigger a dragged piece is drawn than on its square.
const double dragScale = 1.3;

/// How long a piece dropped where it cannot go takes to fly back.
const Duration springBackDuration = Duration(milliseconds: 150);

/// The playable board: #71's [BoardView] showing [controller]'s position
/// with its highlights, taking taps and drags as the player's moves.
///
/// Tap a piece to pick it up and a target to move it; or drag it and drop
/// it on a target. A drop anywhere else — on the board or off it — flies
/// the piece back to its square and moves nothing.
class BoardInteraction extends StatefulWidget {
  const BoardInteraction({
    super.key,
    required this.controller,
    required this.bottom,
  });

  final GameController controller;

  /// The side drawn at the bottom.
  final Colour bottom;

  @override
  State<BoardInteraction> createState() => _BoardInteractionState();
}

class _BoardInteractionState extends State<BoardInteraction>
    with SingleTickerProviderStateMixin {
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

  GameController get _controller => widget.controller;

  @override
  void dispose() {
    _springEntry?.remove();
    _spring.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final state = _controller.state;
        return BoardView(
          position: state.position,
          bottom: widget.bottom,
          options: _controller.options,
          decorate: (square, side, scale) =>
              _highlights(state, square, side, scale),
          wrapPiece: _draggable,
          wrapSquare: _target,
        );
      },
    );
  }

  /// The design's three highlight layers: the tint, the selected square's
  /// or a capture's inset ring, and a quiet move's dot.
  List<Widget> _highlights(
    GameViewState state,
    Square square,
    double side,
    double scale,
  ) {
    final name = square.name;
    final tint = state.tintAt(square);
    final mark = state.markAt(square);
    final dot = (side * 0.3).roundToDouble();
    return [
      if (tint != SquareTint.none)
        Positioned.fill(
          key: const ValueKey(#tint),
          child: ColoredBox(key: Key('tint-$name'), color: _tintColour(tint)),
        ),
      if (tint == SquareTint.selected)
        Positioned.fill(
          key: const ValueKey(#selectedRing),
          child: _ring('selected-$name', Palette.selectedRing, 2 * scale),
        ),
      if (mark == SquareMark.ring)
        Positioned.fill(
          key: const ValueKey(#captureRing),
          child: _ring('ring-$name', Palette.captureRing, 3 * scale),
        ),
      if (mark == SquareMark.dot)
        Center(
          key: const ValueKey(#dot),
          child: SizedBox.square(
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
    ];
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
          setState(() => _dragging = square);
          _controller.pickUp(square);
        },
        onDragEnd: (_) {
          if (mounted) setState(() => _dragging = null);
        },
        onDraggableCanceled: (velocity, offset) {
          _controller.drop(square, null);
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
    if (!cellContext.mounted) return;
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
