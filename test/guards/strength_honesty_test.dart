@Tags(['guard'])
library;

// Invariant 4 (CLAUDE.md): each strength step's handicap is exactly what its
// description says, Master has none, and the same position, step and seed
// always give the same move. Reasons start `strength-honest:` (the table,
// the descriptions, and the blunders happening as described),
// `strength-master:` (Master unhandicapped) and `strength-seed:`
// (determinism, and seeds that matter).

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:honest_chess/engine/engine.dart';
import 'package:honest_chess/engine/splitmix.dart';

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
        s.noiseCp == 0 &&
            s.depthCap == null &&
            s.seesMateInOne &&
            s.blunderPercent == 0,
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

  final rate = RegExp(r'on (\d+)% of moves it blunders').firstMatch(lower);
  if (rate != null) {
    claim(
      int.parse(rate.group(1)!) == s.blunderPercent,
      '"${rate.group(0)}" but blunderPercent is ${s.blunderPercent}',
    );
  } else {
    claim(
      s.blunderPercent == 0 &&
          (lower.contains('never blunders') ||
              lower.contains('nothing held back')),
      'states no blunder rate, and does not say it never blunders, but '
      'blunderPercent is ${s.blunderPercent}',
    );
  }
  final size = lower.contains("two pawns' worth");
  claim(
    size == (s.blunderPercent > 0),
    'mentions "two pawns\' worth": $size, but blunderPercent is '
    '${s.blunderPercent}',
  );
  if (size) {
    claim(blunderCp == 200, '"two pawns\' worth" but blunderCp is $blunderCp');
  }

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
      (
        master.noiseCp,
        master.depthCap,
        master.seesMateInOne,
        master.blunderPercent,
      ),
      (0, null, true, 0),
      reason:
          'strength-master: Master has noise, a depth cap, a mate '
          'handicap or blunders',
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

  final blundering = [
    for (final step in Strength.values)
      if (step.settings.blunderPercent > 0) step,
  ];

  /// The share, in percent, of [draws] on which [blundersNow] fires.
  double share(Iterable<bool> draws) =>
      100 * draws.where((b) => b).length / draws.length;

  test('invariant 4: each step blunders on the share of moves its '
      'description states, across positions', () {
    expect(blundering, isNotEmpty);
    final offenders = <String>[];
    for (final step in blundering) {
      final percent = step.settings.blunderPercent;
      final measured = share([
        for (var i = 0; i < 20000; i++)
          blundersNow(0x5eed, splitMixFinalise(i), percent),
      ]);
      if ((measured - percent).abs() > 1) {
        offenders.add('${step.name}: $measured% for $percent%');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'strength-honest: over 20000 positions the blunder rate was not '
          'the stated one: $offenders',
    );
  });

  test('invariant 4: the game\'s seed decides which moves are blunders', () {
    final offenders = <String>[];
    for (final step in blundering) {
      final percent = step.settings.blunderPercent;
      for (final position in _positions) {
        final measured = share([
          for (var seed = 0; seed < 20000; seed++)
            blundersNow(seed, position.key, percent),
        ]);
        if ((measured - percent).abs() > 1) {
          offenders.add('${step.name} ${position.toFen()}: $measured%');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'strength-seed: over 20000 seeds in one position the blunder rate '
          'was not the stated one: $offenders',
    );
  });

  test('invariant 4: a blunder gives away at least blunderCp by the '
      "step's own search", () {
    final offenders = <String>[];
    var blunders = 0;
    for (final step in blundering) {
      final settings = step.settings;
      int seen(RootScore root) =>
          isMateScore(root.score) && !settings.seesMateInOne
          ? root.score.sign * missedMateScore
          : root.score;
      for (final position in _positions) {
        for (var seed = 0; seed < 40; seed++) {
          if (!blundersNow(seed, position.key, settings.blunderPercent)) {
            continue;
          }
          final choice = chooseMove(
            position,
            step,
            seed,
            nodeBudget: _budget,
            table: TranspositionTable(megabytes: 1),
          )!;
          final roots = choice.search.rootScores;
          final top = roots.map(seen).reduce(max);
          if (isMateScore(top) && settings.seesMateInOne) continue;
          final worse = roots.where(
            (r) =>
                seen(r) <= top - blunderCp &&
                !(settings.seesMateInOne && isMateScore(r.score)),
          );
          if (worse.isEmpty) continue;
          blunders++;
          final chosen = roots.firstWhere((r) => r.move == choice.move);
          if (seen(chosen) > top - blunderCp) {
            offenders.add(
              '${step.name} seed $seed ${position.toFen()}: '
              '${choice.move} scored ${seen(chosen)}, best $top',
            );
          }
        }
      }
    }
    expect(blunders, greaterThan(0), reason: 'no blunder was rolled');
    expect(
      offenders,
      isEmpty,
      reason:
          'strength-honest: a blunder gave away less than $blunderCp cp: '
          '$offenders',
    );
  });
}
