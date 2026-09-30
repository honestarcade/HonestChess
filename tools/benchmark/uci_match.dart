// One step of the strength dial against Stockfish at fixed UCI_Elo levels,
// or against another step whose rating was already measured, for the
// dev-only benchmark (#69, #159). Run it through
// tools/benchmark_stockfish.sh, which refuses without Stockfish; CI never
// runs it.
//
//   dart run tools/benchmark/uci_match.dart --stockfish PATH
//       [--step master] [--games 60] [--levels 1600,1800,2000]
//       [--vs STEP --anchor ELO,LOW,HIGH] [--jobs 1] [--out FILE] [--pgn DIR]
//
// Stockfish plays on a 5 s + 0.1 s clock. Its flag falling is counted but
// does not end the game: on a busy machine the operating system, not the
// play, would decide it. The step plays every move at its fixed node budget, as a player
// gets it; its clock is kept and reported, never enforced. With --vs the
// opponent is that step instead of Stockfish, and the rating is chained
// from --anchor, the opponent's measured rating and 95% interval. --jobs
// plays that many games at once, each in its own isolate with its own
// Stockfish; every game is seeded, so the results do not depend on it.
// Appends a dated section to --out (the engine-strength memory by default)
// and writes the games as PGN under --pgn; it commits nothing.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:honest_chess/engine/engine.dart';

import '../../test/fixtures/openings.dart';
import 'elo.dart';

const int startMs = 5000;
const int incrementMs = 100;
const int plyCap = 200;
const int seedBase = 2026;
const String defaultOut = '.n8/memory/engine-strength.md';
const String defaultPgn = 'build/benchmark';

/// The owner's target rating for each step, as measured: their decision on
/// #159, 2026-09-29.
const Map<Strength, int> targets = {
  Strength.beginner: 600,
  Strength.casual: 900,
  Strength.club: 1200,
  Strength.strong: 1600,
  Strength.master: 2200,
};

/// Stockfish's lowest `UCI_Elo`, from its own option list (`uci` prints
/// `UCI_Elo … min 1320`, Stockfish 19, checked 2026-09-29).
const int stockfishFloor = 1320;

Never _usage(String message) {
  stderr.writeln('uci_match: $message');
  stderr.writeln(
    'usage: dart run tools/benchmark/uci_match.dart --stockfish PATH '
    '[--step master] [--games N] [--levels 1600,1800,2000] '
    '[--vs STEP --anchor ELO,LOW,HIGH] [--jobs N] [--out FILE] [--pgn DIR]',
  );
  exit(2);
}

Strength _step(String name) {
  for (final step in Strength.values) {
    if (step.name == name) return step;
  }
  _usage('no strength step named $name');
}

/// Who the step under test plays: Stockfish at [level], or [step].
final class Opponent {
  const Opponent.stockfish(int this.level) : step = null;
  const Opponent.step(Strength this.step) : level = null;

  final int? level;
  final Strength? step;

  String get label => switch (step) {
    final s? => title(s),
    null => 'Stockfish UCI_Elo $level',
  };

  String get fileName => switch (step) {
    final s? => 'vs-${s.name}',
    null => 'uci-elo-$level',
  };
}

/// [step]'s name as a title, e.g. `Casual`.
String title(Strength step) =>
    '${step.name[0].toUpperCase()}${step.name.substring(1)}';

Future<void> main(List<String> args) async {
  final options = <String, String>{};
  for (var i = 0; i < args.length; i++) {
    final name = args[i];
    if (!name.startsWith('--') || i + 1 >= args.length) {
      _usage('unexpected argument $name');
    }
    options[name.substring(2)] = args[++i];
  }
  final unknown = options.keys.toSet().difference({
    'stockfish',
    'step',
    'games',
    'levels',
    'vs',
    'anchor',
    'jobs',
    'out',
    'pgn',
  });
  if (unknown.isNotEmpty) _usage('unknown option ${unknown.join(', ')}');
  final stockfishPath = options['stockfish'];
  if (stockfishPath == null || !File(stockfishPath).existsSync()) {
    stderr.writeln(
      'stockfish not found: ${stockfishPath ?? '(no --stockfish)'}',
    );
    exit(3);
  }
  final step = _step(options['step'] ?? 'master');
  final games = int.tryParse(options['games'] ?? '60');
  if (games == null || games < 1) _usage('--games must be a positive integer');
  final jobs = int.tryParse(options['jobs'] ?? '1');
  if (jobs == null || jobs < 1) _usage('--jobs must be a positive integer');
  final vs = options['vs'] == null ? null : _step(options['vs']!);
  Estimate? anchor;
  if (vs != null) {
    if (options.containsKey('levels')) _usage('--vs replaces --levels');
    final parts = [
      for (final p in (options['anchor'] ?? '').split(','))
        if (int.tryParse(p) case final n?) n.toDouble(),
    ];
    if (parts.length != 3 || !(parts[1] <= parts[0] && parts[0] <= parts[2])) {
      _usage('--vs needs --anchor ELO,LOW,HIGH (LOW <= ELO <= HIGH)');
    }
    anchor = Estimate(parts[0], parts[1], parts[2]);
  } else if (options.containsKey('anchor')) {
    _usage('--anchor needs --vs');
  }
  final levels = [
    for (final l in (options['levels'] ?? '1600,1800,2000').split(','))
      int.tryParse(l) ?? _usage('--levels must be integers'),
  ];
  if (vs == null && levels.any((l) => l < stockfishFloor)) {
    _usage("--levels must be at least $stockfishFloor, Stockfish's floor");
  }
  final opponents = vs == null
      ? [for (final l in levels) Opponent.stockfish(l)]
      : [Opponent.step(vs)];
  final out = options['out'] ?? defaultOut;
  final pgnDir = Directory(options['pgn'] ?? defaultPgn)
    ..createSync(recursive: true);

  final started = DateTime.now().toUtc();
  // Read before the first game: the tree may move on during a long run.
  final commit = _commit();
  final date = started.toIso8601String().substring(0, 10);
  final engineName = vs == null ? await Stockfish.identify(stockfishPath) : '';
  final scores = <LevelScore>[];
  final rows = <String>[];
  var stepMoves = 0;
  var stepMicros = 0;
  var stepWouldFlag = 0;
  var stockfishFlags = 0;
  for (final opponent in opponents) {
    final results = List<GameResult?>.filled(games, null);
    var next = 0;
    Future<void> worker() async {
      while (next < games) {
        final g = next++;
        final result = await Isolate.run(
          () => playGame(stockfishPath, step, opponent, g),
        );
        results[g] = result;
        stdout.writeln(
          '${opponent.label} game ${g + 1}/$games: ${title(step)} '
          '${result.stepWhite ? 'White' : 'Black'} '
          '${result.stepScore} (${result.ending}, ${result.plies} plies)',
        );
      }
    }

    await Future.wait([for (var j = 0; j < jobs; j++) worker()]);
    final pgn = StringBuffer();
    var wins = 0;
    var draws = 0;
    var losses = 0;
    for (final (g, r) in results.indexed) {
      final result = r!;
      stepMoves += result.stepMoves;
      stepMicros += result.stepMicros;
      if (result.stepWouldFlag) stepWouldFlag++;
      if (result.stockfishFlagged) stockfishFlags++;
      switch (result.stepScore) {
        case 1:
          wins++;
        case 0:
          losses++;
        default:
          draws++;
      }
      pgn.write(
        result.pgn(date: date, step: step, opponent: opponent, round: g + 1),
      );
    }
    File('${pgnDir.path}/$date-${step.name}-${opponent.fileName}.pgn')
        .writeAsStringSync(pgn.toString());
    final score = LevelScore(opponent.level ?? 0, games, wins + draws / 2);
    scores.add(score);
    final percent = (100 * score.points / games).toStringAsFixed(1);
    rows.add(
      '| ${opponent.level ?? opponent.label} | $games '
      '| $wins / $draws / $losses | $percent% | ${score.performanceText} |',
    );
  }

  final command = [
    'tools/benchmark_stockfish.sh',
    for (final MapEntry(:key, :value) in options.entries)
      if (key != 'stockfish') '--$key $value',
  ].join(' ');
  final common = (
    date: date,
    minutes: DateTime.now().toUtc().difference(started).inMinutes,
    step: step,
    games: games,
    rows: rows,
    stepSeconds: stepMoves == 0 ? 0.0 : stepMicros / stepMoves / 1e6,
    commit: commit,
    command: command,
  );
  final section = switch (vs) {
    null => _stockfishReport(
      common,
      engine: engineName,
      levels: levels,
      estimate: fitElo(scores),
      stepWouldFlag: stepWouldFlag,
      stockfishFlags: stockfishFlags,
    ),
    final vs => chainedReport(
      common,
      vs: vs,
      anchor: anchor!,
      difference: fitElo(scores),
      hardware: _hardware(),
    ),
  };
  final file = File(out);
  if (!file.existsSync()) {
    file
      ..createSync(recursive: true)
      ..writeAsStringSync(_header);
  }
  file.writeAsStringSync('\n$section', mode: FileMode.append);
  stdout.writeln(section);
  stdout.writeln('Appended to $out (not committed).');
  // An engine's stdout subscription would otherwise keep the VM alive.
  exit(0);
}

const _header = '''---
name: engine-strength
description: Each strength step measured against Stockfish at fixed UCI_Elo levels, or chained through a match against a measured step — one dated section per run of tools/benchmark_stockfish.sh
metadata:
  type: project
---

# Engine strength

Each section below is one run of `tools/benchmark_stockfish.sh` (#69,
#159), written by the script and committed by hand.
''';

/// What every report states, whatever the opponent.
typedef RunFacts = ({
  String date,
  int minutes,
  Strength step,
  int games,
  List<String> rows,
  double stepSeconds,
  String commit,
  String command,
});

String _settings(Strength step) {
  final s = step.settings;
  return '`Strength.${step.name}` at ${s.nodeBudget} nodes per move '
      '(depth cap ${s.depthCap ?? 'none'}, noise ±${s.noiseCp} cp, '
      'blunders on ${s.blunderPercent}% of moves, '
      '${s.seesMateInOne ? 'sees' : 'may miss'} mate in one)';
}

String _stockfishReport(
  RunFacts c, {
  required String engine,
  required List<int> levels,
  required EloEstimate estimate,
  required int stepWouldFlag,
  required int stockfishFlags,
}) {
  final name = title(c.step);
  final target = targets[c.step]!;
  return '''
## ${c.date} — $name against $engine

- **Estimate:** $name ≈ $estimate, by logistic (400-point) maximum likelihood over all levels, draws as half points; the interval is the normal approximation.
- **Target ~$target (the owner's, #159, 2026-09-29):** ${targetVerdict(estimate, target)}
- **Hardware:** ${_hardware()}
- **Engine under test:** ${_settings(c.step)}, commit ${c.commit}.
- **Stockfish:** `$engine`, `Threads=1`, `Hash=64`, `UCI_LimitStrength=true`, `UCI_Elo` ${levels.join(' / ')}.
- **Games:** ${c.games} per level from the ladder's openings (`test/fixtures/openings.dart`), each opening with both colours in turn; seeds $seedBase + game index; a $plyCap-ply cap after the opening is a draw. Took ${c.minutes} min.
- **Clock:** Stockfish plays on ${startMs ~/ 1000} s + ${incrementMs / 1000} s per move (`go wtime/btime/winc/binc`) and ran out of time in $stockfishFlags games; a fallen flag is counted, not enforced, and it then sees one increment on its clock. $name plays every move at its fixed node budget; its clock is recorded, not enforced: ${c.stepSeconds.toStringAsFixed(2)} s per move on average, and it would have lost on time in $stepWouldFlag games.
- **Caveat:** `UCI_Elo` is Stockfish's own calibration, made under conditions other than this match's clock; read the estimate as approximate.
- **Command:** `${c.command}`

| Stockfish `UCI_Elo` | Games | $name W / D / L | Score | Performance |
| --- | --- | --- | --- | --- |
${c.rows.join('\n')}
''';
}

/// The section for a chained run: [c.step] against [vs], whose rating
/// [anchor] was measured in an earlier section.
String chainedReport(
  RunFacts c, {
  required Strength vs,
  required Estimate anchor,
  required EloEstimate difference,
  required String hardware,
}) {
  final name = title(c.step);
  final other = title(vs);
  final target = targets[c.step]!;
  final EloEstimate estimate = switch (difference) {
    final Estimate d => chainElo(anchor, d),
    EloBound(:final above) => EloBound(above: above, level: anchor.elo.round()),
  };
  final gap = switch (difference) {
    Estimate(:final elo, :final low, :final high) =>
      '${elo.round()} (95% interval ${low.round()} to ${high.round()})',
    EloBound(:final above) => above ? 'above 0' : 'below 0',
  };
  return '''
## ${c.date} — $name against $other (chained)

- **Estimate:** $name ≈ $estimate: $other's anchor, $anchor, plus the match's rating difference, $gap. The difference is fitted by logistic (400-point) maximum likelihood, draws as half points. The two 95% intervals are combined in quadrature, as independent normal errors.
- **Method:** chained, because Stockfish cannot play below $stockfishFloor. `UCI_Elo` stops at $stockfishFloor, and its mapping to `Skill Level` puts $stockfishFloor at level 0 (Stockfish `src/search.h`, `struct Skill`, read 2026-09-30), so `Skill Level` goes no lower either. The anchor is $other's estimate from its own dated section in this file.
- **Target ~$target (the owner's, #159, 2026-09-29):** ${targetVerdict(estimate, target)}
- **Hardware:** $hardware
- **Engine under test:** ${_settings(c.step)}, against ${_settings(vs)}, commit ${c.commit}.
- **Games:** ${c.games} from the ladder's openings (`test/fixtures/openings.dart`), each opening with both colours in turn; seeds $seedBase + game index, shared by both sides; a $plyCap-ply cap after the opening is a draw. Both sides play at their fixed node budgets, with no clock. Took ${c.minutes} min.
- **Caveat (self-play):** two steps of one engine share its evaluation and blind spots, so a match between them can read a wider gap than either would show against other players.
- **Command:** `${c.command}`

| Opponent | Games | $name W / D / L | Score | Difference |
| --- | --- | --- | --- | --- |
${c.rows.join('\n')}
''';
}

String _hardware() {
  try {
    final r = Process.runSync('sysctl', [
      '-n',
      'machdep.cpu.brand_string',
      'hw.memsize',
    ]);
    final lines = (r.stdout as String).trim().split('\n');
    if (r.exitCode == 0 && lines.length == 2) {
      final gb = (int.parse(lines[1].trim()) / (1 << 30)).round();
      return '${lines[0].trim()}, $gb GB (`sysctl -n machdep.cpu.brand_string hw.memsize`)';
    }
  } on Object {
    // Not macOS: fall through to what Dart knows.
  }
  return '${Platform.operatingSystemVersion}, ${Platform.numberOfProcessors} processors';
}

String _commit() {
  final r = Process.runSync('git', ['rev-parse', '--short', 'HEAD']);
  final dirty = Process.runSync('git', ['status', '--porcelain']);
  final sha = r.exitCode == 0 ? (r.stdout as String).trim() : 'unknown';
  final clean = dirty.exitCode == 0 && (dirty.stdout as String).trim().isEmpty;
  return clean ? sha : '$sha (with uncommitted changes)';
}

/// One finished game.
final class GameResult {
  GameResult({
    required this.stepWhite,
    required this.stepScore,
    required this.ending,
    required this.plies,
    required this.sanMoves,
    required this.stepMoves,
    required this.stepMicros,
    required this.stepWouldFlag,
    required this.stockfishFlagged,
  });

  final bool stepWhite;
  final double stepScore;
  final String ending;
  final int plies;
  final List<String> sanMoves;
  final int stepMoves;
  final int stepMicros;
  final bool stepWouldFlag;
  final bool stockfishFlagged;

  String pgn({
    required String date,
    required Strength step,
    required Opponent opponent,
    required int round,
  }) {
    final whiteScore = stepWhite ? stepScore : 1 - stepScore;
    final result = switch (whiteScore) {
      1 => '1-0',
      0 => '0-1',
      _ => '1/2-1/2',
    };
    final us = 'Honest Chess ${title(step)}';
    final them = opponent.step == null
        ? opponent.label
        : 'Honest Chess ${opponent.label}';
    final text = StringBuffer();
    for (final (i, san) in sanMoves.indexed) {
      if (i.isEven) text.write('${i ~/ 2 + 1}. ');
      text.write('$san ');
    }
    return '[Event "Honest Chess benchmark"]\n'
        '[Site "dev machine"]\n'
        '[Date "${date.replaceAll('-', '.')}"]\n'
        '[Round "$round"]\n'
        '[White "${stepWhite ? us : them}"]\n'
        '[Black "${stepWhite ? them : us}"]\n'
        '[Result "$result"]\n'
        '[Termination "$ending"]\n'
        '[TimeControl "${opponent.step == null ? '5+0.1' : '-'}"]\n\n'
        '$text$result\n\n';
  }
}

/// Game [index] of [step] against [opponent]: opening `index ~/ 2` of the
/// ladder's (cycling), [step] White in the even games.
Future<GameResult> playGame(
  String stockfishPath,
  Strength step,
  Opponent opponent,
  int index,
) async {
  final level = opponent.level;
  final engine = level == null ? null : await Stockfish.start(stockfishPath);
  try {
    await engine?.configure(level!);
    await engine?.newGame();
    return await _play(engine, step, opponent.step, index);
  } finally {
    await engine?.quit();
  }
}

Future<GameResult> _play(
  Stockfish? engine,
  Strength step,
  Strength? other,
  int index,
) async {
  final opening = ladderOpenings[(index % (2 * ladderOpenings.length)) ~/ 2];
  final stepWhite = index.isEven;
  final stepColour = stepWhite ? Colour.white : Colour.black;
  final seed = seedBase + index;
  final table = TranspositionTable();

  var position = Position.initial();
  final positions = [position];
  final uci = <String>[];
  final sanMoves = <String>[];
  void apply(Move move) {
    sanMoves.add(san(position, move));
    uci.add(move.toUci());
    position = play(position, move);
    positions.add(position);
  }

  Move ours(Strength who) => chooseMove(
    position,
    who,
    seed,
    history: [for (var i = 0; i < positions.length - 1; i++) positions[i].key],
    table: table,
  )!.move;

  for (final m in opening) {
    apply(Move.fromUci(position, m));
  }
  var stepMs = startMs;
  var stockfishMs = startMs;
  var stepMoves = 0;
  var stepMicros = 0;
  var stepWouldFlag = false;
  var stockfishFlagged = false;
  GameStatus? end;
  var plies = 0;
  for (; plies < plyCap; plies++) {
    final now = status(positions);
    if (now.isOver) {
      end = now;
      break;
    }
    final stopwatch = Stopwatch()..start();
    if (position.sideToMove == stepColour) {
      final move = ours(step);
      stepMoves++;
      stepMicros += stopwatch.elapsedMicroseconds;
      stepMs -= stopwatch.elapsedMilliseconds;
      if (stepMs <= 0) stepWouldFlag = true;
      stepMs += incrementMs;
      apply(move);
    } else if (engine == null) {
      apply(ours(other!));
    } else {
      // Neither clock is enforced; each is shown as at least one increment
      // so Stockfish's time management never sees a negative clock.
      final ownMs = stockfishMs < incrementMs ? incrementMs : stockfishMs;
      final otherMs = stepMs < incrementMs ? incrementMs : stepMs;
      final best = await engine.bestMove(
        uci,
        whiteMs: stepWhite ? otherMs : ownMs,
        blackMs: stepWhite ? ownMs : otherMs,
      );
      stockfishMs = ownMs - stopwatch.elapsedMilliseconds;
      if (stockfishMs <= 0) stockfishFlagged = true;
      stockfishMs += incrementMs;
      apply(Move.fromUci(position, best));
    }
  }
  end ??= status(positions);
  final stepScore = switch (end) {
    Win(:final winner) => winner == stepColour ? 1.0 : 0.0,
    Draw() || Ongoing() => 0.5,
  };
  final ending = end is Ongoing ? 'ply cap' : '$end';
  return GameResult(
    stepWhite: stepWhite,
    stepScore: stepScore,
    ending: ending,
    plies: plies,
    sanMoves: sanMoves,
    stepMoves: stepMoves,
    stepMicros: stepMicros,
    stepWouldFlag: stepWouldFlag,
    stockfishFlagged: stockfishFlagged,
  );
}

/// [move] in Standard Algebraic Notation, for the PGN files.
String san(Position position, Move move) {
  var text = '';
  if (move.isCastling) {
    text = move.to.file == 6 ? 'O-O' : 'O-O-O';
  } else {
    final kind = position.pieceAt(move.from)!.kind;
    final capture = move.isCapture || move.isEnPassant;
    if (kind == PieceKind.pawn) {
      text =
          '${capture ? '${move.from.name[0]}x' : ''}${move.to.name}'
          '${move.promotion == null ? '' : '=${move.promotion!.letter.toUpperCase()}'}';
    } else {
      final rivals = [
        for (final other in legalMoves(position))
          if (other.to == move.to &&
              other.from != move.from &&
              position.pieceAt(other.from)!.kind == kind)
            other.from,
      ];
      var from = '';
      if (rivals.isNotEmpty) {
        if (rivals.every((s) => s.file != move.from.file)) {
          from = move.from.name[0];
        } else if (rivals.every((s) => s.rank != move.from.rank)) {
          from = move.from.name[1];
        } else {
          from = move.from.name;
        }
      }
      text =
          '${kind.letter.toUpperCase()}$from${capture ? 'x' : ''}'
          '${move.to.name}';
    }
  }
  final next = play(position, move);
  if (inCheck(next)) text += legalMoves(next).isEmpty ? '#' : '+';
  return text;
}

/// Stockfish over UCI on its stdin and stdout.
final class Stockfish {
  Stockfish._(this._process, this._lines);

  final Process _process;
  final StreamIterator<String> _lines;
  String name = 'Stockfish';

  /// The `id name` the engine at [path] reports, e.g. `Stockfish 19`.
  static Future<String> identify(String path) async {
    final engine = await start(path);
    await engine.quit();
    return engine.name;
  }

  static Future<Stockfish> start(String path) async {
    final process = await Process.start(path, const []);
    unawaited(process.stderr.drain<void>());
    final engine = Stockfish._(
      process,
      StreamIterator(
        process.stdout.transform(utf8.decoder).transform(const LineSplitter()),
      ),
    );
    engine._send('uci');
    await engine._until((line) {
      if (line.startsWith('id name ')) {
        engine.name = line.substring('id name '.length).trim();
      }
      return line == 'uciok';
    });
    return engine;
  }

  void _send(String command) => _process.stdin.writeln(command);

  Future<String> _until(bool Function(String line) done) async {
    while (await _lines.moveNext()) {
      if (done(_lines.current)) return _lines.current;
    }
    throw StateError('stockfish exited');
  }

  Future<void> _ready() async {
    _send('isready');
    await _until((line) => line == 'readyok');
  }

  Future<void> configure(int elo) async {
    _send('setoption name Threads value 1');
    _send('setoption name Hash value 64');
    _send('setoption name UCI_LimitStrength value true');
    _send('setoption name UCI_Elo value $elo');
    await _ready();
  }

  Future<void> newGame() async {
    _send('ucinewgame');
    await _ready();
  }

  Future<String> bestMove(
    List<String> moves, {
    required int whiteMs,
    required int blackMs,
  }) async {
    _send('position startpos moves ${moves.join(' ')}');
    _send(
      'go wtime $whiteMs btime $blackMs winc $incrementMs binc $incrementMs',
    );
    final line = await _until((line) => line.startsWith('bestmove '));
    return line.split(' ')[1];
  }

  Future<void> quit() async {
    _send('quit');
    await _process.stdin.close();
    await _process.exitCode;
    await _lines.cancel();
  }
}
