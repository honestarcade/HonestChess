/// The computer's thinking time on a real device (#112), built as an app in
/// profile mode — debug builds run the search JIT-compiled, so their
/// timings say nothing about the release app. Run it with
/// `tools/think_time.sh`, which builds, installs and launches it and reads
/// the lines it logs (each prefixed [_tag]).
///
/// Every move goes through the real [ComputerPlayer] isolate: for each step,
/// one discarded warm-up move, then each of [thinkPositions] with a fresh
/// player whose seed is the position's index. The isolate's spawn is
/// excluded from the time; the first request's table set-up is not, because
/// a game's first move pays it too. Last, positions 0–9 are searched again
/// at Club and must give the same moves (CLAUDE.md invariant 4).
///
/// It lives outside `integration_test/`, so the nightly device job never
/// runs it.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:honest_chess/engine/engine.dart';

import 'think_positions.dart';
import 'think_time_report.dart';

const _tag = 'think_time';

/// How many positions the repeat at Club covers.
const determinismPositions = 10;

void _log(Map<String, Object> record) =>
    debugPrint('$_tag ${jsonEncode(record)}');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final status = ValueNotifier('Starting…');
  runApp(_StatusApp(status));
  try {
    await _run(status);
  } on Object catch (error) {
    _log({'kind': 'error', 'message': '$error'});
    status.value = 'Failed: $error';
  }
}

Future<void> _run(ValueNotifier<String> status) async {
  final moves = <MoveTiming>[];
  for (final step in Strength.values) {
    status.value = '${step.name}: warming up';
    await _time(step, 0, seed: -1);
    for (var i = 0; i < thinkPositions.length; i++) {
      status.value = '${step.name}: ${i + 1} of ${thinkPositions.length}';
      final timing = await _time(step, i, seed: i);
      moves.add(timing);
      _log(timing.toJson());
    }
  }

  status.value = 'Checking the same moves come back';
  final mismatches = <Map<String, Object>>[];
  for (var i = 0; i < determinismPositions; i++) {
    final first = moves.firstWhere(
      (m) => m.step == Strength.club && m.index == i,
    );
    final again = await _time(Strength.club, i, seed: i);
    if (again.uci != first.uci) {
      mismatches.add({'index': i, 'first': first.uci, 'again': again.uci});
    }
  }
  _log({
    'kind': 'determinism',
    'step': Strength.club.name,
    'positions': determinismPositions,
    'mismatches': mismatches,
  });

  final reports = summarise(moves);
  for (final report in reports) {
    _log(report.toJson());
  }
  for (final line in table(reports)) {
    debugPrint('$_tag table $line');
  }
  _log({
    'kind': 'done',
    'misses': [
      for (final r in reports)
        if (!r.within) r.step.name,
    ],
    'deterministic': mismatches.isEmpty,
  });
  status.value = 'Done. The results are on the computer.';
}

/// Times one move at [step] in position [index] with [seed], on a fresh
/// player whose isolate is started before the clock starts.
Future<MoveTiming> _time(Strength step, int index, {required int seed}) async {
  final fen = thinkPositions[index].fen;
  final side = Position.fromFen(fen).sideToMove;
  final game = Game.start(
    VsComputer(playerColour: side.opponent, step: step, seed: seed),
    const Untimed(),
    fen: fen,
  );
  final player = ComputerPlayer(step, seed);
  try {
    await player.start();
    final watch = Stopwatch()..start();
    final result = await player.chooseMove(game);
    watch.stop();
    if (result is! Moved) {
      throw StateError('$_tag: ${step.name} $index was cancelled');
    }
    return MoveTiming(
      step: step,
      index: index,
      ms: watch.elapsedMilliseconds,
      uci: result.move.toUci(),
      depth: result.depth,
      nodes: result.nodes,
    );
  } finally {
    await player.dispose();
  }
}

class _StatusApp extends StatelessWidget {
  const _StatusApp(this.status);

  final ValueNotifier<String> status;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ValueListenableBuilder(
            valueListenable: status,
            builder: (context, text, _) => Text(
              'Timing the computer\n\n$text',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    ),
  );
}
