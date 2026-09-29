// Legal move generation, one FIDE clause at a time. The perft guard
// (test/guards/perft_test.dart) proves the clauses together; these tests
// name each one, and the refusals — what must NOT be offered — are tagged
// `guard` with reasons starting `movegen:` so tools/mutation_check.py can
// require the right one to fire.

import 'package:flutter_test/flutter_test.dart';
import 'package:honest_chess/engine/engine.dart';
import 'package:honest_chess/engine/src/board.dart';

import '../fixtures/fens.dart';

Position _fen(String fen) => Position.fromFen(fen);

Set<String> _uci(Position p) => {for (final m in legalMoves(p)) m.toUci()};

/// The destinations of the legal moves from [square].
Set<String> _from(Position p, String square) => {
  for (final m in legalMoves(p))
    if (m.from.name == square) m.to.name,
};

/// [p] after the moves in [ucis], each of which must be legal.
Position _play(Position p, List<String> ucis) {
  for (final uci in ucis) {
    final board = Board.fromPosition(p)..make(Move.fromUci(p, uci).packed);
    p = board.toPosition();
  }
  return p;
}

const _guard = ['guard'];

void main() {
  final fixtures = [for (final f in allFens) _fen(f)];

  group('3.1 moves and attacks', () {
    test('3.1: no move ends on a square of the mover\'s own piece', () {
      for (final p in fixtures) {
        for (final m in legalMoves(p)) {
          expect(
            p.pieceAt(m.to)?.colour,
            isNot(p.sideToMove),
            reason: '${p.toFen()}: $m',
          );
        }
      }
    });

    test('3.1.2: isAttacked holds for every square a piece captures on', () {
      for (final p in fixtures) {
        for (final m in legalMoves(p)) {
          if (m.isCapture && !m.isEnPassant) {
            expect(
              isAttacked(p, m.to, p.sideToMove),
              isTrue,
              reason: '${p.toFen()}: $m',
            );
          }
        }
      }
      // A pawn attacks diagonally forward only — not ahead, not behind.
      final p = _fen('k7/8/8/8/4P3/8/8/7K w - - 0 1');
      for (final (square, attacked) in [
        ('d5', true),
        ('f5', true),
        ('e5', false),
        ('d3', false),
        ('f3', false),
      ]) {
        expect(
          isAttacked(p, Square.parse(square), Colour.white),
          attacked,
          reason: square,
        );
      }
    });

    test('3.1.3: a pinned piece still attacks', () {
      // The white knight on e2 is pinned to its king by the rook on e8, yet
      // the black king still may not step onto c3 or d4, which it attacks.
      final p = _fen('4r3/8/8/8/2k5/8/4N3/4K3 b - - 0 1');
      expect(isAttacked(p, Square.parse('c3'), Colour.white), isTrue);
      expect(isAttacked(p, Square.parse('d4'), Colour.white), isTrue);
      expect(
        _from(p, 'c4'),
        isNot(anyOf(contains('c3'), contains('d4'))),
        reason:
            'movegen: the king stepped onto a square a pinned piece attacks',
      );
      expect(_from(p, 'c4'), containsAll(['b3', 'b4', 'b5', 'c5', 'd5', 'd3']));
    }, tags: _guard);
  });

  group('3.2–3.6 pieces', () {
    Set<String> squares(String names) => names.split(' ').toSet();
    const diagonals = 'a1 b2 c3 e5 f6 g7 h8 a7 b6 c5 e3 f2 g1';
    const lines = 'd1 d2 d3 d5 d6 d7 d8 a4 b4 c4 e4 f4 g4 h4';

    test('3.2: a bishop moves along its diagonals only', () {
      expect(
        _from(_fen('k7/8/8/8/3B4/8/8/7K w - - 0 1'), 'd4'),
        squares(diagonals),
      );
    });

    test('3.3: a rook moves along its file and rank only', () {
      expect(
        _from(_fen('k7/8/8/8/3R4/8/8/7K w - - 0 1'), 'd4'),
        squares(lines),
      );
    });

    test('3.4: a queen moves along its file, rank and diagonals', () {
      expect(
        _from(_fen('k7/8/8/8/3Q4/8/8/7K w - - 0 1'), 'd4'),
        squares('$diagonals $lines'),
      );
    });

    test('3.5: no slider passes through an occupied square', () {
      // Own pawn on d6 stops the rook short; enemy pawn on f4 is captured
      // and nothing beyond it is reached.
      expect(
        _from(_fen('k7/8/3P4/8/3R1p2/8/8/7K w - - 0 1'), 'd4'),
        squares('d5 d3 d2 d1 c4 b4 a4 e4 f4'),
      );
      expect(
        _from(_fen('k7/8/5P2/8/3B4/8/1p6/7K w - - 0 1'), 'd4'),
        squares('e5 c5 b6 a7 c3 b2 e3 f2 g1'),
      );
    });

    test('3.6: a knight reaches its eight squares, over occupied ones', () {
      expect(
        _from(_fen('k7/8/8/2PPP3/2PNP3/2PPP3/8/7K w - - 0 1'), 'd4'),
        squares('b3 b5 c2 c6 e2 e6 f3 f5'),
      );
    });
  });

  group('3.7 pawns', () {
    test('3.7 / 3.7.1: one square forward onto an empty square only', () {
      expect(_from(_fen('k7/8/8/8/4P3/8/8/7K w - - 0 1'), 'e4'), {'e5'});
      expect(_from(_fen('k7/8/8/4p3/8/8/8/7K b - - 0 1'), 'e5'), {'e4'});
      expect(
        _from(_fen('k7/8/8/4p3/4P3/8/8/7K w - - 0 1'), 'e4'),
        isEmpty,
        reason: 'a pawn never captures straight ahead',
      );
    });

    test('3.7.2: two squares only from the start, across empty squares', () {
      expect(_from(_fen('k7/8/8/8/8/8/4P3/7K w - - 0 1'), 'e2'), {'e3', 'e4'});
      expect(_from(_fen('k7/4p3/8/8/8/8/8/7K b - - 0 1'), 'e7'), {'e6', 'e5'});
      expect(_from(_fen('k7/8/8/8/8/4P3/8/7K w - - 0 1'), 'e3'), {'e4'});
      expect(_from(_fen('k7/8/8/8/4n3/8/4P3/7K w - - 0 1'), 'e2'), {'e3'});
      expect(_from(_fen('k7/8/8/8/8/4n3/4P3/7K w - - 0 1'), 'e2'), isEmpty);
    });

    test('3.7.3: captures diagonally forward only, never onto an empty '
        'diagonal', () {
      // Enemy pieces behind the pawn (d3, f3) are not capturable; f5 is
      // empty, so no diagonal move goes there.
      expect(_from(_fen('k7/8/8/3n4/4P3/3n1n2/8/7K w - - 0 1'), 'e4'), {
        'e5',
        'd5',
      });
    });

    test('3.7.3.1: en passant captures the pawn that just advanced two '
        'squares, and only that pawn', () {
      final start = _fen('4k3/3p4/8/4P3/8/8/8/4K3 b - - 0 1');
      final afterDouble = _play(start, ['d7d5']);
      expect(_uci(afterDouble), contains('e5d6'));
      final captured = _play(afterDouble, ['e5d6']);
      expect(captured.pieceAt(Square.parse('d5')), isNull);
      expect(captured.pieceAt(Square.parse('d6')), Piece.whitePawn);

      // The same pawn arriving on d5 in two single steps is not capturable.
      final twoSteps = _play(start, ['d7d6', 'e1d1', 'd6d5']);
      expect(
        _uci(twoSteps),
        isNot(contains('e5d6')),
        reason: 'movegen: en passant against a pawn that arrived in two steps',
      );
    }, tags: _guard);

    test('3.7.3.2: en passant only on the immediately following move', () {
      final p = _play(_fen('4k3/3p4/8/4P3/8/8/8/4K3 b - - 0 1'), [
        'd7d5',
        'e1d1',
        'e8f8',
      ]);
      expect(
        _uci(p),
        isNot(contains('e5d6')),
        reason: 'movegen: en passant was offered a move late',
      );
      expect(p.enPassant, isNull);
    }, tags: _guard);

    test('3.7.3.3 / 3.7.3.4: exactly four promotions per destination, '
        'whatever is still on the board', () {
      // White still has its queen; promotion to a queen is offered anyway.
      final p = _fen('k2r4/4P3/8/8/8/8/8/1Q5K w - - 0 1');
      final promotions = [
        for (final m in legalMoves(p))
          if (m.from.name == 'e7') m,
      ];
      expect(
        promotions.map((m) => m.promotion),
        everyElement(isNot(anyOf(PieceKind.king, PieceKind.pawn, isNull))),
        reason: 'movegen: a pawn promoted to a king, a pawn or nothing',
      );
      expect(
        {for (final m in promotions) m.toUci()},
        {
          for (final to in ['e8', 'd8'])
            for (final k in 'qrbn'.split('')) 'e7$to$k',
        },
      );
      expect(promotions, hasLength(8));
      expect(
        _play(p, ['e7d8n']).pieceAt(Square.parse('d8')),
        Piece.whiteKnight,
      );
      // Black promotes downwards, the same four ways.
      expect(_from(_fen('k7/8/8/8/8/8/p7/7K b - - 0 1'), 'a2'), {'a1'});
      expect(
        _uci(_fen('k7/8/8/8/8/8/p7/7K b - - 0 1'))
            .where((u) => u.startsWith('a2a1')),
        hasLength(4),
      );
    }, tags: _guard);
  });

  group('3.8 the king', () {
    test('3.8 / 3.8.1: one step to any square not attacked', () {
      // The rook on a5 covers rank 5.
      expect(_from(_fen('7k/8/8/r7/4K3/8/8/8 w - - 0 1'), 'e4'), {
        'd3',
        'e3',
        'f3',
        'd4',
        'f4',
      });
    });

    test('3.8.2: castling moves the king two squares and the rook to the '
        'square the king crossed', () {
      final p = _fen('r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1');
      expect(_uci(p), containsAll(['e1g1', 'e1c1']));
      expect(_play(p, ['e1g1']).toFen(), 'r3k2r/8/8/8/8/8/8/R4RK1 b kq - 1 1');
      expect(_play(p, ['e1c1']).toFen(), 'r3k2r/8/8/8/8/8/8/2KR3R b kq - 1 1');
      expect(
        _play(p, ['e1g1', 'e8c8']).toFen(),
        '2kr3r/8/8/8/8/8/8/R4RK1 w - - 2 2',
      );
      expect(legalMoves(p).where((m) => m.isCastling), hasLength(2));
    });

    test('3.8.2.1: no castling once the king or that rook has moved', () {
      final p = _fen('r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1');
      final kingMoved = _play(p, ['e1f1', 'a8b8', 'f1e1', 'b8a8']);
      expect(
        _uci(kingMoved),
        isNot(anyOf(contains('e1g1'), contains('e1c1'))),
        reason: 'movegen: castled after the king had moved',
      );
      final rookMoved = _play(p, ['h1h2', 'a8b8', 'h2h1', 'b8a8']);
      expect(
        _uci(rookMoved),
        isNot(contains('e1g1')),
        reason: 'movegen: castled with a rook that had moved',
      );
      expect(_uci(rookMoved), contains('e1c1'));
      // A rook captured on its home square takes that right with it.
      final captured = _play(p, ['a1a8']);
      expect(
        captured.castlingRights,
        Castling.whiteKingside | Castling.blackKingside,
      );
    }, tags: _guard);

    test('3.8.2.2: no castling out of, through or into check, or across an '
        'occupied square', () {
      for (final (fen, move, why) in [
        ('4r1k1/8/8/8/8/8/8/R3K2R w KQ - 0 1', 'e1g1', 'out of check'),
        ('4r1k1/8/8/8/8/8/8/R3K2R w KQ - 0 1', 'e1c1', 'out of check'),
        (
          '4kr2/8/8/8/8/8/8/4K2R w K - 0 1',
          'e1g1',
          'through an attacked square',
        ),
        (
          '3rk3/8/8/8/8/8/8/R3K3 w Q - 0 1',
          'e1c1',
          'through an attacked square',
        ),
        ('4k1r1/8/8/8/8/8/8/4K2R w K - 0 1', 'e1g1', 'into check'),
        ('2r1k3/8/8/8/8/8/8/R3K3 w Q - 0 1', 'e1c1', 'into check'),
        (
          '4k3/8/8/8/8/8/8/4K1NR w K - 0 1',
          'e1g1',
          'across an occupied square',
        ),
        (
          '4k3/8/8/8/8/8/8/RN2K3 w Q - 0 1',
          'e1c1',
          'across an occupied square',
        ),
        ('r3k2r/8/8/8/8/8/8/4K1Q1 b kq - 0 1', 'e8g8', 'into check'),
        (
          'r3k2r/8/8/8/8/8/8/3QK3 b kq - 0 1',
          'e8c8',
          'through an attacked square',
        ),
      ]) {
        expect(
          _uci(_fen(fen)),
          isNot(contains(move)),
          reason: 'movegen: castling $why ($fen $move)',
        );
      }
      // The rook may cross an attacked square: only the king's path counts.
      expect(_uci(_fen('1r2k3/8/8/8/8/8/8/R3K3 w Q - 0 1')), contains('e1c1'));
    }, tags: _guard);
  });

  group('3.9 check', () {
    test('3.9 / 3.9.1: inCheck is exactly "the mover\'s king is attacked"', () {
      for (final p in fixtures) {
        expect(
          inCheck(p),
          isAttacked(p, p.kingSquare(p.sideToMove), p.sideToMove.opponent),
          reason: p.toFen(),
        );
      }
      expect(inCheck(_fen('4k3/8/8/8/8/8/4r3/4K3 w - - 0 1')), isTrue);
      expect(inCheck(Position.initial()), isFalse);
      // A pinned knight still gives check.
      expect(inCheck(_fen('8/8/k7/8/2n5/8/3KB3/8 w - - 0 1')), isTrue);
    });

    test('1.4.1 / 3.9.2: no move leaves or places the mover\'s king in '
        'check', () {
      for (final p in fixtures) {
        for (final m in legalMoves(p)) {
          expect(
            isInCheck(_play(p, [m.toUci()]), p.sideToMove),
            isFalse,
            reason: 'movegen: $m left its king attacked in ${p.toFen()}',
          );
        }
      }
      // A pinned rook moves along the pin only; a pinned bishop not at all.
      expect(_from(_fen('4r2k/8/8/8/8/8/4R3/4K3 w - - 0 1'), 'e2'), {
        'e3',
        'e4',
        'e5',
        'e6',
        'e7',
        'e8',
      }, reason: 'movegen: a pinned rook left its pin line');
      expect(
        _from(_fen('4r2k/8/8/8/8/8/4B3/4K3 w - - 0 1'), 'e2'),
        isEmpty,
        reason: 'movegen: a pinned bishop moved',
      );
      // The king may not step back along the checking rook's line.
      expect(_from(_fen('4k3/8/8/8/8/8/8/r3K3 w - - 0 1'), 'e1'), {
        'e2',
        'd2',
        'f2',
      }, reason: 'movegen: the king stayed on the checking line');
      // En passant would remove both pawns from rank 5 and expose the king
      // to the rook: the horizontal en-passant pin.
      final p = _fen('8/8/8/K2pP2r/8/8/8/7k w - d6 0 1');
      expect(
        _uci(p),
        isNot(contains('e5d6')),
        reason: 'movegen: en passant exposed the king along the rank',
      );
      expect(_uci(p), contains('e5e6'));
    }, tags: _guard);
  });

  group('3.10 legal moves', () {
    test('3.10 / 3.10.1 / 3.10.2: the move counts of every reference '
        'position match the published perft counts to depth 2', () {
      const published = {
        'initial': [20, 400],
        'kiwipete': [48, 2039],
        'position3': [14, 191],
        'position4': [6, 264],
        'position4-mirrored': [6, 264],
        'position5': [44, 1486],
        'position6': [46, 2079],
      };
      for (final MapEntry(:key, :value) in published.entries) {
        final p = _fen(cpwPerftFens[key]!);
        expect(legalMoves(p), hasLength(value[0]), reason: key);
        expect(perft(p, 2), value[1], reason: key);
      }
    });

    test('the order is deterministic and there are no duplicates', () {
      for (final p in fixtures) {
        final a = legalMoves(p), b = legalMoves(_fen(p.toFen()));
        expect(a, b);
        expect(a.toSet(), hasLength(a.length));
      }
    });

    test('make then unmake restores every fixture exactly', () {
      for (final p in fixtures) {
        final board = Board.fromPosition(p);
        for (final m in legalMoves(p)) {
          board
            ..make(m.packed)
            ..unmake();
          expect(board.toPosition(), p, reason: '$m in ${p.toFen()}');
        }
      }
    });

    test('making a move updates the counters and the en-passant square', () {
      expect(
        _play(Position.initial(), ['e2e4']).toFen(),
        'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1',
      );
      expect(
        _play(Position.initial(), ['g1f3', 'g8f6', 'f3g1']).toFen(),
        'rnbqkb1r/pppppppp/5n2/8/8/8/PPPPPPPP/RNBQKBNR b KQkq - 3 2',
      );
    });
  });

  group('UCI', () {
    test('moves print as from, to and a lower-case promotion', () {
      expect(Move.fromUci(Position.initial(), 'e2e4').toUci(), 'e2e4');
      final p = _fen('k7/4P3/8/8/8/8/8/7K w - - 0 1');
      final m = Move.fromUci(p, 'e7e8q');
      expect(m.promotion, PieceKind.queen);
      expect(m.toString(), 'e7e8q');
    });

    test('every legal move round-trips through its UCI form', () {
      for (final p in fixtures) {
        for (final m in legalMoves(p)) {
          final back = Move.fromUci(p, m.toUci());
          expect(back, m);
          expect(back.packed, m.packed);
        }
      }
    });

    test('anything not the UCI form of a legal move is refused', () {
      final p = Position.initial();
      for (final bad in [
        '',
        'e2',
        'E2E4',
        'e2e5',
        'e2e4q',
        'e1g1',
        ' e2e4',
        'e2e4 ',
        'e2-e4',
      ]) {
        expect(
          () => Move.fromUci(p, bad),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              startsWith('move:'),
            ),
          ),
          reason: bad,
        );
      }
      final promo = _fen('k7/4P3/8/8/8/8/8/7K w - - 0 1');
      for (final bad in ['e7e8', 'e7e8Q', 'e7e8k', 'e7e8p']) {
        expect(() => Move.fromUci(promo, bad), throwsFormatException);
      }
    });

    test('equality is on from, to and promotion only', () {
      final m = Move.fromUci(Position.initial(), 'e2e4');
      expect(Move.packed(m.packed & ~Move.doublePush), m);
      expect(Move.packed(m.packed & ~Move.doublePush).hashCode, m.hashCode);
      expect(Move.fromUci(Position.initial(), 'e2e3'), isNot(m));
    });
  });

  group('perft', () {
    test('depth 0 is one node; a negative depth is refused', () {
      expect(perft(Position.initial(), 0), 1);
      expect(() => perft(Position.initial(), -1), throwsArgumentError);
      expect(() => divide(Position.initial(), 0), throwsArgumentError);
    });

    test('divide splits perft by first move', () {
      final p = _fen(cpwPerftFens['kiwipete']!);
      final split = divide(p, 2);
      expect(split.keys.toSet(), _uci(p));
      expect(split.values.fold(0, (a, b) => a + b), perft(p, 2));
    });
  });
}
