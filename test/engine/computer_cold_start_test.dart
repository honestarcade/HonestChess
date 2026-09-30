// The computer's first move in a fresh process with less time left than its
// clock margin (#155): nothing has run yet, so every step of the request is
// at its slowest, and it must still answer before its flag falls. This file
// holds this one test so that its first request is the process's first.

import 'package:flutter_test/flutter_test.dart';
import 'package:honest_chess/engine/engine.dart';

/// Kiwipete: many captures and checks, so even two plies are expensive.
const _kiwipete =
    'r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1';

class _Time {
  int ms = 0;
  int call() => ms;
}

void main() {
  test('a cold first move inside the clock margin answers in time', () async {
    const leftMs = 30;
    // Beginner first: its request is the one nothing before it has warmed.
    for (final step in [Strength.beginner, ...Strength.values.skip(1)]) {
      final time = _Time();
      final player = ComputerPlayer(step, 7, now: time.call);
      addTearDown(player.dispose);
      await player.start();
      var game = Game.start(
        VsComputer(playerColour: Colour.white, step: step, seed: 7),
        Timed.blitz,
        time: time.call,
        fen: _kiwipete,
      );
      game = game.play(Move.fromUci(game.position, 'e1g1'));
      time.ms = Timed.blitz.initialMs - leftMs;

      final thinking = Stopwatch()..start();
      final moved = await player.chooseMove(game) as Moved;
      time.ms += thinking.elapsedMilliseconds;
      final after = game.play(moved.move, byComputer: true);
      expect(
        after.remaining(Colour.black),
        greaterThan(0),
        reason:
            'the computer flagged: ${step.name} thought '
            '${thinking.elapsedMilliseconds} ms with $leftMs ms left '
            '(${after.status})',
      );
    }
  });
}
