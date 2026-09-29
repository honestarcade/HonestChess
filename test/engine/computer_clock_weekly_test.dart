@Tags(['weekly'])
library;

// The computer never loses on time: whole games of the computer against
// itself, through the worker isolate, with each move's real thinking time
// charged to the mover's clock. Too slow for the pull-request gate.

import 'package:flutter_test/flutter_test.dart';
import 'package:honest_chess/engine/engine.dart';

/// A monotonic time source the test winds by the time really spent.
class ChargedTime {
  int ms = 0;
  int call() => ms;
}

/// Plays [step] against itself under [control] until [moves] full moves or
/// the game ends, charging each move's real time to the mover, and returns
/// how many searches the clock cut short of the step's node budget.
Future<int> _selfPlay(Strength step, Timed control, {int moves = 80}) async {
  final time = ChargedTime();
  final players = [
    for (final seed in [1, 2]) ComputerPlayer(step, seed, now: time.call),
  ];
  addTearDown(() => Future.wait([for (final p in players) p.dispose()]));
  for (final player in players) {
    await player.start();
  }
  var game = Game.start(const TwoPlayer(), control, time: time.call);
  var capped = 0;
  var plies = 0;
  while (!game.isOver && game.position.fullmoveNumber <= moves) {
    final mover = game.sideToMove;
    final elapsed = Stopwatch()..start();
    final answer = await players[mover.index].chooseMove(game);
    time.ms += elapsed.elapsedMilliseconds;
    expect(answer, isA<Moved>());
    final moved = answer as Moved;
    if (moved.nodes < step.settings.nodeBudget &&
        moved.depth < (step.settings.depthCap ?? 64)) {
      capped++;
    }
    game = game.play(moved.move);
    plies++;
    final ended = switch (game.status) {
      Win(:final reason) || Draw(:final reason) => reason,
      _ => null,
    };
    expect(
      ended,
      isNot(anyOf(GameEndReason.flag, GameEndReason.flagNoMatingMaterial)),
      reason: '${mover.name} flagged at move ${game.position.fullmoveNumber}',
    );
    expect(
      game.history.last.clock.whiteMs > 0 &&
          game.history.last.clock.blackMs > 0,
      isTrue,
      reason: 'a clock reached zero: ${game.history.last.clock}',
    );
  }
  // Printed so the weekly log shows how far each game got.
  // ignore: avoid_print
  print('$step $control: $plies plies, ${game.status}, $capped capped');
  return capped;
}

void main() {
  test('Club against itself at 5+0 never flags in 80 moves', () async {
    await _selfPlay(Strength.club, Timed.blitz);
  }, timeout: const Timeout(Duration(minutes: 10)));

  test('Master against itself at 1+0 never flags, though its clock cuts its '
      'searches', () async {
    final capped = await _selfPlay(Strength.master, Timed(1, 0));
    expect(
      capped,
      greaterThan(0),
      reason: 'the clock never shortened a search',
    );
  }, timeout: const Timeout(Duration(minutes: 10)));
}
