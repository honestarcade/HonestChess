// The computer near the end of its clock, in a sharp position where the
// search's first iterations cost more than the clock cap's margin: it must
// still answer before its clock reaches zero (#132). Real time is charged,
// as the game screen charges it.

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
  for (final (step, leftMs) in [
    (Strength.club, 150),
    (Strength.club, 60),
    (Strength.master, 150),
  ]) {
    test(
      '${step.name} with $leftMs ms left answers before its flag falls',
      () async {
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
        expect(game.remaining(Colour.black), leftMs);

        final thinking = Stopwatch()..start();
        final moved = await player.chooseMove(game) as Moved;
        time.ms += thinking.elapsedMilliseconds;
        final after = game.play(moved.move, byComputer: true);
        expect(
          after.remaining(Colour.black),
          greaterThan(0),
          reason:
              'the computer flagged: it thought '
              '${thinking.elapsedMilliseconds} ms with $leftMs ms left '
              '(${after.status})',
        );
      },
    );
  }
}
