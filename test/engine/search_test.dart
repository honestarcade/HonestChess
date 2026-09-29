// The computer's search: it finds mates and wins material in known puzzles,
// gives the same answer every run, stops when told, and — the invariant 3
// guard, reasons starting `search-legal:` — only ever returns a legal move.
// A second guard (`search-pure:`) keeps clocks and unseeded randomness out
// of the search's source, which invariant 4's determinism rests on.

import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:honest_chess/engine/engine.dart';

import '../fixtures/fens.dart';
import '../fixtures/puzzles.dart';

Position _fen(String fen) => Position.fromFen(fen);

/// A search with a fresh, small table, so runs do not share state.
SearchResult _search(
  Position position, {
  SearchLimits limits = const SearchLimits(nodes: 100000),
  List<int> history = const [],
  ShouldStop? shouldStop,
}) => search(
  position,
  limits: limits,
  history: history,
  shouldStop: shouldStop,
  table: TranspositionTable(megabytes: 1),
);

Found _found(SearchResult result) {
  expect(result, isA<Found>());
  return result as Found;
}

/// [position] with the board turned round and the colours swapped: the same
/// position for the other side.
String _mirror(Position position) {
  final fields = position.toFen().split(' ');
  String swapCase(String s) => String.fromCharCodes([
    for (final c in s.codeUnits)
      c >= 0x61 && c <= 0x7a
          ? c - 32
          : c >= 0x41 && c <= 0x5a
          ? c + 32
          : c,
  ]);
  final board = fields[0].split('/').reversed.map(swapCase).join('/');
  final side = fields[1] == 'w' ? 'b' : 'w';
  final castling = fields[2] == '-'
      ? '-'
      : ([...swapCase(fields[2]).split('')]
              ..sort((a, b) => 'KQkq'.indexOf(a).compareTo('KQkq'.indexOf(b))))
            .join();
  final ep = fields[3] == '-'
      ? '-'
      : '${fields[3][0]}${fields[3][1] == '3' ? '6' : '3'}';
  return '$board $side $castling $ep ${fields[4]} ${fields[5]}';
}

/// Positions from seeded random playouts, each with the keys of the game's
/// earlier positions, until [count] positions with a legal move are found.
List<(Position, List<int>)> _playoutPositions(int count) {
  final out = <(Position, List<int>)>[];
  for (var seed = 0; out.length < count; seed++) {
    final rng = Random(seed);
    var position = rng.nextInt(4) == 0
        ? _fen(allFens[rng.nextInt(allFens.length)])
        : Position.initial();
    final keys = <int>[];
    for (var ply = 0; ply < 120 && out.length < count; ply++) {
      final moves = legalMoves(position);
      if (moves.isEmpty) break;
      out.add((position, List.of(keys)));
      keys.add(position.key);
      position = play(position, moves[rng.nextInt(moves.length)]);
    }
  }
  return out;
}

const _guard = ['guard'];

void main() {
  group('mates', () {
    test('finds every mate in one, scored as mate at ply 1', () {
      expect(mateInOne, isNotEmpty);
      for (final p in mateInOne) {
        final found = _found(_search(_fen(p.fen)));
        expect(found.move.toUci(), p.move, reason: 'puzzle ${p.id}');
        expect(found.score, mateScore - 1, reason: 'puzzle ${p.id}');
      }
    });

    test('finds every mate in two, scored as mate at ply 3', () {
      expect(mateInTwo, isNotEmpty);
      for (final p in mateInTwo) {
        final found = _found(_search(_fen(p.fen)));
        expect(found.move.toUci(), p.move, reason: 'puzzle ${p.id}');
        expect(found.score, mateScore - 3, reason: 'puzzle ${p.id}');
      }
    });

    test('the side being mated sees its mate coming', () {
      // Black to move after 1.f3 e5 2.g4: 2...Qh4# is mate for Black, so
      // White, a move earlier, must see a mate in one against it on g4.
      final beforeBlunder = _fen(
        'rnbqkbnr/pppp1ppp/8/4p3/8/5P2/PPPPP1PP/RNBQKBNR w KQkq - 0 2',
      );
      final found = _found(
        _search(beforeBlunder, limits: const SearchLimits(depth: 3)),
      );
      final g4 = found.rootScores.singleWhere((r) => r.move.toUci() == 'g2g4');
      expect(g4.score, -(mateScore - 2));
      expect(found.move.toUci(), isNot('g2g4'));
    });
  });

  test('tactics: at least 20 forks, pins and skewers, each solved exactly', () {
    expect(tactics.length, greaterThanOrEqualTo(20));
    expect({for (final t in tactics) t.theme}, {'fork', 'pin', 'skewer'});
    final missed = [
      for (final t in tactics)
        if (_found(_search(_fen(t.fen))).move.toUci() != t.move)
          '${t.id} (${t.theme})',
    ];
    expect(missed, isEmpty, reason: 'puzzles missed at 100,000 nodes');
  });

  group('determinism', () {
    final positions = [
      for (final f in cpwPerftFens.values) _fen(f),
      _fen(tactics.first.fen),
    ];

    for (final exact in [true, false]) {
      test('two runs agree on everything (exactRootScores: $exact)', () {
        final limits = SearchLimits(nodes: 30000, exactRootScores: exact);
        for (final p in positions) {
          final a = _found(_search(p, limits: limits));
          final b = _found(_search(p, limits: limits));
          final fen = p.toFen();
          expect(b.move, a.move, reason: fen);
          expect(b.score, a.score, reason: fen);
          expect(b.depth, a.depth, reason: fen);
          expect(b.nodes, a.nodes, reason: fen);
          expect(b.pv, a.pv, reason: fen);
          expect(
            [for (final r in b.rootScores) '$r'],
            [for (final r in a.rootScores) '$r'],
            reason: fen,
          );
        }
      });
    }

    test('exact root scores rank every move; the best is the top score, '
        'first in generation order on a tie', () {
      for (final p in positions) {
        final found = _found(_search(p, limits: const SearchLimits(depth: 3)));
        final generated = legalMoves(p);
        expect([for (final r in found.rootScores) r.move], generated);
        expect(found.rootScores.every((r) => r.exact), isTrue);
        final top = found.rootScores.map((r) => r.score).reduce(max);
        expect(found.score, top);
        expect(
          found.move,
          found.rootScores.firstWhere((r) => r.score == top).move,
        );
      }
    });

    test('without exact root scores, the chosen move is exact and every '
        'other score is a bound below it', () {
      for (final p in positions) {
        final fast = _found(
          _search(
            p,
            limits: const SearchLimits(depth: 4, exactRootScores: false),
          ),
        );
        final chosen = fast.rootScores.singleWhere((r) => r.move == fast.move);
        expect(chosen.exact, isTrue, reason: p.toFen());
        expect(chosen.score, fast.score, reason: p.toFen());
        for (final r in fast.rootScores.where((r) => !r.exact)) {
          expect(r.score, lessThanOrEqualTo(fast.score), reason: '$r');
        }
      }
    });
  });

  group('limits and stopping', () {
    final middlegame = _fen(cpwPerftFens['kiwipete']!);

    test('a node limit is kept once the first iteration is done', () {
      final found = _found(
        _search(middlegame, limits: const SearchLimits(nodes: 200000)),
      );
      expect(found.nodes, lessThanOrEqualTo(200000));
      expect(found.depth, greaterThan(1));
    });

    test('the first iteration always finishes', () {
      final found = _found(
        _search(middlegame, limits: const SearchLimits(nodes: 1)),
      );
      expect(found.depth, 1);
      expect(legalMoves(middlegame), contains(found.move));
    });

    test('a depth limit is kept', () {
      final found = _found(
        _search(middlegame, limits: const SearchLimits(depth: 3)),
      );
      expect(found.depth, 3);
    });

    test('a cancelled search stops within one check interval and returns '
        'no move', () {
      for (final after in [1, 3, 10]) {
        var calls = 0;
        final result = _search(
          middlegame,
          limits: const SearchLimits(),
          shouldStop: () => ++calls >= after ? StopReason.cancel : null,
        );
        expect(result, isA<Cancelled>(), reason: 'cancel at call $after');
        expect(result, isNot(isA<Found>()));
        expect(calls, after, reason: 'no check after the cancel');
        expect(
          (result as Cancelled).nodes,
          lessThanOrEqualTo(after * stopCheckInterval),
        );
      }
    });

    test('a deadline returns the last finished iteration, exactly as a '
        'search to that depth finds it', () {
      var calls = 0;
      final timed = _found(
        _search(
          middlegame,
          limits: const SearchLimits(),
          shouldStop: () => ++calls >= 40 ? StopReason.deadline : null,
        ),
      );
      expect(timed.nodes, lessThanOrEqualTo(40 * stopCheckInterval));
      final byDepth = _found(
        _search(middlegame, limits: SearchLimits(depth: timed.depth)),
      );
      expect(timed.move, byDepth.move);
      expect(timed.score, byDepth.score);
      expect(timed.pv, byDepth.pv);
    });

    test('a deadline in the first iteration still gives a move', () {
      final found = _found(
        _search(
          middlegame,
          limits: const SearchLimits(),
          shouldStop: () => StopReason.deadline,
        ),
      );
      expect(found.depth, 1);
    });

    test('no legal move is an ArgumentError; one legal move comes back at '
        'once', () {
      const mated =
          'rnb1kbnr/pppp1ppp/8/4p3/6Pq/5P2/PPPPP2P/RNBQKBNR w KQkq - 1 3';
      const stalemated = '7k/5Q2/6K1/8/8/8/8/8 b - - 0 1';
      for (final fen in [mated, stalemated]) {
        expect(() => _search(_fen(fen)), throwsArgumentError, reason: fen);
      }
      final forced = _fen('7k/8/5QK1/8/8/8/8/8 b - - 0 1');
      expect(legalMoves(forced), hasLength(1));
      final found = _found(_search(forced));
      expect(found.move, legalMoves(forced).single);
      expect(found.depth, 1);
    });
  });

  group('draws inside the search', () {
    test('a move into a position seen twice before scores 0; seen once, '
        'it does not', () {
      // White is a queen up; Qb1-a2 is an ordinary move unless its position
      // has already occurred twice in the game.
      final position = _fen('7k/8/8/8/8/8/6K1/1Q6 w - - 10 60');
      final qa2 = legalMoves(position).singleWhere((m) => m.toUci() == 'b1a2');
      final after = play(position, qa2).key;
      int scoreOf(List<int> history) => _found(
        _search(
          position,
          limits: const SearchLimits(depth: 3),
          history: history,
        ),
      ).rootScores.singleWhere((r) => r.move == qa2).score;
      // The search compares a node with every second key before it: from
      // the first ply, history slots 3 and 1 here.
      expect(scoreOf([0, after, 0, after]), 0);
      expect(scoreOf([0, 0, 0, after]), greaterThan(500));
    });

    test('the fifty-move rule is scored as a draw, but a mate on the '
        'hundredth halfmove is still a mate', () {
      // Rb8 mates at once; Rc7 is quiet and reaches halfmove 100.
      final position = _fen('6k1/1R6/6K1/8/8/8/8/8 w - - 99 120');
      final found = _found(
        _search(position, limits: const SearchLimits(depth: 3)),
      );
      expect(found.move.toUci(), 'b7b8');
      expect(found.score, mateScore - 1);
      final quiet = found.rootScores.singleWhere(
        (r) => r.move.toUci() == 'b7c7',
      );
      expect(quiet.score, 0);
    });

    test('insufficient material scores 0, not the extra knight', () {
      final found = _found(
        _search(
          _fen('8/8/8/4k3/8/8/3K4/4N3 w - - 0 1'),
          limits: const SearchLimits(depth: 4),
        ),
      );
      expect(found.rootScores.every((r) => r.score == 0), isTrue);
    });

    test('a stalemating move scores 0, however far ahead', () {
      final position = _fen('7k/8/8/8/8/8/8/K4Q2 w - - 0 1');
      final found = _found(
        _search(position, limits: const SearchLimits(depth: 3)),
      );
      final stalemate = found.rootScores.singleWhere(
        (r) => r.move.toUci() == 'f1f7',
      );
      expect(stalemate.score, 0);
      expect(found.score, greaterThan(500));
    });
  });

  group('evaluation', () {
    test('is the same for a position and its colour-swapped mirror', () {
      for (final fen in allFens) {
        final p = _fen(fen);
        expect(evaluate(_fen(_mirror(p))), evaluate(p), reason: fen);
      }
    });

    test('scores the start near level, and an extra queen well ahead', () {
      expect(evaluate(Position.initial()).abs(), lessThan(50));
      final queenUp = _fen(
        'rnb1kbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
      );
      expect(evaluate(queenUp), greaterThan(800));
      expect(evaluate(_fen(_mirror(queenUp))), greaterThan(800));
    });
  });

  group('transposition table', () {
    test('stores and returns an entry; another key in the bucket misses', () {
      final table = TranspositionTable(megabytes: 1);
      const key = 0x123456789abcdef;
      table.store(key, 0x1234, -250, 7, Bound.lower, 3);
      final entry = table.probe(key);
      expect(TranspositionTable.entryMove(entry), 0x1234);
      expect(TranspositionTable.entryScore(entry, 3), -250);
      expect(TranspositionTable.entryDepth(entry), 7);
      expect(TranspositionTable.entryBound(entry), Bound.lower);
      expect(table.probe(key ^ (1 << 62)), 0);
    });

    test(
      'mate scores are stored from the node and read back from the root',
      () {
        final table = TranspositionTable(megabytes: 1);
        table.store(42, 0, mateScore - 5, 3, Bound.exact, 2);
        // Mate in 3 plies from this node: at ply 4 it is mate at ply 7.
        expect(
          TranspositionTable.entryScore(table.probe(42), 4),
          mateScore - 7,
        );
      },
    );
  });

  test('invariant 3: over 1,000 seeded playout positions, the move is '
      'always legal', () {
    final positions = _playoutPositions(1000);
    expect(positions, hasLength(1000));
    final offenders = <String>[];
    for (final (position, history) in positions) {
      try {
        final found = _found(
          _search(
            position,
            limits: const SearchLimits(nodes: 2000),
            history: history,
          ),
        );
        if (!legalMoves(position).contains(found.move)) {
          offenders.add('${position.toFen()}: ${found.move}');
        }
      } on Object catch (e) {
        offenders.add('${position.toFen()}: threw $e');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'search-legal: ${offenders.length} positions got an illegal move '
          'or none; first: ${offenders.take(3).join('; ')}',
    );
  }, tags: [..._guard, 'slow']);

  test('invariant 4: the search files read no clock and draw no unseeded '
      'random number', () {
    const files = [
      'lib/engine/search.dart',
      'lib/engine/evaluate.dart',
      'lib/engine/transposition.dart',
      'lib/engine/src/board.dart',
      'lib/engine/src/tables.dart',
    ];
    final comment = RegExp(r'//[^\n]*|/\*[\s\S]*?\*/');
    final forbidden = RegExp(
      r'\bDateTime\b|\bStopwatch\b|\bRandom\s*\(\s*\)|\bRandom\.secure\b',
    );
    final offenders = [
      for (final path in files)
        for (final m in forbidden.allMatches(
          File(path).readAsStringSync().replaceAll(comment, ''),
        ))
          '$path: ${m.group(0)}',
    ];
    expect(
      offenders,
      isEmpty,
      reason: 'search-pure: ${offenders.length} offender(s): $offenders',
    );
  }, tags: _guard);
}
