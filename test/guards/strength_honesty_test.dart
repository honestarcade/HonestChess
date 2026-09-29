@Tags(['guard'])
library;

// Invariant 4 (CLAUDE.md): each strength step's handicap is exactly what its
// description says, Master has none, and the same position, step and seed
// always give the same move. Reasons start `strength-honest:` (the table and
// the descriptions), `strength-master:` (Master unhandicapped) and
// `strength-seed:` (determinism, and seeds that matter).

import 'package:flutter_test/flutter_test.dart';
import 'package:honest_chess/engine/engine.dart';

import '../fixtures/fens.dart';

/// Small budgets keep the guard quick; the choice logic is the same at any
/// budget.
const _budget = 20000;

const _words = {'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5};

final _positions = [
  for (final fen in cpwPerftFens.values) Position.fromFen(fen),
  Position.fromFen(extraFens[6]),
];

Move _choose(
  Position position,
  Strength step,
  int seed, {
  TranspositionTable? table,
}) => chooseMove(
  position,
  step,
  seed,
  nodeBudget: _budget,
  table: table ?? TranspositionTable(megabytes: 1),
)!.move;

/// The claims [description] makes, checked against [settings]; each
/// disagreement is returned as a sentence.
List<String> _disagreements(String name, String text, StrengthSettings s) {
  final out = <String>[];
  void claim(bool agrees, String what) {
    if (!agrees) out.add('$name: $what');
  }

  final lower = text.toLowerCase();
  final depth = RegExp(r'looks (\w+) moves? ahead').firstMatch(lower);
  if (depth != null) {
    claim(
      _words[depth.group(1)] == s.depthCap,
      '"${depth.group(0)}" but depthCap is ${s.depthCap}',
    );
  } else {
    claim(
      lower.contains('thinks deeply') && s.depthCap == null,
      'no depth claimed ("thinks deeply") but depthCap is ${s.depthCap}',
    );
  }

  final looseness = [
    if (lower.contains('a little loosely'))
      ('a little loosely', s.noiseCp >= 50 && s.noiseCp < 150)
    else if (lower.contains('loosely'))
      ('loosely', s.noiseCp >= 150),
    if (lower.contains('carefully'))
      ('carefully', s.noiseCp >= 1 && s.noiseCp < 50),
    if (lower.contains('no looseness')) ('no looseness', s.noiseCp == 0),
    if (lower.contains('nothing held back'))
      (
        'nothing held back',
        s.noiseCp == 0 && s.depthCap == null && s.seesMateInOne,
      ),
  ];
  claim(looseness.isNotEmpty, 'says nothing about how loosely it chooses');
  for (final (words, agrees) in looseness) {
    claim(agrees, '"$words" but noiseCp is ${s.noiseCp}');
  }

  claim(
    lower.contains('mate in one') == !s.seesMateInOne,
    'mentions missing mate in one: ${lower.contains('mate in one')}, '
    'but seesMateInOne is ${s.seesMateInOne}',
  );

  final time = RegExp(r'about (\w+) seconds').firstMatch(lower);
  if (time != null) {
    claim(
      _words[time.group(1)] == s.thinkSeconds,
      '"${time.group(0)}" but thinkSeconds is ${s.thinkSeconds}',
    );
  }
  claim(
    s.nodeBudget == calibratedNodeBudget(s.thinkSeconds),
    'nodeBudget ${s.nodeBudget} is not the calibration for '
    '${s.thinkSeconds} s (${calibratedNodeBudget(s.thinkSeconds)})',
  );
  return out;
}

void main() {
  test('invariant 4: every step description agrees with its settings', () {
    final offenders = [
      for (final step in Strength.values)
        ..._disagreements(step.name, step.description, step.settings),
    ];
    expect(
      offenders,
      isEmpty,
      reason:
          'strength-honest: ${offenders.length} disagreement(s): '
          '$offenders',
    );
  });

  test('invariant 4: Master has no handicap — its move is the plain '
      "search's, whatever the seed", () {
    final master = Strength.master.settings;
    expect(
      (master.noiseCp, master.depthCap, master.seesMateInOne),
      (0, null, true),
      reason:
          'strength-master: Master has noise, a depth cap or a mate '
          'handicap',
    );
    final offenders = <String>[];
    for (final position in _positions) {
      final plain = search(
        position,
        limits: const SearchLimits(nodes: _budget, exactRootScores: false),
        table: TranspositionTable(megabytes: 1),
      );
      for (final seed in [0, 1, -1, 0x123456789abcdef]) {
        final chosen = _choose(position, Strength.master, seed);
        if (chosen != (plain as Found).move) {
          offenders.add(
            '${position.toFen()} seed $seed: $chosen, not '
            '${plain.move}',
          );
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'strength-master: Master chose other than its search: '
          '$offenders',
    );
  });

  test('invariant 4: the same position, step and seed give the same move, '
      'even after the table held another search', () {
    final offenders = <String>[];
    final used = TranspositionTable(megabytes: 1);
    for (final step in Strength.values) {
      for (final position in _positions) {
        const seed = 0x5eed;
        final first = _choose(position, step, seed);
        // Fill the table with a different search first.
        search(
          Position.initial(),
          limits: const SearchLimits(nodes: 5000),
          table: used,
        );
        final again = _choose(position, step, seed, table: used);
        if (first != again) {
          offenders.add('${step.name} ${position.toFen()}: $first then $again');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'strength-seed: the same position, step and seed gave '
          'different moves: $offenders',
    );
  });

  test('invariant 4: at each noisy step a different seed can give a '
      'different move', () {
    final noisy = [
      for (final step in Strength.values)
        if (step.settings.noiseCp > 0) step,
    ];
    expect(noisy, isNotEmpty);
    final silent = <String>[];
    for (final step in noisy) {
      bool varies(Position position) {
        final first = _choose(position, step, 0);
        for (var seed = 1; seed < 16; seed++) {
          if (_choose(position, step, seed) != first) return true;
        }
        return false;
      }

      if (!_positions.any(varies)) silent.add(step.name);
    }
    expect(
      silent,
      isEmpty,
      reason: 'strength-seed: the seed never changed the move at $silent',
    );
  });
}
