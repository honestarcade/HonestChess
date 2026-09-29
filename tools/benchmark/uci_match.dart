// Master against Stockfish at fixed UCI_Elo levels, for the dev-only
// benchmark (#69). Run it through tools/benchmark_stockfish.sh, which
// refuses without Stockfish; CI never runs it.
//
//   dart run tools/benchmark/uci_match.dart --stockfish PATH
//       [--games 60] [--levels 1600,1800,2000] [--out FILE] [--pgn DIR]
//
// Stockfish plays on a 5 s + 0.1 s clock and loses on time if its flag
// falls. Master plays every move at its fixed node budget, as a player gets
// it; its clock is kept and reported, never enforced. Appends a dated
// section to --out (the engine-strength memory by default) and writes the
// games as PGN under --pgn; it commits nothing.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:honest_chess/engine/engine.dart';

import '../../test/fixtures/openings.dart';
import 'elo.dart';

const int startMs = 5000;
const int incrementMs = 100;
const int plyCap = 200;
const int seedBase = 2026;
const String defaultOut = '.n8/memory/engine-strength.md';
const String defaultPgn = 'build/benchmark';

Never _usage(String message) {
  stderr.writeln('uci_match: $message');
  stderr.writeln(
    'usage: dart run tools/benchmark/uci_match.dart --stockfish PATH '
    '[--games N] [--levels 1600,1800,2000] [--out FILE] [--pgn DIR]',
  );
  exit(2);
}

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
    'games',
    'levels',
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
  final games = int.tryParse(options['games'] ?? '60');
  if (games == null || games < 1) _usage('--games must be a positive integer');
  final levels = [
    for (final l in (options['levels'] ?? '1600,1800,2000').split(','))
      int.tryParse(l) ?? _usage('--levels must be integers'),
  ];
  final out = options['out'] ?? defaultOut;
  final pgnDir = Directory(options['pgn'] ?? defaultPgn)
    ..createSync(recursive: true);

  final started = DateTime.now().toUtc();
  // Read before the first game: the tree may move on during a long run.
  final commit = _commit();
  final date = started.toIso8601String().substring(0, 10);
  final engine = await Stockfish.start(stockfishPath);
  final scores = <LevelScore>[];
  final rows = <String>[];
  var masterMoves = 0;
  var masterMicros = 0;
  var masterWouldFlag = 0;
  var stockfishFlags = 0;
  try {
    for (final level in levels) {
      await engine.configure(level);
      final pgn = StringBuffer();
      var wins = 0;
      var draws = 0;
      var losses = 0;
      for (var g = 0; g < games; g++) {
        final result = await _playGame(engine, level, g);
        masterMoves += result.masterMoves;
        masterMicros += result.masterMicros;
        if (result.masterWouldFlag) masterWouldFlag++;
        if (result.stockfishFlagged) stockfishFlags++;
        switch (result.masterScore) {
          case 1:
            wins++;
          case 0:
            losses++;
          default:
            draws++;
        }
        pgn.write(result.pgn(date: date, level: level, round: g + 1));
        stdout.writeln(
          'UCI_Elo $level game ${g + 1}/$games: Master '
          '${result.masterWhite ? 'White' : 'Black'} '
          '${result.masterScore} (${result.ending}, ${result.plies} plies)',
        );
      }
      File('${pgnDir.path}/$date-uci-elo-$level.pgn')
          .writeAsStringSync(pgn.toString());
      final score = LevelScore(level, games, wins + draws / 2);
      scores.add(score);
      rows.add(
        '| $level | $games | $wins / $draws / $losses '
        '| ${(100 * score.points / games).toStringAsFixed(1)}% '
        '| ${score.performanceText} |',
      );
    }
  } finally {
    await engine.quit();
  }

  final estimate = fitElo(scores);
  final section = _report(
    date: date,
    minutes: DateTime.now().toUtc().difference(started).inMinutes,
    engine: engine.name,
    games: games,
    levels: levels,
    rows: rows,
    estimate: estimate,
    masterSeconds: masterMoves == 0 ? 0 : masterMicros / masterMoves / 1e6,
    masterWouldFlag: masterWouldFlag,
    stockfishFlags: stockfishFlags,
    commit: commit,
    command: [
      'tools/benchmark_stockfish.sh',
      for (final MapEntry(:key, :value) in options.entries)
        if (key != 'stockfish') '--$key $value',
    ].join(' '),
  );
  final file = File(out);
  if (!file.existsSync()) {
    file
      ..createSync(recursive: true)
      ..writeAsStringSync(_header);
  }
  file.writeAsStringSync('\n$section', mode: FileMode.append);
  stdout.writeln(section);
  stdout.writeln('Appended to $out (not committed).');
  // The engine's stdout subscription would otherwise keep the VM alive.
  exit(0);
}

const _header = '''---
name: engine-strength
description: Master measured against Stockfish at fixed UCI_Elo levels — one dated section per run of tools/benchmark_stockfish.sh
metadata:
  type: project
---

# Engine strength

Each section below is one run of `tools/benchmark_stockfish.sh` (#69),
written by the script and committed by hand. The target is Master at
1800–2000 Elo.
''';

String _report({
  required String date,
  required int minutes,
  required String engine,
  required int games,
  required List<int> levels,
  required List<String> rows,
  required EloEstimate estimate,
  required double masterSeconds,
  required int masterWouldFlag,
  required int stockfishFlags,
  required String commit,
  required String command,
}) {
  final verdict = switch (estimate) {
    Estimate(:final elo) when elo >= 1800 && elo <= 2000 =>
      'met: the estimate is within 1800–2000.',
    Estimate(:final elo) when elo > 2000 =>
      'met: the estimate is above 2000, stronger than the target range.',
    Estimate(:final elo) =>
      'not met: the estimate is ${(1800 - elo).round()} Elo below 1800.',
    EloBound(above: true) => 'met: Master won every game.',
    EloBound(above: false) => 'not met: Master lost every game.',
  };
  final master = Strength.master.settings;
  return '''
## $date — Master against $engine

- **Estimate:** Master ≈ $estimate, by logistic (400-point) maximum likelihood over all levels, draws as half points; the interval is the normal approximation.
- **Target 1800–2000:** $verdict
- **Hardware:** ${_hardware()}
- **Engine under test:** `Strength.master` at ${master.nodeBudget} nodes per move, commit $commit.
- **Stockfish:** `$engine`, `Threads=1`, `Hash=64`, `UCI_LimitStrength=true`, `UCI_Elo` ${levels.join(' / ')}.
- **Games:** $games per level from the ladder's openings (`test/fixtures/openings.dart`), each opening with both colours in turn; seeds $seedBase + game index; a $plyCap-ply cap after the opening is a draw. Took $minutes min.
- **Clock:** Stockfish plays on ${startMs ~/ 1000} s + ${incrementMs / 1000} s per move (`go wtime/btime/winc/binc`) and lost on time in $stockfishFlags games. Master plays every move at its fixed node budget; its clock is recorded, not enforced: ${masterSeconds.toStringAsFixed(2)} s per move on average, and it would have lost on time in $masterWouldFlag games.
- **Caveat:** `UCI_Elo` is Stockfish's own calibration, made under conditions other than this match's clock; read the estimate as approximate.
- **Command:** `$command`

| Stockfish `UCI_Elo` | Games | Master W / D / L | Score | Performance |
| --- | --- | --- | --- | --- |
${rows.join('\n')}
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
    required this.masterWhite,
    required this.masterScore,
    required this.ending,
    required this.plies,
    required this.sanMoves,
    required this.masterMoves,
    required this.masterMicros,
    required this.masterWouldFlag,
    required this.stockfishFlagged,
  });

  final bool masterWhite;
  final double masterScore;
  final String ending;
  final int plies;
  final List<String> sanMoves;
  final int masterMoves;
  final int masterMicros;
  final bool masterWouldFlag;
  final bool stockfishFlagged;

  String pgn({required String date, required int level, required int round}) {
    final whiteScore = masterWhite ? masterScore : 1 - masterScore;
    final result = switch (whiteScore) {
      1 => '1-0',
      0 => '0-1',
      _ => '1/2-1/2',
    };
    final master = 'Honest Chess Master';
    final stockfish = 'Stockfish UCI_Elo $level';
    final text = StringBuffer();
    for (final (i, san) in sanMoves.indexed) {
      if (i.isEven) text.write('${i ~/ 2 + 1}. ');
      text.write('$san ');
    }
    return '[Event "Honest Chess benchmark"]\n'
        '[Site "dev machine"]\n'
        '[Date "${date.replaceAll('-', '.')}"]\n'
        '[Round "$round"]\n'
        '[White "${masterWhite ? master : stockfish}"]\n'
        '[Black "${masterWhite ? stockfish : master}"]\n'
        '[Result "$result"]\n'
        '[Termination "$ending"]\n'
        '[TimeControl "5+0.1"]\n\n'
        '$text$result\n\n';
  }
}

Future<GameResult> _playGame(Stockfish engine, int level, int index) async {
  final opening = ladderOpenings[(index % (2 * ladderOpenings.length)) ~/ 2];
  final masterWhite = index.isEven;
  final masterColour = masterWhite ? Colour.white : Colour.black;
  final seed = seedBase + index;
  final table = TranspositionTable();
  await engine.newGame();

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

  for (final m in opening) {
    apply(Move.fromUci(position, m));
  }
  var masterMs = startMs;
  var stockfishMs = startMs;
  var masterMoves = 0;
  var masterMicros = 0;
  var masterWouldFlag = false;
  GameStatus? end;
  var ending = 'ply cap';
  var plies = 0;
  for (; plies < plyCap; plies++) {
    final now = status(positions);
    if (now.isOver) {
      end = now;
      break;
    }
    final stopwatch = Stopwatch()..start();
    if (position.sideToMove == masterColour) {
      final choice = chooseMove(
        position,
        Strength.master,
        seed,
        history: [
          for (var i = 0; i < positions.length - 1; i++) positions[i].key,
        ],
        table: table,
      )!;
      masterMoves++;
      masterMicros += stopwatch.elapsedMicroseconds;
      masterMs -= stopwatch.elapsedMilliseconds;
      if (masterMs <= 0) masterWouldFlag = true;
      masterMs += incrementMs;
      apply(choice.move);
    } else {
      final ownMs = stockfishMs;
      // Master's clock is not enforced; Stockfish is shown at least one
      // increment of it so its time management never sees a negative clock.
      final otherMs = masterMs < incrementMs ? incrementMs : masterMs;
      final best = await engine.bestMove(
        uci,
        whiteMs: masterWhite ? otherMs : ownMs,
        blackMs: masterWhite ? ownMs : otherMs,
      );
      stockfishMs -= stopwatch.elapsedMilliseconds;
      if (stockfishMs <= 0) {
        end = flagResult(position, masterColour.opponent);
        ending = 'Stockfish lost on time';
        break;
      }
      stockfishMs += incrementMs;
      apply(Move.fromUci(position, best));
    }
  }
  end ??= status(positions);
  final double masterScore;
  switch (end) {
    case Win(:final winner):
      masterScore = winner == masterColour ? 1 : 0;
      if (ending == 'ply cap') ending = '$end';
    case Draw():
      masterScore = 0.5;
      if (ending == 'ply cap') ending = '$end';
    case Ongoing():
      masterScore = 0.5;
  }
  return GameResult(
    masterWhite: masterWhite,
    masterScore: masterScore,
    ending: ending,
    plies: plies,
    sanMoves: sanMoves,
    masterMoves: masterMoves,
    masterMicros: masterMicros,
    masterWouldFlag: masterWouldFlag,
    stockfishFlagged: ending == 'Stockfish lost on time',
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
