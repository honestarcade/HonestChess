@Tags(['weekly'])
@Timeout(Duration(minutes: 110))
library;

// The strength ladder (#69): each step of the dial must beat the one below
// it, over a fixed-seed match from the committed openings, at each step's
// own node budget. Too slow for the pull-request gate; the weekly job runs
// it every Sunday.

import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:honest_chess/engine/engine.dart';

import '../fixtures/openings.dart';
import 'strength_ladder.dart';

/// Games per pair: every opening once with each colour.
const ladderGames = 40;

/// The least the stronger step must score in a pair, in points: 65%.
final int ladderBar = (0.65 * ladderGames).ceil();

/// Games of one pair run side by side, each in its own isolate; every game
/// is independent and seeded, so the results do not depend on how many.
final int _workers = max(1, min(4, Platform.numberOfProcessors - 1));

Future<List<LadderResult>> _playPair(Strength stronger, Strength weaker) async {
  final results = List<LadderResult?>.filled(ladderGames, null);
  var next = 0;
  Future<void> worker() async {
    while (next < ladderGames) {
      final index = next++;
      results[index] = await Isolate.run(
        () => playLadderGame(
          stronger,
          weaker,
          index,
          table: TranspositionTable(),
        ),
      );
    }
  }

  await Future.wait([for (var i = 0; i < _workers; i++) worker()]);
  return [for (final r in results) r!];
}

String _points(double points) =>
    points == points.truncate() ? '${points.toInt()}' : '${points.truncate()}½';

void main() {
  final rows = <String>[];

  tearDownAll(() {
    final table = [
      '### Strength ladder ($ladderGames games per pair, bar $ladderBar)',
      '',
      '| Pair | Stronger scored | Wins | Draws | Losses | Seconds |',
      '| --- | --- | --- | --- | --- | --- |',
      ...rows,
      '',
    ].join('\n');
    stdout.writeln(table);
    final summary = Platform.environment['GITHUB_STEP_SUMMARY'];
    if (summary != null && summary.isNotEmpty) {
      File(summary).writeAsStringSync('$table\n', mode: FileMode.append);
    }
  });

  test(
    'the openings are ${ladderGames ~/ 2}, each played with both colours',
    () {
      expect(ladderOpenings, hasLength(ladderGames ~/ 2));
    },
  );

  for (var i = 1; i < Strength.values.length; i++) {
    final weaker = Strength.values[i - 1];
    final stronger = Strength.values[i];
    test('${stronger.name} scores at least $ladderBar/$ladderGames against '
        '${weaker.name}', () async {
      final stopwatch = Stopwatch()..start();
      final results = await _playPair(stronger, weaker);
      final points = results.fold(0.0, (sum, r) => sum + r.strongerScore);
      final wins = results.where((r) => r.strongerScore == 1).length;
      final losses = results.where((r) => r.strongerScore == 0).length;
      final draws = ladderGames - wins - losses;
      rows.add(
        '| ${stronger.name}–${weaker.name} | ${_points(points)}/$ladderGames '
        '| $wins | $draws | $losses | ${stopwatch.elapsed.inSeconds} |',
      );
      stdout.writeln(rows.last);
      expect(
        points,
        greaterThanOrEqualTo(ladderBar),
        reason:
            'strength-ladder: ${stronger.name} scored ${_points(points)} of '
            '$ladderGames against ${weaker.name}; games: '
            '${[for (final (i, r) in results.indexed) '$i ${r.strongerScore} ${r.ending}'].join(', ')}',
      );
    }, timeout: const Timeout(Duration(minutes: 30)));
  }
}
