import 'package:honest_chess/engine/engine.dart';

/// How a refused move was tried.
enum RefusalVia { tap, drop }

/// A move the board refused (#97): with a piece selected, a tap on a square
/// that is neither one of its targets nor one of the mover's own pieces, or
/// a dragged piece let go where it cannot go. Not a `GameEvent`: nothing in
/// the game changed. The feedback hub ticks for it; the spoken refusal
/// (#102) names [kind].
class Refusal {
  const Refusal({
    required this.kind,
    required this.from,
    required this.to,
    required this.via,
  });

  /// The piece that could not go.
  final PieceKind kind;

  /// Where it stands.
  final Square from;

  /// The square tapped or dropped on; null for a drop off the board.
  final Square? to;

  final RefusalVia via;

  @override
  bool operator ==(Object other) =>
      other is Refusal &&
      other.kind == kind &&
      other.from == from &&
      other.to == to &&
      other.via == via;

  @override
  int get hashCode => Object.hash(kind, from, to, via);

  @override
  String toString() =>
      'Refusal(${kind.name} ${from.name}→${to?.name ?? 'off'} ${via.name})';
}
