import 'package:flutter_test/flutter_test.dart';

import 'package:honest_chess/a11y/move_speech.dart';
import 'package:honest_chess/engine/engine.dart';

/// [uci] played from [fen], spoken.
String say(String fen, String uci) {
  final before = Position.fromFen(fen);
  final move = Move.fromUci(before, uci);
  return moveSpeech(move, before, play(before, move));
}

/// A game played from the start through [ucis].
Game played(List<String> ucis, {GameMode mode = const TwoPlayer()}) {
  var game = Game.start(mode, const Untimed());
  for (final uci in ucis) {
    final computer = mode is VsComputer && game.sideToMove != mode.playerColour;
    game = game.play(Move.fromUci(game.position, uci), byComputer: computer);
  }
  return game;
}

const start = Position.initialFen;

void main() {
  group('moveSpeech', () {
    test('a quiet move names the colour, the piece and the square', () {
      expect(say(start, 'g1f3'), 'White knight to f3');
      expect(say(start, 'e2e4'), 'White pawn to e4');
      expect(
        say(
          'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1',
          'b8c6',
        ),
        'Black knight to c6',
      );
    });

    test('a capture names the piece taken', () {
      expect(
        say('4k3/8/8/4p3/8/5N2/8/4K3 w - - 0 1', 'f3e5'),
        'White knight takes black pawn on e5',
      );
      expect(
        say('4k3/8/8/4q3/8/5N2/8/3K4 b - - 0 1', 'e5f4'),
        'Black queen to f4',
      );
      expect(
        say('4k3/8/8/8/5q2/8/6N1/4K3 w - - 0 1', 'g2f4'),
        'White knight takes black queen on f4',
      );
    });

    test('en passant says so, on the square the pawn lands', () {
      expect(
        say('4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1', 'e5d6'),
        'White pawn takes black pawn en passant on d6',
      );
      expect(
        say('4k3/8/8/8/3pP3/8/8/4K3 b - e3 0 1', 'd4e3'),
        'Black pawn takes white pawn en passant on e3',
      );
    });

    test('castling names the side, not the squares', () {
      const fen = 'r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1';
      expect(say(fen, 'e1g1'), 'White castles king side');
      expect(say(fen, 'e1c1'), 'White castles queen side');
      const black = 'r3k2r/8/8/8/8/8/8/R3K2R b KQkq - 0 1';
      expect(say(black, 'e8g8'), 'Black castles king side');
      expect(say(black, 'e8c8'), 'Black castles queen side');
    });

    test('each promotion names the piece', () {
      const fen = '8/P6k/8/8/8/8/8/4K3 w - - 0 1';
      for (final (letter, name) in const [
        ('q', 'queen'),
        ('r', 'rook'),
        ('b', 'bishop'),
        ('n', 'knight'),
      ]) {
        expect(say(fen, 'a7a8$letter'), 'White pawn to a8, promotes to $name');
      }
      expect(
        say('1r5k/P7/8/8/8/8/8/4K3 w - - 0 1', 'a7b8n'),
        'White pawn takes black rook on b8, promotes to knight',
      );
    });

    test('check and checkmate follow the move; a quiet move has neither', () {
      expect(
        say('4k3/8/8/8/8/8/8/R3K3 w - - 0 1', 'a1a8'),
        'White rook to a8, check',
      );
      expect(
        say('6k1/5ppp/8/8/8/8/8/R3K3 w - - 0 1', 'a1a8'),
        'White rook to a8, checkmate',
      );
      expect(
        say('4k3/P7/8/8/8/8/8/4K3 w - - 0 1', 'a7a8q'),
        'White pawn to a8, promotes to queen, check',
      );
      expect(
        say('r3k2r/8/8/8/8/8/8/R3K1R1 b kq - 0 1', 'e8c8'),
        isNot(contains('check')),
      );
      expect(
        say('5k2/8/8/8/8/8/8/4K2R w K - 0 1', 'e1g1'),
        'White castles king side, check',
      );
      expect(
        say('6k1/8/8/3pP3/8/1B6/8/4K3 w - d6 0 1', 'e5d6'),
        'White pawn takes black pawn en passant on d6, check',
      );
    });

    test('fool\'s mate ends in words', () {
      final game = played(['f2f3', 'e7e5', 'g2g4', 'd8h4']);
      final history = game.history;
      expect(
        moveSpeech(
          history.last.move!,
          history[history.length - 2].position,
          game.position,
        ),
        'Black queen to h4, checkmate',
      );
      expect(resultSpeech(game), 'Black wins. Black delivers checkmate.');
    });

    test('a move from an empty square is an error, not words', () {
      final before = Position.initial();
      final move = Move.fromUci(before, 'e2e4');
      final after = play(before, move);
      expect(() => moveWords(move, after), throwsArgumentError);
    });
  });

  group('the other sentences', () {
    test('the result reads the card\'s tag, then its title', () {
      final vs = played(
        ['f2f3', 'e7e5', 'g2g4', 'd8h4'],
        mode: const VsComputer(
          playerColour: Colour.black,
          step: Strength.club,
          seed: 1,
        ),
      );
      expect(resultSpeech(vs), 'You win. Black delivers checkmate.');
      final resigned = played(['e2e4']).resign(Colour.black);
      expect(resultSpeech(resigned), 'White wins. Black resigned.');
    });

    test('a start says new or restarted, and who plays', () {
      final two = played([]);
      final vs = Game.start(
        const VsComputer(
          playerColour: Colour.black,
          step: Strength.club,
          seed: 1,
        ),
        const Untimed(),
      );
      expect(startSpeech(two, restart: false), 'New game, two players');
      expect(startSpeech(two, restart: true), 'Game restarted, two players');
      expect(startSpeech(vs, restart: false), 'New game, you play Black');
      expect(startSpeech(vs, restart: true), 'Game restarted, you play Black');
    });

    test('a restore says whose move it is', () {
      expect(restoreSpeech(played(['e2e4'])), 'Game restored, Black to move');
    });

    test('a takeback names the earliest move undone', () {
      final before = played(['g1f3', 'e7e5']);
      final one = played(['g1f3']);
      expect(takebackSpeech(one, before), 'Took back Black pawn to e5');
      expect(
        takebackSpeech(played([]), before),
        'Took back White knight to f3',
      );
      expect(takebackSpeech(one, null), 'Took back');
      expect(takebackSpeech(before, one), 'Took back');
    });

    test('refusal, selection and the computer thinking', () {
      expect(
        refusalSpeech(PieceKind.knight),
        "Knight can't move there, put down",
      );
      expect(selectedSpeech(Piece.whiteKnight), 'White knight selected');
      expect(
        thinkingSpeech(
          const VsComputer(
            playerColour: Colour.white,
            step: Strength.club,
            seed: 1,
          ),
        ),
        'Club is thinking',
      );
    });
  });
}
