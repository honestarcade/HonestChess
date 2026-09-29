// Statistics recorded from the controller's events over real engine games
// (#82): which games count, and that each counts once. The complements —
// what must NOT be counted — are asserted beside every count.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:honest_chess/data/app_store.dart';
import 'package:honest_chess/data/game_saves.dart';
import 'package:honest_chess/data/play_mode.dart';
import 'package:honest_chess/data/recorded_state.dart';
import 'package:honest_chess/data/stats.dart';
import 'package:honest_chess/data/stats_listener.dart';
import 'package:honest_chess/engine/engine.dart';
import 'package:honest_chess/ui/game/defaults.dart';
import 'package:honest_chess/ui/game/game_controller.dart';

/// The test's time source.
var now = 0;
int time() => now;

const blitzMs = 5 * 60 * 1000;

/// A memory store that notes every write.
class CountingStore extends AppStore {
  CountingStore() : super.memory();

  final writes = <StoreDoc>[];

  int writesTo(StoreDoc doc) => writes.where((d) => d == doc).length;

  @override
  Future<bool> write(StoreDoc doc, Map<String, Object?> data) {
    writes.add(doc);
    return super.write(doc, data);
  }
}

GameSetup vsComputer({
  Strength step = Strength.club,
  TimeControl timeControl = Timed.blitz,
}) => (
  mode: GameKind.vsComputer,
  strength: step,
  colour: Colour.white,
  timeControl: timeControl,
);

GameSetup twoPlayers([TimeControl timeControl = Timed.blitz]) => (
  mode: GameKind.twoPlayers,
  strength: null,
  colour: null,
  timeControl: timeControl,
);

/// The app's objects as the root wires them, over [store].
class Rig {
  Rig(this.store) {
    var ids = 0;
    controller = GameController.idle(
      now: time,
      newGameId: () => (++ids).toRadixString(16).padLeft(16, '0'),
    );
    saves = GameSaves(store, time: time)..attach(controller.events);
    recorder = StatsRecorder(store: store, nowMillis: () => 1759104000000);
    listener = StatsListener(
      controller: controller,
      recorder: recorder,
      saves: saves,
    );
    addTearDown(() {
      listener.dispose();
      recorder.dispose();
      saves.dispose();
      controller.dispose();
    });
  }

  final AppStore store;
  late final GameController controller;
  late final GameSaves saves;
  late final StatsRecorder recorder;
  late final StatsListener listener;

  ComputerStats get computer => recorder.document.computer;
  TwoPlayerStats get two => recorder.document.two;

  /// Launch: the saved games and the statistics read.
  Future<void> launch() async {
    await recorder.load();
    await saves.loadAll();
    await settle();
  }

  /// Everything queued has been saved, recorded and written.
  Future<void> settle() async {
    await saves.flush();
    await recorder.idle;
    await saves.flush();
  }

  void play(String uci) {
    now += 1000;
    expect(
      controller.move(
        Square.parse(uci.substring(0, 2)),
        Square.parse(uci.substring(2, 4)),
      ),
      isTrue,
      reason: 'test: $uci is played',
    );
  }

  /// Your move, then the computer's clock (it never moves here) runs out.
  Future<void> winOnTime() async {
    play('e2e4');
    now += blitzMs + 1;
    expect(controller.checkFlag(), isTrue);
    expect(controller.game.status, const Win(Colour.white, GameEndReason.flag));
    await settle();
  }
}

Future<Rig> launched([AppStore? store]) async {
  final rig = Rig(store ?? CountingStore());
  await rig.launch();
  return rig;
}

/// A saved, unfinished game against the computer, as the store holds it.
AppStore storeWithSavedComputerGame({
  required bool started,
  bool outcome = false,
}) {
  var game = Game.start(
    const VsComputer(
      playerColour: Colour.white,
      step: Strength.strong,
      seed: 7,
    ),
    Timed.rapid,
    time: time,
  );
  if (started) {
    game = game.play(Move.fromUci(game.position, 'e2e4'));
    game = game.play(Move.fromUci(game.position, 'e7e5'), byComputer: true);
  }
  return CountingStore()..putRaw(
    StoreDoc.gameComputer,
    jsonEncode({
      'format': 1,
      'data': {
        'game': game.toJson(),
        'recorded': {
          'id': 'abcdefabcdefabcd',
          'started': started,
          'outcome': outcome,
        },
      },
    }),
  );
}

void main() {
  setUp(() => now = 0);

  group('vs Computer', () {
    test('a game with no move of yours, then a new game: nothing', () async {
      final rig = await launched();
      await rig.controller.newGame(vsComputer());
      await rig.controller.newGame(vsComputer());
      await rig.settle();
      expect(rig.computer.played, 0, reason: 'stats: an unstarted game');
      expect(rig.computer.lost, 0);
      expect(
        (rig.store as CountingStore).writesTo(StoreDoc.stats),
        0,
        reason: 'stats: nothing counted, nothing written',
      );
    });

    test('a resignation before your first move is one loss', () async {
      final rig = await launched();
      await rig.controller.newGame(vsComputer());
      expect(rig.controller.resign(), isTrue);
      await rig.settle();
      expect(rig.computer.toJson(), {
        ...const ComputerStats().toJson(),
        'played': 1,
        'lost': 1,
        'steps': {
          for (final s in Strength.values)
            s.name: {'played': s == Strength.club ? 1 : 0, 'won': 0},
        },
      });
    });

    test('one move, then Restart: played 1, lost 1, streak 0', () async {
      final rig = await launched();
      await rig.controller.newGame(vsComputer());
      await rig.winOnTime();
      expect(rig.computer.streak, 1);
      await rig.controller.newGame(vsComputer());
      rig.play('d2d4');
      expect(await rig.controller.restart(), isTrue);
      await rig.settle();
      expect(rig.computer.played, 2);
      expect(rig.computer.lost, 1, reason: 'stats: quitting is a loss');
      expect(rig.computer.won, 1);
      expect(rig.computer.streak, 0, reason: 'stats: the loss ends it');
      expect(rig.computer.longestMoves, 1);
      expect(rig.controller.game.moves, isEmpty);
    });

    test('Restart waits for the loss to be written; the old game is frozen '
        'meanwhile', () async {
      final rig = await launched();
      await rig.controller.newGame(vsComputer());
      rig.play('e2e4');
      final before = rig.controller.game;
      final restarting = rig.controller.restart();
      expect(
        rig.controller.inputLocked,
        isTrue,
        reason: 'controller: frozen while replacing',
      );
      expect(identical(rig.controller.game.history, before.history), isTrue);
      now += blitzMs + 1;
      expect(
        rig.controller.checkFlag(),
        isFalse,
        reason: 'controller: a frozen game cannot flag',
      );
      expect(
        await rig.controller.newGame(twoPlayers()),
        isFalse,
        reason: 'controller: the first replacement wins',
      );
      expect(await restarting, isTrue);
      expect(rig.computer.lost, 1);
      expect(rig.controller.game.mode, isA<VsComputer>());
      expect(rig.controller.game.moves, isEmpty);
    });

    test('three wins make a streak of 3; a draw ends it', () async {
      final rig = await launched();
      for (var i = 1; i <= 3; i++) {
        await rig.controller.newGame(vsComputer());
        await rig.winOnTime();
        expect(rig.computer.streak, i);
      }
      // Your lone king: the computer's flag falls, and it is a draw.
      final game = Game.start(
        const VsComputer(
          playerColour: Colour.white,
          step: Strength.club,
          seed: 3,
        ),
        Timed.blitz,
        fen: '4k3/4p3/8/8/8/8/8/4K3 w - - 0 1',
        time: time,
      );
      expect(rig.controller.restore(game), isTrue);
      rig.controller.resume();
      rig.play('e1e2');
      now += blitzMs + 1;
      expect(rig.controller.checkFlag(), isTrue);
      await rig.settle();
      expect(rig.computer.drawn, 1);
      expect(rig.computer.streak, 0, reason: 'stats: a draw ends the streak');
      expect(rig.computer.won, 3);
      expect(rig.computer.played, 4);
    });

    test(
      'the computer\'s flag and your resignation are each counted once',
      () async {
        final rig = await launched();
        await rig.controller.newGame(vsComputer());
        await rig.winOnTime();
        await rig.controller.newGame(vsComputer());
        rig.play('e2e4');
        rig.controller.resign();
        await rig.settle();
        // A rematch after a finished game is no abandon.
        await rig.controller.restart();
        await rig.settle();
        expect(
          (rig.computer.played, rig.computer.won, rig.computer.lost),
          (2, 1, 1),
        );
        expect(rig.recorder.document.recentIds, [
          '0000000000000001',
          '0000000000000002',
        ]);
      },
    );

    test('only the game\'s own step moves', () async {
      final rig = await launched();
      await rig.controller.newGame(vsComputer(step: Strength.strong));
      await rig.winOnTime();
      for (final step in Strength.values) {
        expect(
          (rig.computer.steps[step]!.played, rig.computer.steps[step]!.won),
          step == Strength.strong ? (1, 1) : (0, 0),
          reason: 'stats: ${step.name}',
        );
      }
    });
  });

  group('Two players', () {
    test('a mate by Black is a Black win', () async {
      final rig = await launched();
      await rig.controller.newGame(twoPlayers(const Untimed()));
      for (final uci in ['f2f3', 'e7e5', 'g2g4', 'd8h4']) {
        rig.play(uci);
      }
      await rig.settle();
      expect(rig.two.toJson(), {
        ...const TwoPlayerStats().toJson(),
        'played': 1,
        'blackWins': 1,
        'longestMoves': 2,
        'clocks': {
          for (final c in StatsClock.values)
            c.name: {'played': c == StatsClock.untimed ? 1 : 0},
        },
      });
      expect(rig.computer.played, 0, reason: 'stats: the other mode');
    });

    test('an agreed draw is a draw, under its clock', () async {
      final rig = await launched();
      await rig.controller.newGame(twoPlayers(Timed(15, 10)));
      rig.play('e2e4');
      rig.play('e7e5');
      rig.controller.pause();
      expect(await rig.controller.offerDraw(), isTrue);
      await rig.settle();
      expect((rig.two.played, rig.two.drawn), (1, 1));
      expect((rig.two.whiteWins, rig.two.blackWins), (0, 0));
      expect(rig.two.clocks[StatsClock.custom], 1);
      expect(rig.two.longestMoves, 1);
    });

    test('a game abandoned by New after ten moves: nothing', () async {
      final rig = await launched();
      await rig.controller.newGame(twoPlayers());
      for (final uci in [
        'e2e4', 'e7e5', 'g1f3', 'b8c6', 'f1b5', 'a7a6', 'b5a4', 'g8f6', //
        'e1g1', 'f8e7', 'f1e1', 'b7b5', 'a4b3', 'd7d6', 'c2c3', 'e8g8',
        'h2h3', 'c6b8', 'd2d4', 'b8d7',
      ]) {
        rig.play(uci);
      }
      expect(await rig.controller.newGame(twoPlayers()), isTrue);
      await rig.settle();
      expect(rig.two.played, 0, reason: 'stats: an abandoned two-player game');
      expect(
        (rig.store as CountingStore).writesTo(StoreDoc.stats),
        0,
        reason: 'stats: nothing counted, nothing written',
      );
    });

    test('games count per time control; the longest is kept', () async {
      final rig = await launched();
      for (final (control, moves) in [
        (Timed.blitz, ['f2f3', 'e7e5', 'g2g4', 'd8h4']),
        (Timed(5, 0), ['e2e4', 'e7e5', 'd1h5', 'b8c6', 'f1c4', 'g8f6', 'h5f7']),
        (Timed.classical, ['f2f3', 'e7e5', 'g2g4', 'd8h4']),
      ]) {
        await rig.controller.newGame(twoPlayers(control));
        moves.forEach(rig.play);
        await rig.settle();
      }
      expect(
        {for (final c in StatsClock.values) c: rig.two.clocks[c]},
        {
          StatsClock.untimed: 0,
          StatsClock.blitz: 2,
          StatsClock.rapid: 0,
          StatsClock.classical: 1,
          StatsClock.custom: 0,
        },
      );
      expect((rig.two.whiteWins, rig.two.blackWins), (1, 2));
      expect(rig.two.longestMoves, 4);
    });
  });

  group('exactly once', () {
    test('the same id recorded twice counts once', () async {
      final rig = await launched();
      await rig.controller.newGame(vsComputer());
      rig.play('e2e4');
      rig.controller.resign();
      final game = rig.controller.game;
      final state = RecordedState.fromJson(rig.controller.recorded, game);
      await rig.settle();
      expect(rig.computer.lost, 1);
      // A crash between the statistics write and the save: the end stage
      // runs again for the same game at the next launch.
      expect(
        await rig.recorder.recordResult(game, state),
        RecordOutcome.duplicate,
      );
      expect(rig.computer.lost, 1, reason: 'stats: a second record');
      expect(rig.computer.played, 1);
    });

    test(
      'a finished game reloaded counts once, and not with outcome set',
      () async {
        for (final outcome in [false, true]) {
          var game = Game.start(
            const VsComputer(
              playerColour: Colour.black,
              step: Strength.casual,
              seed: 9,
            ),
            const Untimed(),
            time: time,
          );
          for (final uci in ['f2f3', 'e7e5', 'g2g4', 'd8h4']) {
            game = game.play(
              Move.fromUci(game.position, uci),
              byComputer: game.sideToMove == Colour.white,
            );
          }
          final store = CountingStore()
            ..putRaw(
              StoreDoc.gameComputer,
              jsonEncode({
                'format': 1,
                'data': {
                  'game': game.toJson(),
                  'recorded': {
                    'id': '1111222233334444',
                    'started': true,
                    'outcome': outcome,
                  },
                },
              }),
            );
          final rig = await launched(store);
          expect(
            rig.computer.won,
            outcome ? 0 : 1,
            reason: 'stats: outcome $outcome at load',
          );
          expect(rig.computer.played, outcome ? 0 : 1);
          expect(store.rawText(StoreDoc.gameComputer), isNull);
        }
      },
    );

    test('an ended game taken back and won keeps its first result', () async {
      final rig = await launched();
      final game = Game.start(
        const VsComputer(
          playerColour: Colour.white,
          step: Strength.club,
          seed: 5,
        ),
        const Untimed(),
        fen: '7k/5K2/8/8/8/8/8/6Q1 w - - 0 1',
        time: time,
      );
      expect(rig.controller.restore(game), isTrue);
      rig.controller.resume();
      rig.play('g1g6');
      expect(rig.controller.game.status, const Draw(GameEndReason.stalemate));
      await rig.settle();
      expect(rig.computer.drawn, 1);
      expect(rig.controller.recorded['outcome'], isTrue);
      expect(rig.controller.takeBack(), isTrue);
      await rig.settle();
      expect(
        rig.saves.recorded(PlayMode.computer)['outcome'],
        isTrue,
        reason: 'saves: the reopened game carries its counted flag',
      );
      rig.play('g1g7');
      expect(rig.controller.game.status, isA<Win>());
      await rig.settle();
      expect(rig.computer.won, 0, reason: 'stats: the first result stands');
      expect((rig.computer.played, rig.computer.drawn), (1, 1));
      // Nor does quitting it afterwards count.
      rig.controller.takeBack();
      await rig.controller.restart();
      await rig.settle();
      expect(rig.computer.lost, 0);
    });

    test('a saved, started computer game displaced by a new one while the '
        'board held two players is one loss', () async {
      final rig = await launched();
      await rig.controller.newGame(vsComputer());
      rig.play('e2e4');
      await rig.controller.newGame(twoPlayers());
      rig.play('e2e4');
      await rig.settle();
      expect(rig.computer.played, 0, reason: 'stats: the other mode is kept');
      await rig.controller.newGame(vsComputer());
      await rig.settle();
      expect((rig.computer.played, rig.computer.lost), (1, 1));
      expect(rig.two.played, 0, reason: 'stats: the two-player game is not');
    });

    for (final (started, outcome, counted) in [
      (true, false, true),
      (true, true, false),
      (false, false, false),
    ]) {
      test('idle at launch, a new computer game over a saved one '
          '(started $started, outcome $outcome)', () async {
        final rig = await launched(
          storeWithSavedComputerGame(started: started, outcome: outcome),
        );
        expect(rig.listener.isAbandonable(PlayMode.computer), counted);
        expect(await rig.controller.newGame(vsComputer()), isTrue);
        await rig.settle();
        expect((
          rig.computer.played,
          rig.computer.lost,
        ), counted ? (1, 1) : (0, 0));
        expect(
          rig.computer.steps[Strength.strong]!.played,
          counted ? 1 : 0,
          reason: 'stats: the saved game\'s own step',
        );
      });
    }

    test(
      'a new two-player game leaves the saved computer game alone',
      () async {
        final rig = await launched(storeWithSavedComputerGame(started: true));
        await rig.controller.newGame(twoPlayers());
        await rig.settle();
        expect(rig.computer.played, 0);
        expect(rig.saves.load(PlayMode.computer), isNotNull);
      },
    );
  });

  group('reset', () {
    test(
      'clears both modes; a game in progress counts once, in full',
      () async {
        final rig = await launched();
        await rig.controller.newGame(vsComputer());
        await rig.winOnTime();
        await rig.controller.newGame(twoPlayers(const Untimed()));
        for (final uci in ['f2f3', 'e7e5', 'g2g4', 'd8h4']) {
          rig.play(uci);
        }
        await rig.controller.newGame(vsComputer(step: Strength.beginner));
        rig.play('e2e4');
        await rig.settle();
        await rig.recorder.resetAll();
        expect(rig.computer.toJson(), const ComputerStats().toJson());
        expect(rig.two.toJson(), const TwoPlayerStats().toJson());
        expect(rig.recorder.document.resetAt, 1759104000000);

        now += blitzMs + 1;
        expect(rig.controller.checkFlag(), isTrue);
        await rig.settle();
        expect(
          (rig.computer.played, rig.computer.won, rig.computer.streak),
          (1, 1, 1),
        );
        expect(rig.computer.steps[Strength.beginner]!.won, 1);
        expect(rig.computer.longestMoves, 1);
      },
    );
  });
}
