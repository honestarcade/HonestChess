// The saved games (#81): one document per mode, written on every change
// event and deleted when the game ends. The complements matter as much as
// the saves: the other mode's document is never touched, an ongoing game's
// document is never deleted, a restore writes nothing, and a refused
// document loads as nothing at all.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:honest_chess/data/app_store.dart';
import 'package:honest_chess/data/game_event.dart';
import 'package:honest_chess/data/game_saves.dart';
import 'package:honest_chess/data/play_mode.dart';
import 'package:honest_chess/engine/engine.dart';
import 'package:honest_chess/ui/game/defaults.dart';
import 'package:honest_chess/ui/game/game_controller.dart';

const vsClub = VsComputer(
  playerColour: Colour.white,
  step: Strength.club,
  seed: 0x1234abcd,
);

/// The test's time source.
var now = 0;
int time() => now;

Game playAll(Game game, List<String> ucis) {
  for (final uci in ucis) {
    final byComputer = switch (game.mode) {
      VsComputer(:final computerColour) => game.sideToMove == computerColour,
      TwoPlayer() => false,
    };
    now += 1500;
    game = game.play(Move.fromUci(game.position, uci), byComputer: byComputer);
  }
  return game;
}

Game computerGame([List<String> ucis = const ['e2e4', 'e7e5', 'g1f3']]) =>
    playAll(Game.start(vsClub, Timed.rapid, time: time), ucis);

Game twoPlayerGame([List<String> ucis = const ['d2d4', 'd7d5']]) =>
    playAll(Game.start(const TwoPlayer(), Timed.blitz, time: time), ucis);

/// The fool's mate: Black mates on its second move.
Game mated(GameMode mode) => playAll(Game.start(mode, const Untimed()), [
  'f2f3',
  'e7e5',
  'g2g4',
  'd8h4',
]);

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

Map<String, Object?> documentOf(AppStore store, StoreDoc doc) {
  final text = store.rawText(doc);
  expect(text, isNotNull, reason: 'test: ${doc.name} is stored');
  final envelope = jsonDecode(text!) as Map<String, Object?>;
  return envelope['data']! as Map<String, Object?>;
}

void main() {
  setUp(() => now = 0);

  group('saving', () {
    test('a save after each kind of change from the controller', () async {
      final store = CountingStore();
      final saves = GameSaves(store, time: time);
      final controller = GameController.idle(now: time);
      saves.attach(controller.events);
      addTearDown(() {
        saves.dispose();
        controller.dispose();
      });

      final writes = <String>[];
      Future<void> step(String what, void Function() change) async {
        final before = store.writesTo(StoreDoc.gameTwo);
        change();
        await saves.flush();
        expect(
          store.writesTo(StoreDoc.gameTwo),
          before + 1,
          reason: 'saves: $what writes game-two once',
        );
        writes.add(what);
        final saved = Game.fromJson(
          documentOf(store, StoreDoc.gameTwo)['game']! as Map<String, Object?>,
          time: time,
        );
        expect(
          saved.moves.map((m) => m.toUci()),
          controller.game.moves.map((m) => m.toUci()),
          reason: 'saves: after $what the saved moves are the live ones',
        );
      }

      expect(store.rawText(StoreDoc.gameTwo), isNull);
      await step('a new game', () {
        controller.newGame((
          mode: GameKind.twoPlayers,
          strength: null,
          colour: null,
          timeControl: Timed.blitz,
          rotate: false,
        ));
      });
      await step('a move', () {
        now += 1000;
        controller.move(Square.parse('e2'), Square.parse('e4'));
      });
      await step('the reply', () {
        now += 1000;
        controller.move(Square.parse('e7'), Square.parse('e5'));
      });
      await step('a takeback', controller.takeBack);
      await step('a pause', controller.pause);
      await step('a resume', controller.resume);
      expect(writes, hasLength(6));

      // A selection is no change of game: nothing is written.
      controller.tapSquare(Square.parse('d7'));
      now += 5000;
      await saves.flush();
      expect(
        store.writesTo(StoreDoc.gameTwo),
        6,
        reason: 'saves: a selection or a clock tick writes nothing',
      );
      expect(
        store.writesTo(StoreDoc.gameComputer),
        0,
        reason: 'saves: a two-player game never writes game-computer',
      );
    });

    test('a restore writes nothing and the next change saves', () async {
      final store = AppStore.memory();
      final saves = GameSaves(store, time: time);
      final controller = GameController.idle(now: time);
      saves.attach(controller.events);
      addTearDown(() {
        saves.dispose();
        controller.dispose();
      });
      final events = <GameEvent>[];
      controller.events.listen(events.add);

      expect(controller.restore(computerGame(), recorded: {'id': 'x'}), isTrue);
      await saves.flush();
      expect(events.map((e) => e.runtimeType), [GameRestored]);
      expect(
        store.rawText(StoreDoc.gameComputer),
        isNull,
        reason: 'saves: restoring is no change to save',
      );
      expect(store.rawText(StoreDoc.meta), isNull);

      controller.resume();
      await saves.flush();
      final doc = documentOf(store, StoreDoc.gameComputer);
      expect(doc['recorded'], {'id': 'x'}, reason: 'saves: recorded carried');
    });

    test('round trip through the store equals the game', () async {
      final store = AppStore.memory();
      final saves = GameSaves(store, time: time);
      final game = computerGame();
      await saves.save(game, {'id': 'abc', 'started': true});
      await saves.flush();

      final reopened = GameSaves(store, time: time);
      await reopened.loadAll();
      final loaded = reopened.load(PlayMode.computer)!;
      expect(loaded.position.toFen(), game.position.toFen());
      expect(
        [for (final s in loaded.history) s.position.toFen()],
        [for (final s in game.history) s.position.toFen()],
        reason: 'saves: the whole history comes back',
      );
      expect(loaded.moves, game.moves);
      expect(loaded.mode, game.mode, reason: 'saves: step, colour and seed');
      expect((loaded.mode as VsComputer).seed, vsClub.seed);
      expect(loaded.clock.control, Timed.rapid);
      for (final side in Colour.values) {
        expect(
          loaded.remaining(side),
          game.remaining(side),
          reason: 'saves: $side\'s clock',
        );
      }
      expect(loaded.status, game.status);
      expect(loaded.options.takebackAllowed, game.options.takebackAllowed);
      expect(reopened.recorded(PlayMode.computer), {
        'id': 'abc',
        'started': true,
      });
      expect(reopened.offered, (
        mode: PlayMode.computer,
        step: Strength.club,
        fullmove: 2,
        sideToMove: Colour.black,
      ));
    });

    test(
      'saving a two-player game leaves game-computer byte-identical',
      () async {
        final store = AppStore.memory();
        final saves = GameSaves(store, time: time);
        await saves.save(computerGame(), const {});
        await saves.flush();
        final computerText = store.rawText(StoreDoc.gameComputer);

        final events = StreamController<GameEvent>.broadcast(sync: true);
        saves.attach(events.stream);
        var two = Game.start(const TwoPlayer(), Timed.blitz, time: time);
        events.add(GameStarted(two, const {}));
        for (final uci in ['e2e4', 'c7c5', 'g1f3']) {
          two = playAll(two, [uci]);
          events.add(GameMoved(two, const {}));
        }
        events.add(GamePaused(two.pause(), const {}));
        events.add(GameEnded(mated(const TwoPlayer()), const {}));
        await saves.flush();

        expect(
          store.rawText(StoreDoc.gameComputer),
          computerText,
          reason: 'saves: the other mode\'s document is never written',
        );
        expect(
          saves.load(PlayMode.computer),
          isNotNull,
          reason: 'saves: the other mode\'s slot is kept',
        );
        await events.close();
        saves.dispose();
      },
    );

    test(
      'lastPlayed follows the last save; meta is written on change only',
      () async {
        final store = AppStore.memory();
        final saves = GameSaves(store, time: time);
        await saves.save(computerGame(), const {});
        await saves.flush();
        expect(documentOf(store, StoreDoc.meta), {'lastPlayed': 'computer'});
        expect(saves.offered?.mode, PlayMode.computer);

        await saves.save(twoPlayerGame(), const {});
        await saves.flush();
        expect(documentOf(store, StoreDoc.meta), {'lastPlayed': 'two'});
        expect(saves.offered?.mode, PlayMode.two);
        expect(saves.offered?.step, isNull);

        // A second save in the same mode leaves meta alone.
        store.putRaw(
          StoreDoc.meta,
          '{"format":1,"data":{"lastPlayed":"two"} }',
        );
        await saves.save(twoPlayerGame(['d2d4']), const {});
        await saves.flush();
        expect(
          store.rawText(StoreDoc.meta),
          '{"format":1,"data":{"lastPlayed":"two"} }',
          reason: 'saves: meta is rewritten only when the value changes',
        );

        await saves.save(computerGame(['e2e4']), const {});
        await saves.flush();
        expect(documentOf(store, StoreDoc.meta), {'lastPlayed': 'computer'});
        expect(saves.offered, (
          mode: PlayMode.computer,
          step: Strength.club,
          fullmove: 1,
          sideToMove: Colour.black,
        ));
      },
    );
  });

  group('launch', () {
    Future<GameSaves> launch(AppStore store) async {
      final saves = GameSaves(store, time: time);
      await saves.loadAll();
      return saves;
    }

    test(
      'lastPlayed picks the offered game; an empty slot falls back',
      () async {
        final store = AppStore.memory();
        final writer = GameSaves(store, time: time);
        await writer.save(computerGame(), const {});
        await writer.save(twoPlayerGame(), const {});
        await writer.flush();

        expect((await launch(store)).offered?.mode, PlayMode.two);

        store.putRaw(StoreDoc.meta, '{"format":1,"data":{"lastPlayed":"x"}}');
        expect(
          (await launch(store)).offered?.mode,
          PlayMode.computer,
          reason: 'saves: an unknown lastPlayed prefers the computer\'s game',
        );

        await store.delete(StoreDoc.meta);
        expect((await launch(store)).offered?.mode, PlayMode.computer);
        expect(
          store.corruptionNotices.value,
          isEmpty,
          reason: 'saves: meta raises no notice',
        );

        store.putRaw(StoreDoc.meta, '{"format":1,"data":{"lastPlayed":"two"}}');
        await store.delete(StoreDoc.gameTwo);
        expect(
          (await launch(store)).offered?.mode,
          PlayMode.computer,
          reason: 'saves: lastPlayed naming an empty slot offers the other',
        );

        await store.delete(StoreDoc.gameComputer);
        expect((await launch(store)).offered, isNull);
      },
    );

    test('a document with an illegal move list is quarantined and loads as '
        'none', () async {
      final store = AppStore.memory();
      final writer = GameSaves(store, time: time);
      await writer.save(computerGame(), const {});
      await writer.flush();
      final data = documentOf(store, StoreDoc.gameComputer);
      final game = Map<String, Object?>.of(
        data['game']! as Map<String, Object?>,
      )..['moves'] = ['e2e4', 'e7e5', 'e1e3'];
      store.putRaw(
        StoreDoc.gameComputer,
        jsonEncode({
          'format': 1,
          'data': {...data, 'game': game},
        }),
      );

      final saves = await launch(store);
      expect(saves.load(PlayMode.computer), isNull);
      expect(saves.offered, isNull, reason: 'saves: nothing half-loaded');
      expect(
        store.rawText(StoreDoc.gameComputer),
        isNull,
        reason: 'saves: the refused document is moved aside',
      );
      expect(store.corruptionNotices.value, {
        StoreDoc.gameComputer,
      }, reason: 'saves: the same notice as a damaged file');
    });

    test(
      'a game that is not a map, or in the wrong slot, is quarantined',
      () async {
        final store = AppStore.memory();
        store.putRaw(
          StoreDoc.gameComputer,
          '{"format":1,"data":{"game":[1,2],"recorded":{}}}',
        );
        final computerJson = computerGame().toJson();
        store.putRaw(
          StoreDoc.gameTwo,
          jsonEncode({
            'format': 1,
            'data': {'game': computerJson, 'recorded': <String, Object?>{}},
          }),
        );
        final saves = await launch(store);
        expect(saves.load(PlayMode.computer), isNull);
        expect(saves.load(PlayMode.two), isNull);
        expect(store.corruptionNotices.value, {
          StoreDoc.gameComputer,
          StoreDoc.gameTwo,
        });
      },
    );

    test(
      'a missing or mistyped recorded loads as empty, not quarantined',
      () async {
        final store = AppStore.memory();
        store.putRaw(
          StoreDoc.gameComputer,
          jsonEncode({
            'format': 1,
            'data': {'game': computerGame().toJson(), 'recorded': 'x'},
          }),
        );
        final saves = await launch(store);
        expect(saves.load(PlayMode.computer), isNotNull);
        expect(saves.recorded(PlayMode.computer), isEmpty);
        expect(store.corruptionNotices.value, isEmpty);
      },
    );

    test(
      'a finished game found at launch runs the end stages and is deleted',
      () async {
        final store = AppStore.memory();
        final finished = mated(vsClub);
        store.putRaw(
          StoreDoc.gameComputer,
          jsonEncode({
            'format': 1,
            'data': {
              'game': finished.toJson(),
              'recorded': {'id': 'f'},
            },
          }),
        );
        final saves = GameSaves(store, time: time);
        final seen = <(PlayMode, GameStatus, String)>[];
        saves.addEndStage((mode, game, recorded) async {
          seen.add((mode, game.status, jsonEncode(recorded)));
        });
        await saves.loadAll();
        expect(
          saves.offered,
          isNull,
          reason: 'saves: a finished game is never offered',
        );
        await saves.flush();
        expect(seen, [(PlayMode.computer, finished.status, '{"id":"f"}')]);
        expect(store.rawText(StoreDoc.gameComputer), isNull);
        expect(store.corruptionNotices.value, isEmpty);
      },
    );
  });

  group('ending', () {
    test('an ended game\'s document is deleted after the end stages; an '
        'ongoing one\'s never is', () async {
      final store = AppStore.memory();
      final saves = GameSaves(store, time: time);
      final controller = GameController.idle(now: time);
      saves.attach(controller.events);
      addTearDown(() {
        saves.dispose();
        controller.dispose();
      });
      final order = <String>[];
      saves.addEndStage((mode, game, recorded) async {
        order.add(
          'stage: ${store.rawText(mode.doc) == null ? 'gone' : 'present'}',
        );
      });

      controller.newGame((
        mode: GameKind.twoPlayers,
        strength: null,
        colour: null,
        timeControl: const Untimed(),
        rotate: false,
      ));
      for (final uci in ['f2f3', 'e7e5', 'g2g4']) {
        controller.move(
          Square.parse(uci.substring(0, 2)),
          Square.parse(uci.substring(2)),
        );
        await saves.flush();
        expect(
          store.rawText(StoreDoc.gameTwo),
          isNotNull,
          reason: 'saves: an ongoing game\'s document is never deleted',
        );
      }
      controller.move(Square.parse('d8'), Square.parse('h4'));
      expect(controller.game.isOver, isTrue);
      await saves.flush();
      expect(
        saves.offered,
        isNull,
        reason: 'saves: an ended game leaves its slot',
      );
      expect(order, ['stage: present'], reason: 'saves: stages before delete');
      expect(store.rawText(StoreDoc.gameTwo), isNull);
      expect(saves.load(PlayMode.two), isNull);

      // Takeback reopens it: live again, and saved again.
      expect(controller.takeBack(), isTrue);
      await saves.flush();
      expect(store.rawText(StoreDoc.gameTwo), isNotNull);
      expect(saves.offered?.mode, PlayMode.two);
    });

    test(
      'a failing end stage keeps the document; later stages do not run',
      () async {
        final store = AppStore.memory();
        final saves = GameSaves(store, time: time);
        await saves.save(twoPlayerGame(['f2f3', 'e7e5', 'g2g4']), const {});
        await saves.flush();
        var later = false;
        saves
          ..addEndStage((mode, game, recorded) async => throw StateError('x'))
          ..addEndStage((mode, game, recorded) async => later = true);
        final events = StreamController<GameEvent>.broadcast(sync: true);
        saves.attach(events.stream);
        events.add(GameEnded(mated(const TwoPlayer()), const {}));
        await saves.flush();
        expect(later, isFalse);
        expect(store.rawText(StoreDoc.gameTwo), isNotNull);
        expect(saves.offered, isNull, reason: 'saves: never offered even so');
        await events.close();
        saves.dispose();
      },
    );
  });

  group('controller events', () {
    test('an event raised while another is delivered comes right after it', () {
      final controller = GameController(now: time);
      addTearDown(controller.dispose);
      final seen = <Type>[];
      controller.events.listen((event) {
        seen.add(event.runtimeType);
        if (event is GamePaused) controller.resume();
      });
      controller.events.listen((event) => seen.add(event.runtimeType));
      controller.pause();
      expect(seen, [GamePaused, GamePaused, GameResumed, GameResumed]);
    });

    test('New over an unfinished game: abandoned before started', () {
      final controller = GameController(now: time)
        ..move(Square.parse('e2'), Square.parse('e4'));
      addTearDown(controller.dispose);
      final seen = <GameEvent>[];
      controller.events.listen(seen.add);
      controller.restart();
      expect(seen.map((e) => e.runtimeType), [GameAbandoned, GameStarted]);
      expect(seen.first.game.moves, hasLength(1));
      expect(seen.last.game.moves, isEmpty);
    });

    test('resign emits only ended; the idle controller refuses everything', () {
      final idle = GameController.idle(now: time);
      addTearDown(idle.dispose);
      final seen = <GameEvent>[];
      idle.events.listen(seen.add);
      expect(idle.isIdle, isTrue);
      expect([
        idle.pause(),
        idle.resign(),
        idle.takeBack(),
        idle.restart(),
      ], everyElement(isFalse));
      expect(() => idle.game, throwsStateError);
      expect(() => idle.state, throwsStateError);
      expect(seen, isEmpty, reason: 'controller: an idle one raises nothing');

      expect(
        idle.restore(mated(vsClub)),
        isFalse,
        reason: 'controller: a finished game is not restored',
      );
      expect(idle.isIdle, isTrue);

      idle.newGame((
        mode: GameKind.twoPlayers,
        strength: null,
        colour: null,
        timeControl: const Untimed(),
        rotate: false,
      ));
      seen.clear();
      idle.resign();
      expect(seen.map((e) => e.runtimeType), [GameEnded]);
    });
  });
}
