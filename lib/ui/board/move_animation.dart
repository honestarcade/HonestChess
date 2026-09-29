import 'dart:async';

import 'package:flutter/widgets.dart';

import 'package:honest_chess/data/game_event.dart';
import 'package:honest_chess/engine/engine.dart';
import 'package:honest_chess/ui/board/board_options.dart';
import 'package:honest_chess/ui/board/board_view.dart';
import 'package:honest_chess/ui/game/game_controller.dart';
import 'package:honest_chess/ui/game/result_text.dart' show endedByMove;
import 'package:honest_chess/ui/motion.dart';

/// How long a move's slide takes (owner, round one: about 180 ms).
const Duration moveSlideDuration = Duration(milliseconds: 180);

/// The slide's easing.
const Curve moveSlideCurve = Curves.easeOutCubic;

/// One piece sliding from [from] to [to].
typedef PieceSlide = ({Piece piece, Square from, Square to});

/// One piece fading out where it stood.
typedef PieceFade = ({Piece piece, Square square});

/// What one move shows while it slides: the pieces sliding, and the pieces
/// fading where they were taken. The board underneath already shows the
/// position after the move, its sliding pieces' targets hidden.
@immutable
final class MoveMotion {
  const MoveMotion({required this.slides, required this.fades});

  final List<PieceSlide> slides;
  final List<PieceFade> fades;

  /// The squares whose piece, in the position after the move, waits for
  /// the slide to end before it shows.
  Set<Square> get hidden => {for (final s in slides) s.to};

  bool get isEmpty => slides.isEmpty && fades.isEmpty;
}

/// The motion of [move] played from [before]. The moving piece slides and a
/// captured piece — en passant's passed pawn included — fades; castling
/// slides the rook beside the king; a promotion slides the pawn, whose
/// square then shows the new piece. A [dropped] move is already on its
/// square: nothing slides but a castling rook, and a capture vanishes.
MoveMotion moveMotion(Position before, Move move, {bool dropped = false}) {
  final mover = before.pieceAt(move.from);
  final slides = <PieceSlide>[];
  final fades = <PieceFade>[];
  if (mover != null && !dropped) {
    slides.add((piece: mover, from: move.from, to: move.to));
  }
  if (move.isCastling) {
    final kingside = move.to.file > move.from.file;
    final rank = move.from.rank;
    final rookFrom = Square.at(kingside ? 7 : 0, rank);
    final rookTo = Square.at(kingside ? 5 : 3, rank);
    final rook = before.pieceAt(rookFrom);
    if (rook != null) slides.add((piece: rook, from: rookFrom, to: rookTo));
  }
  if (move.isCapture && !dropped) {
    final taken = move.isEnPassant
        ? Square.at(move.to.file, move.from.rank)
        : move.to;
    final piece = before.pieceAt(taken);
    if (piece != null) fades.add((piece: piece, square: taken));
  }
  return MoveMotion(slides: slides, fades: fades);
}

/// The board's one slide: it follows [controller]'s events and runs each
/// played move's [MoveMotion] over [moveSlideDuration]. Only a move slides;
/// every other change — a takeback, a new game, a restore — shows at once
/// and ends a slide still running, as a pause does, as the app leaving the
/// foreground does, and as [motion] turning off does. A move while one
/// slides ends that one and starts its own.
class MoveAnimation extends ChangeNotifier {
  MoveAnimation({required TickerProvider vsync, required this.controller})
    : _run = AnimationController(vsync: vsync, duration: moveSlideDuration) {
    _progress = CurvedAnimation(parent: _run, curve: moveSlideCurve);
    _run.addStatusListener((status) {
      if (status == AnimationStatus.completed) _finish();
    });
    _events = controller.events.listen(_on);
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) {
        if (state != AppLifecycleState.resumed) jumpToEnd();
      },
    );
  }

  final GameController controller;
  final AnimationController _run;
  late final Animation<double> _progress;
  late final StreamSubscription<GameEvent> _events;
  late final AppLifecycleListener _lifecycle;
  Motion _motion = Motion.full;
  MoveMotion? _current;
  bool _disposed = false;

  /// The slide's eased progress, 0 to 1.
  Animation<double> get progress => _progress;

  /// The motion running, or null.
  MoveMotion? get current => _current;

  bool get sliding => _current != null;

  /// Whether pieces move; off ends a running slide, and no slide starts.
  Motion get motion => _motion;
  set motion(Motion value) {
    if (value == _motion) return;
    _motion = value;
    // Read from a widget's dependencies, mid-build: the listeners hear of
    // it once the frame is done.
    if (value.isOff && _end()) scheduleMicrotask(_notify);
  }

  void _on(GameEvent event) {
    switch (event) {
      case GameMoved(:final game):
        _end();
        if (_motion.isOff || game.history.length < 2) {
          _notify();
          return;
        }
        final motion = moveMotion(
          game.history[game.history.length - 2].position,
          game.history.last.move!,
          dropped: controller.lastMoveWasDrop,
        );
        if (motion.isEmpty) {
          _notify();
          return;
        }
        _current = motion;
        _run.forward(from: 0);
        _notify();
      // A move that ended the game is still sliding.
      case GameEnded(:final game) when endedByMove(game):
        return;
      default:
        jumpToEnd();
    }
  }

  /// Ends a running slide at once: every piece on its square.
  void jumpToEnd() {
    if (_end()) _notify();
  }

  bool _end() {
    if (_current == null) return false;
    _current = null;
    _run.stop();
    _run.value = 0;
    return true;
  }

  void _finish() {
    if (_current == null) return;
    _current = null;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_events.cancel());
    _lifecycle.dispose();
    _run.dispose();
    super.dispose();
  }
}

/// The slide layer: [animation]'s fading and sliding pieces, drawn in
/// [style] over the board's squares at [cell].
class MoveSlideLayer extends StatelessWidget {
  const MoveSlideLayer({
    super.key,
    required this.animation,
    required this.style,
    required this.cell,
    required this.side,
    required this.scale,
  });

  final MoveAnimation animation;
  final PieceStyle style;
  final Rect Function(Square square) cell;
  final double side;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([animation, animation.progress]),
      builder: (context, _) {
        final motion = animation.current;
        if (motion == null) return const SizedBox.shrink();
        final t = animation.progress.value;
        return Stack(
          children: [
            for (final fade in motion.fades)
              Positioned.fromRect(
                key: Key('fade-${fade.square.name}'),
                rect: cell(fade.square),
                child: Opacity(
                  opacity: 1 - t,
                  child: Center(
                    child: boardPiece(fade.piece, style, side, scale),
                  ),
                ),
              ),
            for (final slide in motion.slides)
              Positioned.fromRect(
                key: Key('slide-${slide.to.name}'),
                rect: Rect.lerp(cell(slide.from), cell(slide.to), t)!,
                child: Center(
                  child: boardPiece(slide.piece, style, side, scale),
                ),
              ),
          ],
        );
      },
    );
  }
}
