import 'dart:math';

import 'package:flutter/foundation.dart';

import 'package:honest_chess/engine/engine.dart';

final _idPattern = RegExp(r'^[0-9a-f]{16}$');

/// Whether [id] has the form [newGameId] gives: 16 lowercase hex digits.
bool isGameId(Object? id) => id is String && _idPattern.hasMatch(id);

/// A new game's id: 64 random bits as 16 lowercase hex digits, drawn from
/// [random] (default `Random.secure()`) as two 32-bit halves.
String newGameId([Random? random]) {
  final source = random ?? Random.secure();
  String half() => source.nextInt(1 << 32).toRadixString(16).padLeft(8, '0');
  return '${half()}${half()}';
}

/// Whether [mover]'s move counts as having started [mode]'s game for the
/// statistics: against the computer a move of your colour, between two
/// players any move.
bool isQualifyingMove(GameMode mode, Colour mover) => switch (mode) {
  VsComputer(:final playerColour) => mover == playerColour,
  TwoPlayer() => true,
};

/// Whether [game]'s history holds a qualifying move ([isQualifyingMove]).
bool hasQualifyingMove(Game game) {
  final history = game.history;
  for (var i = 1; i < history.length; i++) {
    if (isQualifyingMove(game.mode, history[i - 1].position.sideToMove)) {
      return true;
    }
  }
  return false;
}

/// What the statistics know about one game, carried with it in the saved
/// game's `recorded` block: its [id], whether you have [started] it (made a
/// move; it survives takebacks), and whether its result is already counted
/// ([outcome]).
@immutable
final class RecordedState {
  const RecordedState({
    required this.id,
    this.started = false,
    this.outcome = false,
  });

  /// A new game's state: a fresh id, nothing started or counted.
  factory RecordedState.fresh([String Function() newId = newGameId]) =>
      RecordedState(id: newId());

  /// Reads a saved `recorded` block for [game] field by field: a
  /// well-formed `id` is kept, otherwise [newId] draws one; `started` is
  /// true when stored so or when the history holds a qualifying move;
  /// `outcome` is the stored bool, otherwise false.
  factory RecordedState.fromJson(
    Object? json,
    Game game, {
    String Function() newId = newGameId,
  }) {
    final map = json is Map ? json : const <String, Object?>{};
    final id = map['id'];
    final outcome = map['outcome'];
    return RecordedState(
      id: isGameId(id) ? id as String : newId(),
      started: map['started'] == true || hasQualifyingMove(game),
      outcome: outcome is bool && outcome,
    );
  }

  final String id;
  final bool started;
  final bool outcome;

  RecordedState copyWith({bool? started, bool? outcome}) => RecordedState(
    id: id,
    started: started ?? this.started,
    outcome: outcome ?? this.outcome,
  );

  Map<String, Object?> toJson() =>
      Map.unmodifiable({'id': id, 'started': started, 'outcome': outcome});

  @override
  bool operator ==(Object other) =>
      other is RecordedState &&
      other.id == id &&
      other.started == started &&
      other.outcome == outcome;

  @override
  int get hashCode => Object.hash(id, started, outcome);

  @override
  String toString() =>
      'RecordedState($id, started: $started, outcome: $outcome)';
}
