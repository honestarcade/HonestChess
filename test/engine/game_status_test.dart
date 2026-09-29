// Playing moves and ending the game, one FIDE clause at a time. The endings
// that must NOT happen early — twofold, 99 halfmoves, mating material,
// positions that only look repeated — are tagged `guard` with reasons
// starting `status:` or `key:` so tools/mutation_check.py can require the
// right one to fire.

import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:honest_chess/engine/engine.dart';
import 'package:honest_chess/engine/src/board.dart';
import 'package:honest_chess/engine/zobrist_keys.dart';

import '../../tools/gen_zobrist.dart' as gen;
import '../fixtures/fens.dart';

Position _fen(String fen) => Position.fromFen(fen);

/// The game from [fen] through the moves in [ucis], each of which must be
/// legal: every position, the starting one first.
List<Position> _game(String fen, List<String> ucis) {
  final history = [_fen(fen)];
  for (final uci in ucis) {
    history.add(play(history.last, Move.fromUci(history.last, uci)));
  }
  return history;
}

/// The status after the first [plies] + 1 positions of [history].
GameStatus _at(List<Position> history, int plies) =>
    status(history.sublist(0, plies + 1));

/// The index of the first position of [history] at which the game is over,
/// or null when it never is.
int? _firstEnd(List<Position> history) {
  for (var i = 0; i < history.length; i++) {
    if (_at(history, i).isOver) return i;
  }
  return null;
}

/// [plies] random legal moves from [start], stopping early at a position
/// with none. Seeded, so every run plays the same games.
List<Position> _randomGame(Position start, int plies, Random random) {
  final history = [start];
  for (var i = 0; i < plies; i++) {
    final moves = legalMoves(history.last);
    if (moves.isEmpty) break;
    history.add(play(history.last, moves[random.nextInt(moves.length)]));
  }
  return history;
}

const _knightShuffle = ['g1f3', 'g8f6', 'f3g1', 'f6g8'];
const _guard = ['guard'];

void main() {
  final starts = [for (final f in cpwPerftFens.values) _fen(f)];

  group('play', () {
    test('1.3: after every move the other side has the move', () {
      final random = Random(63);
      for (final start in starts) {
        final game = _randomGame(start, 120, random);
        for (var i = 1; i < game.length; i++) {
          expect(
            game[i].sideToMove,
            game[i - 1].sideToMove.opponent,
            reason: game[i].toFen(),
          );
        }
      }
    });

    test('3.1.1: a captured piece is gone, the en-passant victim too', () {
      final capture = _game('4k3/8/8/3p4/4P3/8/8/4K3 w - - 5 10', ['e4d5']);
      expect(capture.last.toFen(), '4k3/8/8/3P4/8/8/8/4K3 b - - 0 10');
      expect(capture.last.bitboard(Piece.blackPawn), 0);

      final ep = _game(
        'rnbqkbnr/ppp1p1pp/8/3pPp2/8/8/PPPP1PPP/RNBQKBNR w KQkq f6 0 3',
        ['e5f6'],
      );
      expect(ep.last.pieceAt(Square.parse('f5')), isNull);
      expect(ep.last.pieceAt(Square.parse('f6')), Piece.whitePawn);
      expect(ep.last.pieceAt(Square.parse('e5')), isNull);
    });

    test('castling moves the rook; rights and counters follow the move', () {
      final castled = _game('r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 7 20', [
        'e1g1',
        'a8b8',
      ]);
      expect(castled[1].toFen(), 'r3k2r/8/8/8/8/8/8/R4RK1 b kq - 8 20');
      expect(castled[2].toFen(), '1r2k2r/8/8/8/8/8/8/R4RK1 w k - 9 21');
    });

    test('3.7.3.5: a promotion takes effect at once and can give check', () {
      final queen = _game('4k3/P7/8/8/8/8/8/4K3 w - - 0 1', ['a7a8q']).last;
      expect(queen.pieceAt(Square.a8), Piece.whiteQueen);
      expect(queen.pieceAt(Square.parse('a7')), isNull);
      expect(status([queen]), const Ongoing(inCheck: true));

      final knight = _game('8/2P5/3k4/8/8/8/8/4K3 w - - 0 1', ['c7c8n']).last;
      expect(knight.pieceAt(Square.parse('c8')), Piece.whiteKnight);
      expect(inCheck(knight), isTrue);
    });

    test('a move that is not legal in the position is refused', () {
      final e2e4 = Move.fromUci(Position.initial(), 'e2e4');
      final afterE4 = play(Position.initial(), e2e4);
      expect(() => play(afterE4, e2e4), throwsArgumentError);
    });
  });

  group('position identity (9.2.3)', () {
    test('9.2.3: the incremental key always equals positionKey', () {
      final random = Random(9023);
      for (final start in [...starts, for (final f in extraFens) _fen(f)]) {
        final board = Board.fromPosition(start);
        final keys = <int>[board.key];
        for (var ply = 0; ply < 80; ply++) {
          final moves = <int>[];
          board.legalMoves(moves);
          if (moves.isEmpty) break;
          board.make(moves[random.nextInt(moves.length)]);
          final position = board.toPosition();
          expect(
            board.key,
            positionKey(position),
            reason:
                'key: the incremental key differs from positionKey '
                'after ply ${ply + 1} from ${start.toFen()}: '
                '${position.toFen()}',
          );
          keys.add(board.key);
        }
        // Unmaking every move restores every key on the way back.
        for (var i = keys.length - 1; i > 0; i--) {
          board.unmake();
          expect(
            board.key,
            keys[i - 1],
            reason: 'key: unmake, ${start.toFen()}',
          );
        }
      }
    }, tags: _guard);

    test('9.2.3: side, placement, castling and legal en passant decide it; '
        'the counters do not', () {
      void same(String a, String b) {
        final pa = _fen(a), pb = _fen(b);
        expect(pa.key, pb.key, reason: '$a / $b');
        expect(isSamePosition(pa, pb), isTrue, reason: '$a / $b');
      }

      void different(String a, String b) {
        final pa = _fen(a), pb = _fen(b);
        expect(pa.key, isNot(pb.key), reason: '$a / $b');
        expect(isSamePosition(pa, pb), isFalse, reason: '$a / $b');
      }

      same(
        '4k3/8/8/8/8/8/8/4K2R w K - 0 1',
        '4k3/8/8/8/8/8/8/4K2R w K - 30 70',
      );
      different(
        '4k3/8/8/8/8/8/8/4K2R w K - 0 1',
        '4k3/8/8/8/8/8/8/4K2R b K - 0 1',
      );
      different(
        '4k3/8/8/8/8/8/8/4K2R w K - 0 1',
        '4k3/8/8/8/8/8/8/5K1R w - - 0 1',
      );
      // 9.2.3.2: only the castling right differs.
      different(
        '4k3/8/8/8/8/8/8/4K2R w K - 0 1',
        '4k3/8/8/8/8/8/8/4K2R w - - 0 1',
      );
      // 9.2.3.1: a legal en-passant capture makes a difference…
      different(
        '4k3/8/8/1Pp5/8/8/8/4K3 w - c6 0 2',
        '4k3/8/8/1Pp5/8/8/8/4K3 w - - 0 2',
      );
      // …an en-passant square nothing can capture on does not…
      same(
        '4k3/8/8/2p5/8/8/8/4K3 w - c6 0 2',
        '4k3/8/8/2p5/8/8/8/4K3 w - - 0 2',
      );
      // …nor does one only a pinned pawn could use.
      same(
        '4k3/8/8/KPp4r/8/8/8/8 w - c6 0 2',
        '4k3/8/8/KPp4r/8/8/8/8 w - - 0 2',
      );
      expect(legalEnPassantFile(_fen('4k3/8/8/1Pp5/8/8/8/4K3 w - c6 0 2')), 2);
    });

    test('the Zobrist keys are exactly what tools/gen_zobrist.dart makes', () {
      expect(
        gen.hex64(gen.splitMix64(0, 1).single),
        '0xe220a8397b1dcdaf',
        reason: 'SplitMix64 from seed 0 starts with the reference output',
      );
      final committed = File('lib/engine/zobrist_keys.dart').readAsStringSync();
      expect(committed, gen.zobristSource());
      expect(zobristKeys, hasLength(gen.keyCount));
      expect(zobristKeys.toSet(), hasLength(gen.keyCount));
    });
  });

  group('checkmate (1.4, 5.1.1)', () {
    test('1.4 / 1.4.1 / 5.1.1: in check with no legal move is checkmate, and '
        'the game ends at once', () {
      final fools = _game(Position.initialFen, [
        'f2f3',
        'e7e5',
        'g2g4',
        'd8h4',
      ]);
      expect(_firstEnd(fools), 4);
      expect(status(fools), const Win(Colour.black, GameEndReason.checkmate));
      expect(_at(fools, 3), const Ongoing(inCheck: false));
    });

    test('1.4.2: the checkmated side loses; the other wins', () {
      final scholars = _game(Position.initialFen, [
        'e2e4', 'e7e5', 'f1c4', 'b8c6', 'd1h5', 'g8f6', 'h5f7', //
      ]);
      expect(
        status(scholars),
        const Win(Colour.white, GameEndReason.checkmate),
      );
      expect(
        status(scholars),
        isNot(const Win(Colour.black, GameEndReason.checkmate)),
      );
    });

    test('a check that can be answered is not the end', () {
      final check = _game(Position.initialFen, ['e2e4', 'f7f6', 'd1h5']);
      expect(status(check), const Ongoing(inCheck: true));
    });
  });

  group('draws', () {
    test('5.2.1: no legal move and not in check is stalemate, a draw', () {
      expect(
        status([_fen('7k/5Q2/6K1/8/8/8/8/8 b - - 0 1')]),
        const Draw(GameEndReason.stalemate),
      );
    });

    // Placement and side only; each one is also checked against canMate.
    const insufficient = {
      'K v K': '4k3/8/8/8/8/8/8/4K3 w - - 0 1',
      'K+B v K': '4k3/8/8/8/8/8/8/2B1K3 w - - 0 1',
      'K v K+B': '4k3/8/8/8/8/8/8/4K1b1 b - - 0 1',
      'K+N v K': '4k3/8/8/8/8/8/8/1N2K3 w - - 0 1',
      'K v K+N': '1n2k3/8/8/8/8/8/8/4K3 w - - 0 1',
      'K+B v K+B, same colour': '4kb2/8/8/8/8/8/8/2B1K3 w - - 0 1',
      'K+B+B v K, same colour': '4k3/8/8/8/8/4B3/8/2B1K3 w - - 0 1',
      'K+B+B v K+B+B, one colour': '3bkb2/8/8/8/8/4B3/8/2B1K3 b - - 0 1',
    };
    const sufficient = {
      'K+N+N v K': '4k3/8/8/8/8/8/8/1N2KN2 w - - 0 1',
      'K+B v K+B, opposite colours': '2b1k3/8/8/8/8/8/8/2B1K3 w - - 0 1',
      'K+B+B v K, both colours': '4k3/8/8/8/8/8/8/2B1KB2 w - - 0 1',
      'K+B+N v K': '4k3/8/8/8/8/8/8/1NB1K3 w - - 0 1',
      'K+N v K+N': '1n2k3/8/8/8/8/8/8/1N2K3 w - - 0 1',
      'K+B v K+N': '1n2k3/8/8/8/8/8/8/2B1K3 w - - 0 1',
      'K+N v K+P': '4k3/7p/8/8/8/8/8/1N2K3 w - - 0 1',
      'K+P v K': '4k3/8/8/8/8/8/4P3/4K3 w - - 0 1',
      'K+R v K': '4k3/8/8/8/8/8/8/R3K3 w - - 0 1',
      'K+Q v K': '4k3/8/8/8/8/8/8/3QK3 w - - 0 1',
      'K v K+P': '4k3/4p3/8/8/8/8/8/4K3 w - - 0 1',
    };

    test('1.5 / 5.2.2: insufficient material, as scoped, is drawn at once', () {
      for (final MapEntry(key: name, value: fen) in insufficient.entries) {
        final p = _fen(fen);
        expect(
          status([p]),
          const Draw(GameEndReason.insufficientMaterial),
          reason: name,
        );
        expect(
          canMate(p, Colour.white) || canMate(p, Colour.black),
          isFalse,
          reason: name,
        );
      }
    });

    test('1.5 / 5.2.2: anything else with a possible mate plays on', () {
      for (final MapEntry(key: name, value: fen) in sufficient.entries) {
        final p = _fen(fen);
        expect(
          status([p]),
          isA<Ongoing>(),
          reason: 'status: $name was declared insufficient material',
        );
        expect(
          canMate(p, Colour.white) || canMate(p, Colour.black),
          isTrue,
          reason: name,
        );
      }
    }, tags: _guard);

    test('canMate: a lone minor mates only with an opposing blocker', () {
      bool white(String fen) => canMate(_fen(fen), Colour.white);
      expect(white('4k3/8/8/8/8/8/8/1N2K3 w - - 0 1'), isFalse);
      expect(white('3qk3/8/8/8/8/8/8/1N2K3 w - - 0 1'), isTrue);
      expect(white('4k3/8/8/8/8/8/8/2B1K3 w - - 0 1'), isFalse);
      expect(white('3rk3/8/8/8/8/8/8/2B1K3 w - - 0 1'), isTrue);
      expect(white('4k3/8/8/8/8/8/8/4K3 w - - 0 1'), isFalse);
      expect(white('4k3/8/8/8/8/8/8/Q3K3 w - - 0 1'), isTrue);
    });

    test('9.2 / 9.2.2: the third occurrence ends the game at the moment it '
        'appears', () {
      final shuffles = _game(Position.initialFen, [
        ..._knightShuffle,
        ..._knightShuffle,
        ..._knightShuffle,
      ]);
      expect(
        _firstEnd(shuffles),
        8,
        reason:
            'status: a twofold repetition ended the game '
            '(or the third occurrence did not)',
      );
      expect(_at(shuffles, 8), const Draw(GameEndReason.threefoldRepetition));
    }, tags: _guard);

    test('9.2.3.2: a repetition that differs by a castling right is not the '
        'same position', () {
      // Each rook steps off and back: the placement returns, the kingside
      // rights do not. Ignoring the rights would draw at ply 8.
      final rooks = _game('r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1', [
        for (var i = 0; i < 3; i++) ...['h1g1', 'h8g8', 'g1h1', 'g8h8'],
      ]);
      expect(
        _firstEnd(rooks),
        10,
        reason:
            'status: positions differing in castling rights counted '
            'as one',
      );
    }, tags: _guard);

    test('9.2.3.1: a repetition that differs by a legal en-passant capture '
        'is not the same position', () {
      // After d7d5, exd6 is legal; the same placement later is not the same
      // position. Counting it would draw at ply 9.
      final legal = _game('4k1n1/3p4/8/4P3/8/8/8/4K1N1 b - - 0 1', [
        'd7d5',
        for (var i = 0; i < 3; i++) ..._knightShuffle,
      ]);
      expect(
        _firstEnd(legal),
        10,
        reason:
            'status: a legal en-passant capture did not split a '
            'repetition',
      );
    }, tags: _guard);

    test('9.2.3.1: an en-passant square no legal capture can use does not '
        'split a repetition', () {
      // After c7c5 only the pinned b5 pawn could take en passant, which
      // would expose its king to the rook: the position after c7c5 is the
      // first occurrence of the one reached again at plies 5 and 9.
      final pinned = _game('4k1n1/2p5/8/KP5r/8/8/8/6N1 b - - 0 1', [
        'c7c5',
        for (var i = 0; i < 2; i++) ..._knightShuffle,
      ]);
      expect(
        _firstEnd(pinned),
        9,
        reason:
            'status: an en-passant square no legal capture can use '
            'split a repetition',
      );
      expect(status(pinned), const Draw(GameEndReason.threefoldRepetition));
    }, tags: _guard);

    test('9.3 / 9.3.2: 100 halfmoves without a pawn move or capture draw; '
        '99 do not', () {
      // Quiet piece moves that never repeat a position, chosen at random
      // from a seeded generator.
      final random = Random(93);
      final history = [_fen('r3k2r/8/8/8/8/8/8/R3K2R w - - 0 1')];
      while (history.length <= 100) {
        final moves = legalMoves(
          history.last,
        ).where((m) => !m.isCapture).toList()..shuffle(random);
        final keys = {for (final p in history) p.key};
        final next = moves
            .map((m) => play(history.last, m))
            .firstWhere(
              (p) => !keys.contains(p.key) && legalMoves(p).isNotEmpty,
            );
        history.add(next);
      }
      expect(history.last.halfmoveClock, 100);
      expect(
        _firstEnd(history.sublist(0, 100)),
        isNull,
        reason: 'status: the fifty-move draw came before 100 halfmoves',
      );
      expect(status(history), const Draw(GameEndReason.fiftyMoves));
    }, tags: _guard);

    test(
      '9.3: a loaded position at 100 halfmoves or more is drawn at once',
      () {
        for (final clock in [100, 101, 149, 150]) {
          expect(
            status([_fen('4k3/8/8/8/8/8/8/R3K3 w - - $clock 90')]),
            const Draw(GameEndReason.fiftyMoves),
            reason: '$clock',
          );
        }
      },
    );

    test('9.6 / 9.6.1: fivefold repetition is never reached — the third '
        'occurrence already ended the game', () {
      final history = [Position.initial()];
      var ply = 0;
      while (!status(history).isOver) {
        final uci = _knightShuffle[ply++ % 4];
        history.add(play(history.last, Move.fromUci(history.last, uci)));
      }
      final occurrences = history
          .where((p) => isSamePosition(p, history.last))
          .length;
      expect(occurrences, 3);
    });

    test('9.6 / 9.6.2: a mate on the move completing the fifty-move count is '
        'a mate, not a draw', () {
      final mate = _game('6k1/5ppp/8/8/8/8/8/R5K1 w - - 99 80', ['a1a8']);
      expect(mate.last.halfmoveClock, 100);
      expect(
        status(mate),
        const Win(Colour.white, GameEndReason.checkmate),
        reason: 'status: a mate on the hundredth halfmove was not a mate',
      );
      // The same count without the mate is the fifty-move draw, not the
      // seventy-five-move rule later.
      final quiet = _game('6k1/5ppp/8/8/8/8/8/R5K1 w - - 99 80', ['a1a7']);
      expect(status(quiet), const Draw(GameEndReason.fiftyMoves));
    }, tags: _guard);

    test('an empty history is refused', () {
      expect(() => status(const []), throwsArgumentError);
    });
  });
}
