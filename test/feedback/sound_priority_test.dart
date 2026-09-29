import 'package:flutter_test/flutter_test.dart';

import 'package:honest_chess/data/game_event.dart';
import 'package:honest_chess/engine/engine.dart';
import 'package:honest_chess/feedback/clips.dart';
import 'package:honest_chess/feedback/game_feedback.dart';
import 'package:honest_chess/feedback/sound_priority.dart';

/// [uci] played from [fen] by a player in a two-player game, and the game
/// after it.
({Move move, Game after}) playFrom(String fen, String uci, {GameMode? mode}) {
  final game = Game.start(mode ?? const TwoPlayer(), const Untimed(), fen: fen);
  final move = Move.fromUci(game.position, uci);
  final byComputer = switch (game.mode) {
    VsComputer(:final computerColour) => game.sideToMove == computerColour,
    TwoPlayer() => false,
  };
  return (move: move, after: game.play(move, byComputer: byComputer));
}

Clip clipAfter(String fen, String uci, {GameMode? mode}) {
  final played = playFrom(fen, uci, mode: mode);
  return clipFor(played.move, played.after);
}

Game playAll(List<String> ucis, {Game? from}) {
  var game = from ?? Game.start(const TwoPlayer(), const Untimed());
  for (final uci in ucis) {
    game = game.play(Move.fromUci(game.position, uci));
  }
  return game;
}

/// Each case: a position, a move, the one clip it must play.
const cases = <({String name, String fen, String uci, Clip clip})>[
  (
    name: 'a quiet move',
    fen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
    uci: 'e2e4',
    clip: Clip.move,
  ),
  (
    name: 'a capture',
    fen: '4k3/8/8/3p4/4P3/8/8/4K3 w - - 0 1',
    uci: 'e4d5',
    clip: Clip.capture,
  ),
  (
    name: 'en passant',
    fen: '4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1',
    uci: 'e5d6',
    clip: Clip.capture,
  ),
  (
    name: 'castling',
    fen: '4k3/8/8/8/8/8/8/4K2R w K - 0 1',
    uci: 'e1g1',
    clip: Clip.castle,
  ),
  (
    name: 'castling with check',
    fen: '5k2/8/8/8/8/8/8/4K2R w K - 0 1',
    uci: 'e1g1',
    clip: Clip.check,
  ),
  (
    name: 'a quiet check',
    fen: '4k3/8/8/8/8/8/8/R3K3 w - - 0 1',
    uci: 'a1a8',
    clip: Clip.check,
  ),
  (
    name: 'a capture with check',
    fen: '3qk3/8/8/8/8/8/8/3QK3 w - - 0 1',
    uci: 'd1d8',
    clip: Clip.check,
  ),
  (
    name: 'a quiet promotion',
    fen: '8/P6k/8/8/8/8/8/4K3 w - - 0 1',
    uci: 'a7a8q',
    clip: Clip.move,
  ),
  (
    name: 'a promotion capturing',
    fen: '1n6/P6k/8/8/8/8/8/4K3 w - - 0 1',
    uci: 'a7b8q',
    clip: Clip.capture,
  ),
  (
    name: 'a promotion with check',
    fen: '7k/P7/8/8/8/8/8/4K3 w - - 0 1',
    uci: 'a7a8q',
    clip: Clip.check,
  ),
  (
    name: 'a capture that mates',
    fen: 'r5k1/5ppp/8/8/8/8/8/R3K3 w - - 0 1',
    uci: 'a1a8',
    clip: Clip.end,
  ),
  (
    name: 'a move that stalemates',
    fen: '7k/8/8/5Q2/8/8/8/4K3 w - - 0 1',
    uci: 'f5f7',
    clip: Clip.end,
  ),
];

void main() {
  group('clipFor: one clip per move, by priority', () {
    for (final c in cases) {
      test(c.name, () {
        expect(clipAfter(c.fen, c.uci), c.clip);
      });
    }

    test('a mate plays only the end, not the check', () {
      final mated = playAll(['f2f3', 'e7e5', 'g2g4', 'd8h4']);
      expect(mated.isOver, isTrue);
      expect(inCheck(mated.position), isTrue);
      expect(clipFor(mated.history.last.move!, mated), Clip.end);
    });

    test('the effects never include the music loop', () {
      final heard = {for (final c in cases) clipAfter(c.fen, c.uci)};
      expect(heard, isNot(contains(Clip.music)));
      expect(heard, {
        Clip.move,
        Clip.capture,
        Clip.castle,
        Clip.check,
        Clip.end,
      });
    });

    test("the computer's move sounds the same as the same move by you", () {
      for (final c in cases) {
        final white = Colour.white;
        final you = clipAfter(
          c.fen,
          c.uci,
          mode: VsComputer(playerColour: white, step: Strength.club, seed: 1),
        );
        final computer = clipAfter(
          c.fen,
          c.uci,
          mode: VsComputer(
            playerColour: white.opponent,
            step: Strength.club,
            seed: 1,
          ),
        );
        expect(computer, you, reason: c.name);
        expect(you, c.clip, reason: c.name);
      }
    });
  });

  group('clipForEvent', () {
    final start = Game.start(const TwoPlayer(), const Untimed());
    final moved = playAll(['e2e4']);
    final mated = playAll(['f2f3', 'e7e5', 'g2g4', 'd8h4']);
    const none = <String, Object?>{};

    test('a move plays its clip', () {
      expect(clipForEvent(GameMoved(moved, none)), Clip.move);
      expect(clipForEvent(GameMoved(mated, none)), Clip.end);
    });

    test("a mate's end event plays nothing more", () {
      expect(clipForEvent(GameEnded(mated, none)), isNull);
    });

    test('an end with no move of its own plays the end', () {
      expect(
        clipForEvent(GameEnded(moved.resign(Colour.black), none)),
        Clip.end,
      );
      final both = playAll(['e7e5'], from: moved);
      expect(clipForEvent(GameEnded(both.agreeDraw(), none)), Clip.end);
    });

    test('takeback, new games, pauses and restores play nothing', () {
      for (final event in <GameEvent>[
        GameStarted(start, none),
        GameTookBack(start, none),
        GamePaused(moved, none),
        GameResumed(moved, none),
        GameRestored(moved, none),
        GameAbandoned(moved, none),
        GameStarted(mated, none),
        GameRestored(mated, none),
      ]) {
        expect(clipForEvent(event), isNull, reason: '${event.runtimeType}');
      }
    });
  });
}
