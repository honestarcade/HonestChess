import 'package:flutter_test/flutter_test.dart';
import 'package:honest_chess/engine/engine.dart';

import '../fixtures/fens.dart';

Matcher _refusedWith(String token) => throwsA(
  isA<FormatException>().having((e) => e.message, 'message', startsWith(token)),
);

void main() {
  group('squares (FIDE 1.1, 2.1, 2.4)', () {
    test('1.1: two sides and 64 addressable squares a1–h8', () {
      expect(Colour.values, hasLength(2));
      expect(Square.values, hasLength(64));
      final names = <String>{};
      for (var rank = 0; rank < 8; rank++) {
        for (var file = 0; file < 8; file++) {
          final sq = Square.at(file, rank);
          expect(sq.file, file);
          expect(sq.rank, rank);
          expect(Square.parse(sq.name), sq);
          names.add(sq.name);
        }
      }
      expect(names, hasLength(64));
      expect(Square.parse('a1').index, 0);
      expect(Square.parse('h8').index, 63);
    });

    test('Square.parse refuses anything but a1–h8', () {
      for (final bad in [
        '',
        'a',
        'a0',
        'a9',
        'i1',
        'A1',
        ' a1',
        'a1 ',
        'e44',
      ]) {
        expect(() => Square.parse(bad), _refusedWith('square:'), reason: bad);
      }
    });

    test('2.1: h1 light, a1 dark, colours alternate on all 64', () {
      expect(Square.parse('h1').isLight, isTrue);
      expect(Square.parse('a1').isLight, isFalse);
      for (final sq in Square.values) {
        if (sq.file < 7) {
          expect(
            Square.at(sq.file + 1, sq.rank).isLight,
            isNot(sq.isLight),
            reason: '${sq.name} and its right neighbour',
          );
        }
        if (sq.rank < 7) {
          expect(
            Square.at(sq.file, sq.rank + 1).isLight,
            isNot(sq.isLight),
            reason: '${sq.name} and the square above',
          );
        }
      }
      expect(Square.values.where((s) => s.isLight), hasLength(32));
    });

    test('2.4: files, ranks and both diagonal directions', () {
      final e4 = Square.parse('e4');
      expect(e4.file, 4);
      expect(e4.rank, 3);
      expect(e4.isSameFile(Square.parse('e8')), isTrue);
      expect(e4.isSameFile(Square.parse('d4')), isFalse);
      expect(e4.isSameRank(Square.parse('a4')), isTrue);
      expect(e4.isSameRank(Square.parse('e5')), isFalse);
      // a1–h8 direction and a8–h1 direction.
      expect(e4.isSameDiagonal(Square.parse('h7')), isTrue);
      expect(e4.isSameDiagonal(Square.parse('b1')), isTrue);
      expect(e4.isSameDiagonal(Square.parse('a8')), isTrue);
      expect(e4.isSameDiagonal(Square.parse('h1')), isTrue);
      expect(e4.isSameDiagonal(Square.parse('e5')), isFalse);
      expect(e4.isSameDiagonal(Square.parse('f6')), isFalse);
      expect(e4.isSameDiagonal(e4), isFalse);
      expect(Square.parse('a1').isSameDiagonal(Square.parse('h8')), isTrue);
    });
  });

  group('the initial position (FIDE 1.2, 2.2, 2.3)', () {
    final initial = Position.initial();

    test('its FEN is exactly the standard one', () {
      expect(
        initial.toFen(),
        'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
      );
      expect(initial, Position.fromFen(Position.initialFen));
    });

    test('1.2: White moves first', () {
      expect(initial.sideToMove, Colour.white);
      expect(initial.castlingRights, Castling.all);
      expect(initial.enPassant, isNull);
      expect(initial.halfmoveClock, 0);
      expect(initial.fullmoveNumber, 1);
    });

    test('2.2: 16 pieces per side in FIDE counts', () {
      const counts = {
        PieceKind.king: 1,
        PieceKind.queen: 1,
        PieceKind.rook: 2,
        PieceKind.bishop: 2,
        PieceKind.knight: 2,
        PieceKind.pawn: 8,
      };
      for (final colour in Colour.values) {
        var total = 0;
        for (final MapEntry(key: kind, value: n) in counts.entries) {
          final onBoard = Square.values
              .where((s) => initial.pieceAt(s) == Piece.of(colour, kind))
              .length;
          expect(onBoard, n, reason: '${colour.name} ${kind.name}');
          total += onBoard;
        }
        expect(total, 16);
      }
      expect(Piece.values, hasLength(12));
    });

    test('2.3: placement square by square', () {
      const back = [
        PieceKind.rook,
        PieceKind.knight,
        PieceKind.bishop,
        PieceKind.queen,
        PieceKind.king,
        PieceKind.bishop,
        PieceKind.knight,
        PieceKind.rook,
      ];
      for (final sq in Square.values) {
        final expected = switch (sq.rank) {
          0 => Piece.of(Colour.white, back[sq.file]),
          1 => Piece.whitePawn,
          6 => Piece.blackPawn,
          7 => Piece.of(Colour.black, back[sq.file]),
          _ => null,
        };
        expect(initial.pieceAt(sq), expected, reason: sq.name);
      }
      expect(initial.pieceAt(Square.parse('d1')), Piece.whiteQueen);
      expect(initial.pieceAt(Square.parse('d8')), Piece.blackQueen);
      expect(initial.kingSquare(Colour.white), Square.e1);
      expect(initial.kingSquare(Colour.black), Square.e8);
    });
  });

  group('FEN round trip', () {
    test('the fixture list has at least 20 FENs and the six CPW positions', () {
      expect(allFens.length, greaterThanOrEqualTo(20));
      expect(allFens.toSet(), hasLength(allFens.length));
      expect(
        cpwPerftFens.keys,
        containsAll(['initial', 'kiwipete', 'position6']),
      );
    });

    for (final fen in allFens) {
      test('round-trips byte for byte: $fen', () {
        final position = Position.fromFen(fen);
        expect(position.toFen(), fen);
        expect(Position.fromFen(position.toFen()), position);
        expect(Position.fromFen(fen).hashCode, position.hashCode);
      });
    }

    test('value equality covers every FEN field', () {
      const base = '4k3/8/8/8/8/8/8/R3K3 w Q - 0 1';
      final variants = [
        '4k3/8/8/8/8/8/8/R3K3 b Q - 0 1',
        '4k3/8/8/8/8/8/8/R3K3 w - - 0 1',
        '4k3/8/8/8/8/8/8/R3K3 w Q - 1 1',
        '4k3/8/8/8/8/8/8/R3K3 w Q - 0 2',
        '4k3/8/8/8/8/8/R7/4K3 w - - 0 1',
      ];
      for (final v in variants) {
        expect(Position.fromFen(v), isNot(Position.fromFen(base)), reason: v);
      }
      expect(
        Position.fromFen(
          'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1',
        ),
        isNot(
          Position.fromFen(
            'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1',
          ),
        ),
      );
    });
  });

  group('malformed FEN is refused, never partially parsed (FIDE 3.10.3)', () {
    const ok = '4k3/8/8/8/8/8/8/4K3 w - - 0 1';
    const cases = <String, String>{
      // Fields.
      '4k3/8/8/8/8/8/8/4K3 w - - 0': 'fen-fields:',
      '4k3/8/8/8/8/8/8/4K3 w - - 0 1 x': 'fen-fields:',
      '4k3/8/8/8/8/8/8/4K3 w -  - 0 1': 'fen-fields:',
      ' 4k3/8/8/8/8/8/8/4K3 w - - 0 1': 'fen-fields:',
      '4k3/8/8/8/8/8/8/4K3 w - - 0 1 ': 'fen-fields:',
      '4k3/8/8/8/8/8/8/4K3\tw - - 0 1': 'fen-fields:',
      '': 'fen-fields:',
      // Placement.
      '4k3/8/8/8/8/8/4K3 w - - 0 1': 'fen-ranks:',
      '4k3/8/8/8/8/8/8/8/4K3 w - - 0 1': 'fen-ranks:',
      '4k3/8/8/8/8/8/8/4K2 w - - 0 1': 'fen-rank-length:',
      '4k3/8/8/8/8/8/8/4K4 w - - 0 1': 'fen-rank-length:',
      '4k3/9/8/8/8/8/8/4K3 w - - 0 1': 'fen-placement:',
      '4k3/08/8/8/8/8/8/4K3 w - - 0 1': 'fen-placement:',
      '4k3/44/8/8/8/8/8/4K3 w - - 0 1': 'fen-placement:',
      '4k3/8/8/8/8/8/8/4K2X w - - 0 1': 'fen-piece:',
      '4k3/8/8/8/8/8/8/4K2 1 w - - 0 1': 'fen-fields:',
      // Side, castling, en passant, counters.
      '4k3/8/8/8/8/8/8/4K3 W - - 0 1': 'fen-side:',
      '4k3/8/8/8/8/8/8/4K3 x - - 0 1': 'fen-side:',
      'r3k2r/8/8/8/8/8/8/R3K2R w QK - 0 1': 'fen-castling:',
      'r3k2r/8/8/8/8/8/8/R3K2R w KK - 0 1': 'fen-castling:',
      'r3k2r/8/8/8/8/8/8/R3K2R w KQkqx - 0 1': 'fen-castling:',
      '4k3/8/8/8/8/8/8/4K3 w K - 0 1': 'fen-castling:',
      '4k3/8/8/8/8/8/8/R4K2 w Q - 0 1': 'fen-castling:',
      '4k3/8/8/8/8/8/8/4K3 w - e9 0 1': 'fen-en-passant:',
      '4k3/8/8/8/8/8/8/4K3 w - e3 0 1': 'fen-en-passant:',
      '4k3/8/8/8/8/8/8/4K3 w - e6 0 1': 'fen-en-passant:',
      '4k3/8/4p3/4p3/8/8/8/4K3 w - e6 0 1': 'fen-en-passant:',
      '4k3/4p3/8/4p3/8/8/8/4K3 w - e6 0 1': 'fen-en-passant:',
      '4k3/8/8/8/8/8/8/4K3 w - - -1 1': 'fen-counter:',
      '4k3/8/8/8/8/8/8/4K3 w - - 01 1': 'fen-counter:',
      '4k3/8/8/8/8/8/8/4K3 w - - 0 0': 'fen-counter:',
      '4k3/8/8/8/8/8/8/4K3 w - - 0 100001': 'fen-counter:',
      '4k3/8/8/8/8/8/8/4K3 w - - 1.5 1': 'fen-counter:',
      '4k3/8/8/8/8/8/8/4K3 w - - 0 +1': 'fen-counter:',
      // Positions no game could reach (FIDE 3.10.3).
      '4k3/8/8/8/8/8/8/4KK2 w - - 0 1': 'fen-kings:',
      '4k3/8/8/8/8/8/8/8 w - - 0 1': 'fen-kings:',
      '4k2k/8/8/8/8/8/8/4K3 w - - 0 1': 'fen-kings:',
      'P3k3/8/8/8/8/8/8/4K3 w - - 0 1': 'fen-pawn-rank:',
      '4k3/8/8/8/8/8/8/p3K3 w - - 0 1': 'fen-pawn-rank:',
      '4k3/8/8/8/8/PPPPPPPP/P7/4K3 w - - 0 1': 'fen-piece-count:',
      '4k3/8/8/QQQQQQQQ/QQQQQQQQ/8/8/4K3 w - - 0 1': 'fen-piece-count:',
      '4k3/8/8/8/8/8/4R3/4K3 w - - 0 1': 'fen-check:',
      '4k3/8/8/8/8/8/8/4K2r b - - 0 1': 'fen-check:',
      '4k3/8/8/8/B7/8/8/4K3 w - - 0 1': 'fen-check:',
      '4k3/3P4/8/8/8/8/8/4K3 w - - 0 1': 'fen-check:',
      '4k3/8/5N2/8/8/8/8/4K3 w - - 0 1': 'fen-check:',
      '8/8/8/8/8/8/4k3/4K3 w - - 0 1': 'fen-check:',
    };

    test('the well-formed base case parses', () {
      expect(Position.fromFen(ok).toFen(), ok);
    });

    for (final MapEntry(key: fen, value: token) in cases.entries) {
      test('$token "$fen"', () {
        expect(() => Position.fromFen(fen), _refusedWith(token));
      });
    }

    test('a refused FEN yields no Position at all', () {
      Position? result;
      for (final fen in cases.keys) {
        try {
          result = Position.fromFen(fen);
        } on FormatException {
          continue;
        }
        fail('$fen returned $result instead of throwing');
      }
    });

    test('check by a blocked slider is not check', () {
      expect(
        Position.fromFen('4k3/3p4/8/8/B7/8/8/4K3 w - - 0 1').toFen(),
        '4k3/3p4/8/8/B7/8/8/4K3 w - - 0 1',
        reason: 'the bishop on a4 is blocked by the d7 pawn',
      );
      expect(
        Position.fromFen('4k3/4p3/8/8/8/8/8/4R1K1 w - - 0 1').toFen(),
        '4k3/4p3/8/8/8/8/8/4R1K1 w - - 0 1',
        reason: 'the rook on e1 is blocked by the e7 pawn',
      );
    });
  });
}
