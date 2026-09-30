// The move sequences qa/test-plan.md tells a tester to play (#106) reach the
// positions the plan says they reach: a check that says "play fool's mate"
// must not send the owner into a sequence that is illegal or ends elsewhere.

import 'package:flutter_test/flutter_test.dart';
import 'package:honest_chess/engine/engine.dart';

import '../guards/repo_files.dart';

/// Each sequence's name in the plan → what the position after it must be.
final _expected = <String, void Function(Position after, GameStatus status)>{
  "Fool's mate": (_, s) =>
      expect(s, const Win(Colour.black, GameEndReason.checkmate)),
  "Scholar's mate": (_, s) =>
      expect(s, const Win(Colour.white, GameEndReason.checkmate)),
  'Check': (p, s) {
    expect(s, const Ongoing(inCheck: true));
    expect(p.sideToMove, Colour.black);
  },
  'Stalemate in ten': (p, s) {
    expect(s, const Draw(GameEndReason.stalemate));
    expect(p.sideToMove, Colour.black);
  },
  'Repetition': (_, s) =>
      expect(s, const Draw(GameEndReason.threefoldRepetition)),
  'Promotion': (p, s) {
    expect(s.isOver, isFalse);
    final moves = [for (final m in legalMoves(p)) m.toUci()];
    for (final uci in ['b7b8q', 'b7a8q']) {
      expect(moves, contains(uci), reason: 'plan-sequences: $uci is legal');
    }
  },
  'En passant': (p, s) {
    expect(s.isOver, isFalse);
    expect(p.pieceAt(Square.parse('d5')), isNull);
    expect(p.pieceAt(Square.parse('d6')), Piece.whitePawn);
  },
  'Castling': (p, s) {
    expect(s.isOver, isFalse);
    expect(p.pieceAt(Square.g1), Piece.whiteKing);
    expect(p.pieceAt(Square.parse('f1')), Piece.whiteRook);
  },
};

void main() {
  final plan = readFile('qa/test-plan.md');
  final line = RegExp(r'^- \*\*(.+?)\*\*.*?:( `.*)$', multiLine: true);
  final found = {
    for (final m in line.allMatches(plan))
      m[1]!: [
        for (final code in RegExp(r'`([a-h1-8 ]+)`').allMatches(m[2]!))
          ...code[1]!.split(' '),
      ],
  };

  test('the plan lists every sequence this test knows, and no other', () {
    expect(
      found.keys.toSet(),
      _expected.keys.toSet(),
      reason: 'plan-sequences: the plan and this test name the same sequences',
    );
  });

  for (final MapEntry(key: name, value: check) in _expected.entries) {
    test('$name reaches what the plan says', () {
      final ucis = found[name];
      expect(ucis, isNotNull, reason: 'plan-sequences: $name is in the plan');
      var position = Position.initial();
      final history = [position];
      for (final uci in ucis!) {
        position = play(position, Move.fromUci(position, uci));
        history.add(position);
      }
      check(position, status(history));
    });
  }
}
