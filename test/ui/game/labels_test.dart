// The words the play screen's frame (#74) shows: step and time-control
// names, the status chip's ending words, and the clock's text and spoken
// label at the rounding edges.
import 'package:flutter_test/flutter_test.dart';

import 'package:honest_chess/engine/engine.dart';
import 'package:honest_chess/ui/game/game_screen.dart';
import 'package:honest_chess/ui/game/labels.dart';
import 'package:honest_chess/ui/game/player_panel.dart';

void main() {
  test('step and time-control names', () {
    expect(
      [for (final s in Strength.values) s.label],
      ['Beginner', 'Casual', 'Club', 'Strong', 'Master'],
    );
    expect(const Untimed().label, 'UNTIMED');
    expect(Timed.blitz.label, 'BLITZ 5+0');
    expect(Timed.rapid.label, 'RAPID 10+5');
    expect(Timed.classical.label, 'CLASSICAL 30+0');
    expect(Timed(15, 10).label, 'CUSTOM 15+10');
    expect(
      Timed(5, 0).label,
      'BLITZ 5+0',
      reason: 'labels: a custom control with a preset\'s values is that preset',
    );
  });

  test('names and sub-lines for each mode and side', () {
    const vs = VsComputer(
      playerColour: Colour.black,
      step: Strength.strong,
      seed: 1,
    );
    expect(playerName(vs, Colour.black), 'You');
    expect(playerName(vs, Colour.white), 'Strong');
    expect(
      playerSubLine(vs, Colour.black, Timed.rapid),
      'YOU · BLACK · RAPID 10+5',
    );
    expect(
      playerSubLine(vs, Colour.white, Timed.rapid),
      'COMPUTER · WHITE · RAPID 10+5',
    );
    const two = TwoPlayer();
    expect(playerName(two, Colour.white), 'White');
    expect(playerName(two, Colour.black), 'Black');
    expect(
      playerSubLine(two, Colour.white, const Untimed()),
      'PLAYER ONE · WHITE · UNTIMED',
    );
    expect(
      playerSubLine(two, Colour.black, Timed(15, 10)),
      'PLAYER TWO · BLACK · CUSTOM 15+10',
    );
    expect(gameTitle(vs), 'vs Strong');
    expect(gameTitle(two), 'Two players');
  });

  test('every ending has its word; every draw reads DRAWN', () {
    const words = {
      GameEndReason.checkmate: 'CHECKMATE',
      GameEndReason.stalemate: 'STALEMATE',
      GameEndReason.insufficientMaterial: 'DRAWN',
      GameEndReason.threefoldRepetition: 'DRAWN',
      GameEndReason.fiftyMoves: 'DRAWN',
      GameEndReason.resignation: 'RESIGNED',
      GameEndReason.resignationNoMatingMaterial: 'DRAWN',
      GameEndReason.agreement: 'DRAWN',
      GameEndReason.flag: 'FLAG FALL',
      GameEndReason.flagNoMatingMaterial: 'DRAWN',
    };
    expect(words.keys, unorderedEquals(GameEndReason.values));
    for (final MapEntry(key: reason, value: word) in words.entries) {
      final GameStatus status = switch (reason) {
        GameEndReason.checkmate ||
        GameEndReason.resignation ||
        GameEndReason.flag => Win(Colour.white, reason),
        _ => Draw(reason),
      };
      expect(status.endingWord, word, reason: 'labels: $reason reads $word');
    }
    expect(const Ongoing(inCheck: true).endingWord, isNull);
  });

  test('status chip priority: ending > thinking > check > to move', () {
    final start = Game.start(const TwoPlayer(), const Untimed());
    expect(statusText(start, thinking: false), 'WHITE TO MOVE');
    expect(statusText(start, thinking: true), 'THINKING…');
    final check = Game.start(
      const TwoPlayer(),
      const Untimed(),
      fen: '4k3/8/8/8/8/8/4r3/4K3 w - - 0 1',
    );
    expect(statusText(check, thinking: false), 'WHITE IN CHECK');
    expect(statusText(check, thinking: true), 'THINKING…');
    final resigned = check.resign(Colour.white);
    expect(
      statusText(resigned, thinking: true),
      'RESIGNED',
      reason: 'labels: the ending word outranks THINKING…',
    );
    final black = Game.start(
      const TwoPlayer(),
      const Untimed(),
      fen: '4k3/8/8/8/8/8/8/R3K3 b - - 0 1',
    );
    expect(statusText(black, thinking: false), 'BLACK TO MOVE');
  });

  test('clock text rounds up, tenths under 10 s, ∞ untimed', () {
    const cases = {
      300000: '5:00',
      299001: '5:00',
      252000: '4:12',
      59999: '1:00',
      30000: '0:30',
      29900: '0:30',
      10000: '0:10',
      9999: '0:10.0',
      9400: '0:09.4',
      9301: '0:09.4',
      1000: '0:01.0',
      50: '0:00.1',
      1: '0:00.1',
      0: '0:00.0',
    };
    for (final MapEntry(key: ms, value: text) in cases.entries) {
      expect(clockText(ms), text, reason: 'clock-text: $ms ms reads $text');
    }
    expect(clockText(null), '∞');
  });

  test('clock semantics name the player and speak the rounded time', () {
    expect(clockSemantics('You', 252000), 'You, 4 minutes 12 seconds');
    expect(clockSemantics('Club', 300000), 'Club, 5 minutes');
    expect(clockSemantics('White', 61000), 'White, 1 minute 1 second');
    expect(clockSemantics('Black', 45000), 'Black, 45 seconds');
    expect(clockSemantics('White', 9400), 'White, 9.4 seconds');
    expect(clockSemantics('White', 0), 'White, 0 seconds');
    expect(clockSemantics('White', null), 'White, no clock');
  });
}
