// Generates test/fixtures/game_v1.json: one saved game in the version-1
// format, frozen once written. test/engine/game_json_test.dart requires the
// committed file to keep loading and to re-serialise byte for byte, so a
// later format change cannot silently break old saves. Re-running this after
// a format change is exactly the mistake the fixture exists to catch: a new
// version gets its own fixture instead.
//
// The game covers castling on both sides, en passant, a promotion, a
// takeback, a timed clock with increment and a seed with the top bit set.
//
// Usage: dart run tools/gen_game_v1.dart

import 'dart:convert';
import 'dart:io';

import 'package:honest_chess/engine/engine.dart';

const String outputPath = 'test/fixtures/game_v1.json';

/// Above 2^63, so the seed is stored as an unsigned decimal string.
const int seed = 0xfedcba9876543210;

/// The moves, the player (White) and the computer alternating, each with the
/// milliseconds its mover thinks. `takeback` undoes the player's last move
/// and the computer's reply.
const List<(String, int)> script = [
  ('e2e4', 4200),
  ('a7a6', 900),
  ('e4e5', 3100),
  ('d7d5', 1100),
  ('e5d6', 5300), // en passant
  ('g8f6', 800),
  ('d2d4', 2000),
  ('b8c6', 700),
  ('takeback', 1500),
  ('d6c7', 2600),
  ('e7e6', 1000),
  ('c7b8q', 4400), // promotion, capturing
  ('a8b8', 1200),
  ('g1f3', 6100),
  ('f8e7', 900),
  ('f1e2', 3300),
  ('e8g8', 1000), // castling, Black
  ('e1g1', 2700), // castling, White
];

/// The game the script plays, saved 2500 ms into Black's think.
Map<String, Object?> fixtureJson() {
  var now = 0;
  var game = Game.start(
    const VsComputer(
      playerColour: Colour.white,
      step: Strength.club,
      seed: seed,
    ),
    Timed.rapid,
    time: () => now,
  );
  for (final (uci, think) in script) {
    now += think;
    if (uci == 'takeback') {
      game = game.takeBack();
      continue;
    }
    game = game.play(
      Move.fromUci(game.position, uci),
      byComputer: game.sideToMove == Colour.black,
    );
  }
  now += 2500;
  return game.toJson();
}

/// [json] as the fixture's bytes: two-space indent, trailing newline.
String encodeFixture(Map<String, Object?> json) =>
    '${const JsonEncoder.withIndent('  ').convert(json)}\n';

void main() {
  File(outputPath).writeAsStringSync(encodeFixture(fixtureJson()));
  stdout.writeln('wrote $outputPath');
}
