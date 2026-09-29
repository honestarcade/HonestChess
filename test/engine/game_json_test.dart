// Saving and restoring a game as version-1 JSON: a property-based round trip
// over seeded random games, the frozen fixture every later build must keep
// loading, and each refusal — with the complement that a refused file loads
// nothing and never crashes. The round trip is tagged `guard` with reasons
// starting `game-json:` so tools/mutation_check.py can require it to fire.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:honest_chess/engine/engine.dart';

import '../fixtures/fens.dart';

const white = Colour.white, black = Colour.black;

/// A hand-wound monotonic time source.
class FakeTime {
  int ms = 0;
  int call() => ms;
  void advance(int by) => ms += by;
}

/// Everything two games could differ in, read at [time]'s now; empty when
/// they are the same game. A running clock is compared as paused, because a
/// save stops the clock the way a takeback does.
List<String> differences(Game actual, Game expected, FakeTime time) {
  final out = <String>[];
  void check(String what, Object? a, Object? e) {
    if (a != e) out.add('$what: $a != $e');
  }

  ClockSnapshot stopped(Game g) {
    final s = g.clock.snapshot(time.ms);
    return ClockSnapshot(
      control: s.control,
      phase: s.phase == ClockPhase.running ? ClockPhase.paused : s.phase,
      runningSide: s.runningSide,
      whiteMs: s.whiteMs,
      blackMs: s.blackMs,
    );
  }

  check('mode', actual.mode, expected.mode);
  check('options', actual.options, expected.options);
  check('fen', actual.position.toFen(), expected.position.toFen());
  check('history length', actual.history.length, expected.history.length);
  for (
    var i = 0;
    i < min(actual.history.length, expected.history.length);
    i++
  ) {
    check('history[$i]', actual.history[i], expected.history[i]);
  }
  check('clock', stopped(actual), stopped(expected));
  check('result', actual.status, expected.status);
  return out;
}

/// [game] saved, encoded, decoded and loaded, as the app will do it.
Game reload(Game game, FakeTime time) => Game.fromJson(
  jsonDecode(jsonEncode(game.toJson())) as Map<String, Object?>,
  time: time.call,
);

/// A seed for the computer, sometimes with the top bit set.
int _randomSeed(Random rng) =>
    (rng.nextInt(1 << 32) << 32) | rng.nextInt(1 << 32);

/// A short random game from [seed]: random mode, time control and start,
/// random legal moves mixed with resignations, agreed draws, takebacks,
/// pauses and flag falls. It may end over, mid-takeback or still going.
(Game, FakeTime) playout(int seed) {
  final rng = Random(seed);
  final time = FakeTime();
  final GameMode mode = rng.nextInt(3) == 0
      ? const TwoPlayer()
      : VsComputer(
          playerColour: rng.nextBool() ? white : black,
          step: Strength.values[rng.nextInt(Strength.values.length)],
          seed: _randomSeed(rng),
        );
  final controls = <TimeControl>[
    const Untimed(),
    ...TimeControl.presets,
    Timed(1, 0),
    Timed(1 + rng.nextInt(90), rng.nextInt(61)),
  ];
  final control = controls[rng.nextInt(controls.length)];
  final fen = rng.nextInt(4) == 0 ? allFens[rng.nextInt(allFens.length)] : null;
  var game = Game.start(
    mode,
    control,
    options: GameOptions(takebackAllowed: rng.nextInt(5) != 0),
    fen: fen,
    time: time.call,
  );
  final plies = rng.nextInt(61);
  for (var i = 0; i < plies; i++) {
    time.advance(rng.nextInt(8000));
    final event = rng.nextInt(100);
    if (event < 2) {
      final side = switch (mode) {
        VsComputer(:final playerColour) => playerColour,
        TwoPlayer() => rng.nextBool() ? white : black,
      };
      if (!game.isOver) game = game.resign(side);
    } else if (event < 4) {
      if (game.canAgreeDraw) game = game.agreeDraw();
    } else if (event < 12) {
      if (game.canTakeBack) game = game.takeBack();
    } else if (event < 15) {
      game = game.pause();
    } else if (event < 18) {
      game = game.resume();
    } else if (event < 20) {
      time.advance(rng.nextInt(120000));
      game = game.flag();
    } else if (!game.isOver) {
      final moves = legalMoves(game.position);
      final byComputer = switch (mode) {
        VsComputer(:final computerColour) => game.sideToMove == computerColour,
        TwoPlayer() => false,
      };
      game = game.play(
        moves[rng.nextInt(moves.length)],
        byComputer: byComputer,
      );
    }
  }
  time.advance(rng.nextInt(5000));
  return (game, time);
}

/// A valid v1 save of a short game, to corrupt one field at a time.
Map<String, Object?> _sample() {
  final time = FakeTime();
  var game = Game.start(
    const VsComputer(playerColour: white, step: Strength.casual, seed: 7),
    Timed.blitz,
    time: time.call,
  );
  for (final uci in ['e2e4', 'e7e5', 'g1f3', 'b8c6']) {
    time.advance(2000);
    game = game.play(
      Move.fromUci(game.position, uci),
      byComputer: game.sideToMove == black,
    );
  }
  return jsonDecode(jsonEncode(game.toJson())) as Map<String, Object?>;
}

/// [json] with [edit] applied to a deep copy.
Map<String, Object?> _edited(
  Map<String, Object?> json,
  void Function(Map<String, Object?> copy) edit,
) {
  final copy = jsonDecode(jsonEncode(json)) as Map<String, Object?>;
  edit(copy);
  return copy;
}

Map<String, Object?> _at(Map<String, Object?> json, String key) =>
    json[key]! as Map<String, Object?>;

Matcher _refused(GameLoadFailure reason, {int? ply}) => throwsA(
  isA<GameLoadError>()
      .having((e) => e.reason, 'reason', reason)
      .having((e) => e.ply, 'ply', ply),
);

const _fixturePath = 'test/fixtures/game_v1.json';

void main() {
  group('round trip', () {
    test('200 random games come back exactly and re-serialise identically', () {
      for (var seed = 0; seed < 200; seed++) {
        final (game, time) = playout(seed);
        Game? loaded;
        Object? refusal;
        try {
          loaded = reload(game, time);
        } on GameLoadError catch (e) {
          refusal = e;
        }
        expect(
          refusal,
          isNull,
          reason:
              'game-json: a saved game did not come back (playout $seed): '
              'the load was refused',
        );
        expect(
          differences(loaded!, game, time),
          isEmpty,
          reason: 'game-json: a saved game did not come back (playout $seed)',
        );
        expect(
          jsonEncode(loaded.toJson()),
          jsonEncode(game.toJson()),
          reason:
              'game-json: a saved game did not come back (playout $seed): '
              'it re-serialised differently',
        );
        if (game.canTakeBack) {
          expect(
            differences(loaded.takeBack(), game.takeBack(), time),
            isEmpty,
            reason:
                'game-json: a saved game did not come back (playout $seed): '
                'a takeback after loading restored something else',
          );
        }
      }
    }, tags: ['guard']);

    test('the playouts reach the cases the round trip must cover', () {
      final seen = <String>{};
      for (var seed = 0; seed < 200; seed++) {
        final (game, _) = playout(seed);
        seen.add(game.mode.runtimeType.toString());
        seen.add(game.clock.control is Timed ? 'timed' : 'untimed');
        seen.add(game.clock.phase.name);
        if (!game.options.takebackAllowed) seen.add('no takeback');
        switch (game.status) {
          case Win(:final reason) || Draw(:final reason):
            seen.add(reason.name);
          case Ongoing():
            seen.add('ongoing');
        }
      }
      expect(
        seen,
        containsAll([
          'VsComputer',
          'TwoPlayer',
          'timed',
          'untimed',
          'notStarted',
          'running',
          'paused',
          'ended',
          'no takeback',
          'ongoing',
          'resignation',
          'agreement',
          'flag',
        ]),
      );
    });

    test('the layout: fixed key order, names, an unsigned decimal seed', () {
      final time = FakeTime();
      final game = Game.start(
        const VsComputer(playerColour: black, step: Strength.master, seed: -1),
        const Untimed(),
        time: time.call,
      );
      expect(
        jsonEncode(game.toJson()),
        '{"version":1,'
        '"mode":{"type":"vsComputer","playerColour":"black"},'
        '"options":{"step":"master","seed":"18446744073709551615",'
        '"timeControl":null,"takebackAllowed":true},'
        '"startFen":"${Position.initialFen}",'
        '"moves":[],'
        '"clock":{"whiteMs":0,"blackMs":0,"snapshots":[[0,0]]},'
        '"result":{"outcome":"ongoing"}}',
      );
      expect((reload(game, time).mode as VsComputer).seed, -1);

      final twoPlayer = Game.start(
        const TwoPlayer(),
        Timed(7, 3),
        options: const GameOptions(takebackAllowed: false),
        time: time.call,
      ).toJson();
      expect(twoPlayer['mode'], {'type': 'twoPlayers'});
      expect(twoPlayer['options'], {
        'timeControl': {'minutes': 7, 'incrementSeconds': 3},
        'takebackAllowed': false,
      });
    });

    test('seeds keep all 64 bits, the top one included', () {
      for (final seed in [0, 1, 0x7fffffffffffffff, 0x8000000000000000, -2]) {
        final time = FakeTime();
        final game = Game.start(
          VsComputer(playerColour: white, step: Strength.club, seed: seed),
          const Untimed(),
          time: time.call,
        );
        final text = (_at(game.toJson(), 'options'))['seed']! as String;
        expect(BigInt.parse(text), BigInt.from(seed).toUnsigned(64));
        expect((reload(game, time).mode as VsComputer).seed, seed);
      }
    });

    test('a running clock is saved as it reads and comes back paused', () {
      final time = FakeTime();
      var game = Game.start(const TwoPlayer(), Timed.blitz, time: time.call);
      game = game.play(Move.fromUci(game.position, 'e2e4'));
      time.advance(12345);
      final loaded = reload(game, time);
      expect(loaded.clock.phase, ClockPhase.paused);
      expect(loaded.remaining(black), 300000 - 12345);
      time.advance(60000);
      expect(
        loaded.remaining(black),
        300000 - 12345,
        reason: 'game-json: a restored clock ran before the player resumed',
      );
    });
  });

  group('the frozen v1 fixture', () {
    final text = File(_fixturePath).readAsStringSync();

    test('keeps loading, as it was saved', () {
      final time = FakeTime();
      final game = Game.fromJson(
        jsonDecode(text) as Map<String, Object?>,
        time: time.call,
      );
      expect(
        game.mode,
        const VsComputer(
          playerColour: white,
          step: Strength.club,
          seed: 0xfedcba9876543210,
        ),
      );
      expect(
        game.position.toFen(),
        '1rbq1rk1/1p2bppp/p3pn2/8/8/5N2/PPPPBPPP/RNBQ1RK1 b - - 5 8',
      );
      expect(game.status, const Ongoing(inCheck: false));
      expect(game.clock.control, Timed.rapid);
      expect(game.clock.phase, ClockPhase.paused);
      expect(game.remaining(white), 610100);
      expect(game.remaining(black), 625600);
      expect(game.history[7].clock.whiteMs, 606600);
      final moves = game.moves;
      expect(moves.where((m) => m.isEnPassant), hasLength(1));
      expect(moves.where((m) => m.isCastling), hasLength(2));
      expect(moves.where((m) => m.promotion != null), hasLength(1));
    });

    test('re-serialises byte for byte', () {
      final game = Game.fromJson(
        jsonDecode(text) as Map<String, Object?>,
        time: FakeTime().call,
      );
      expect(
        '${const JsonEncoder.withIndent('  ').convert(game.toJson())}\n',
        text,
      );
    });
  });

  group('refusals', () {
    final sample = _sample();

    test('the sample itself loads', () {
      expect(Game.fromJson(sample).moves, hasLength(4));
    });

    test('a missing, unknown or newer version', () {
      expect(
        () => Game.fromJson(_edited(sample, (j) => j.remove('version'))),
        _refused(GameLoadFailure.missingVersion),
      );
      for (final version in ['1', 1.0, 0, -1, true]) {
        expect(
          () => Game.fromJson(_edited(sample, (j) => j['version'] = version)),
          _refused(GameLoadFailure.unknownVersion),
          reason: 'version $version',
        );
      }
      expect(
        () => Game.fromJson(_edited(sample, (j) => j['version'] = 2)),
        _refused(GameLoadFailure.newerVersion),
      );
    });

    test('an illegal move, with its ply', () {
      expect(
        () => Game.fromJson(
          _edited(sample, (j) => (j['moves']! as List)[2] = 'e1e3'),
        ),
        _refused(GameLoadFailure.illegalMove, ply: 2),
      );
      expect(
        () => Game.fromJson(
          _edited(sample, (j) => (j['moves']! as List)[0] = 'E2E4'),
        ),
        _refused(GameLoadFailure.illegalMove, ply: 0),
      );
    });

    test('a FEN that does not parse', () {
      expect(
        () => Game.fromJson(_edited(sample, (j) => j['startFen'] = '8/8/8')),
        _refused(GameLoadFailure.invalidFen),
      );
    });

    test('moves after the game ended', () {
      final time = FakeTime();
      var mate = Game.start(
        const TwoPlayer(),
        const Untimed(),
        time: time.call,
      );
      for (final uci in ['f2f3', 'e7e5', 'g2g4', 'd8h4']) {
        mate = mate.play(Move.fromUci(mate.position, uci));
      }
      final json =
          jsonDecode(jsonEncode(mate.toJson())) as Map<String, Object?>;
      expect(
        () => Game.fromJson(
          _edited(json, (j) => (j['moves']! as List).add('e1f2')),
        ),
        _refused(GameLoadFailure.movesAfterGameOver, ply: 4),
      );
    });

    test('a result the moves contradict', () {
      for (final result in [
        {'outcome': 'win', 'winner': 'white', 'reason': 'checkmate'},
        {'outcome': 'draw', 'reason': 'stalemate'},
        {'outcome': 'win', 'winner': 'white', 'reason': 'resignation'},
        {'outcome': 'win', 'winner': 'white', 'reason': 'flag'},
        {'outcome': 'win', 'winner': 'white', 'reason': 'agreement'},
      ]) {
        expect(
          () => Game.fromJson(_edited(sample, (j) => j['result'] = result)),
          _refused(GameLoadFailure.resultContradicted),
          reason: '$result',
        );
      }
      // The complement: the player (White) may resign against the computer,
      // and the players may agree a draw once each has moved.
      final resigned = Game.fromJson(
        _edited(
          sample,
          (j) => j['result'] = {
            'outcome': 'win',
            'winner': 'black',
            'reason': 'resignation',
          },
        ),
      );
      expect(resigned.status, const Win(black, GameEndReason.resignation));
      expect(resigned.clock.phase, ClockPhase.ended);
      final agreed = Game.fromJson(
        _edited(
          sample,
          (j) => j['result'] = {'outcome': 'draw', 'reason': 'agreement'},
        ),
      );
      expect(agreed.status, const Draw(GameEndReason.agreement));
    });

    test('clocks the moves could not have produced', () {
      final cases = <String, void Function(Map<String, Object?>)>{
        'no clock': (j) => j.remove('clock'),
        'a snapshot short': (j) =>
            (_at(j, 'clock')['snapshots']! as List).removeLast(),
        'the start is not the full time': (j) =>
            (_at(j, 'clock')['snapshots']! as List)[0] = [1000, 300000],
        'a waiting clock moved': (j) =>
            ((_at(j, 'clock')['snapshots']! as List)[2] as List)[0] = 1,
        'the mover gained time': (j) =>
            ((_at(j, 'clock')['snapshots']! as List)[2] as List)[1] = 400000,
        'a negative reading': (j) => _at(j, 'clock')['whiteMs'] = -5,
        'the live clock gained time': (j) =>
            _at(j, 'clock')['whiteMs'] = 999999,
        'a time control out of range': (j) => _at(j, 'options')['timeControl'] =
            {'minutes': 91, 'incrementSeconds': 0},
        'an untimed game with readings': (j) =>
            _at(j, 'options')['timeControl'] = null,
      };
      for (final MapEntry(key: name, value: edit) in cases.entries) {
        expect(
          () => Game.fromJson(_edited(sample, edit)),
          throwsA(
            isA<GameLoadError>().having(
              (e) => e.reason,
              'reason',
              anyOf(GameLoadFailure.invalidClock, GameLoadFailure.malformed),
            ),
          ),
          reason: name,
        );
      }
    });

    test('mistyped fields and bad names are malformed', () {
      final cases = <String, void Function(Map<String, Object?>)>{
        'mode type': (j) => _at(j, 'mode')['type'] = 'online',
        'colour': (j) => _at(j, 'mode')['playerColour'] = 'red',
        'step': (j) => _at(j, 'options')['step'] = 'grandmaster',
        'seed sign': (j) => _at(j, 'options')['seed'] = '-1',
        'seed 2^64': (j) => _at(j, 'options')['seed'] = '18446744073709551616',
        'seed a number': (j) => _at(j, 'options')['seed'] = 7,
        'takeback': (j) => _at(j, 'options')['takebackAllowed'] = 'yes',
        'moves': (j) => j['moves'] = 'e2e4',
        'a move': (j) => (j['moves']! as List)[1] = 5,
        'outcome': (j) => _at(j, 'result')['outcome'] = 'lost',
      };
      for (final MapEntry(key: name, value: edit) in cases.entries) {
        expect(
          () => Game.fromJson(_edited(sample, edit)),
          _refused(GameLoadFailure.malformed),
          reason: name,
        );
      }
    });

    test('unknown fields are ignored, at the top and nested', () {
      final loaded = Game.fromJson(
        _edited(sample, (j) {
          j['comment'] = 'from a later build';
          _at(j, 'mode')['theme'] = 'wood';
          _at(j, 'clock')['extra'] = [1, 2];
        }),
      );
      expect(loaded.moves, hasLength(4));
    });

    test('no corruption of any field crashes or half-loads', () {
      final fixture = jsonDecode(
        File(_fixturePath).readAsStringSync(),
      ) as Map<String, Object?>;
      const replacements = <Object?>[null, 'x', -1, 0, 2.5, true, [], {}];
      var loaded = 0, refused = 0;
      for (final path in _paths(fixture, const [])) {
        for (final replacement in [...replacements, _remove]) {
          final copy = _edited(fixture, (j) => _set(j, path, replacement));
          // Anything but a whole game or a GameLoadError fails the test.
          try {
            expect(Game.fromJson(copy), isA<Game>());
            loaded++;
          } on GameLoadError {
            refused++;
          }
        }
      }
      expect(refused, greaterThan(loaded));
    });
  });
}

/// Stands for "remove this key or element" among the corruptions.
const _remove = #remove;

/// Every key or index path into [node], [prefix] first.
List<List<Object>> _paths(Object? node, List<Object> prefix) => [
  if (prefix.isNotEmpty) prefix,
  if (node is Map<String, Object?>)
    for (final key in node.keys) ..._paths(node[key], [...prefix, key]),
  if (node is List<Object?>)
    for (var i = 0; i < node.length; i++) ..._paths(node[i], [...prefix, i]),
];

/// Sets (or, for [_remove], removes) the value at [path] in [root].
void _set(Object root, List<Object> path, Object? value) {
  Object node = root;
  for (final step in path.take(path.length - 1)) {
    node = switch (node) {
      final Map<String, Object?> map => map[step as String]!,
      final List<Object?> list => list[step as int]!,
      _ => throw StateError('no container at $step'),
    };
  }
  final last = path.last;
  switch (node) {
    case final Map<String, Object?> map:
      value == _remove ? map.remove(last) : map[last as String] = value;
    case final List<Object?> list:
      value == _remove ? list.removeAt(last as int) : list[last as int] = value;
  }
}
