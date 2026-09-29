// The statistics document and recorder (#82) over plain values: cleaning on
// read, one fixed write order, the id list, and reset. What must NOT
// happen is asserted beside each rule: a counted id never counts again, a
// refused reset changes nothing, and loading writes nothing.
import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:honest_chess/data/app_store.dart';
import 'package:honest_chess/data/recorded_state.dart';
import 'package:honest_chess/data/stats.dart';
import 'package:honest_chess/engine/engine.dart';

String idOf(int n) => n.toRadixString(16).padLeft(16, '0');

const club = VsComputer(
  playerColour: Colour.white,
  step: Strength.club,
  seed: 1,
);

Game played(GameMode mode, List<String> ucis, {TimeControl? control}) {
  var game = Game.start(mode, control ?? const Untimed());
  for (final uci in ucis) {
    final byComputer = switch (game.mode) {
      VsComputer(:final computerColour) => game.sideToMove == computerColour,
      TwoPlayer() => false,
    };
    game = game.play(Move.fromUci(game.position, uci), byComputer: byComputer);
  }
  return game;
}

/// White (you, against [club]) is mated by the fool's mate.
Game foolsMate(GameMode mode) => played(mode, ['f2f3', 'e7e5', 'g2g4', 'd8h4']);

/// A memory store whose writes can be refused.
class RefusingStore extends AppStore {
  RefusingStore() : super.memory();

  bool refuse = false;
  var writes = 0;

  @override
  Future<bool> write(StoreDoc doc, Map<String, Object?> data) {
    writes++;
    return refuse ? Future.value(false) : super.write(doc, data);
  }
}

void main() {
  group('document', () {
    test('cleaning: bad values read as 0, results clamp to their games', () {
      final doc = StatsDocument.fromJson({
        'computer': {
          'played': 3,
          'won': 9,
          'drawn': -1,
          'lost': 2.0,
          'streak': 7,
          'longestMoves': 'x',
          'steps': {
            'club': {'played': 2, 'won': 5},
            'master': 'nope',
          },
          'extra': 1,
        },
        'two': {
          'played': 1,
          'whiteWins': 4,
          'blackWins': null,
          'drawn': true,
          'longestMoves': 88,
          'clocks': {
            'blitz': {'played': 2},
            'custom': {'played': -3},
            'weird': {'played': 9},
          },
        },
        'recentIds': [
          idOf(1),
          'NOT-AN-ID',
          idOf(2),
          idOf(1),
          42,
          'ABCDEFABCDEFABCD',
        ],
        'resetAt': -5,
        'unknown': {'a': 1},
      });
      final c = doc.computer;
      expect((c.played, c.won, c.drawn, c.lost), (3, 3, 0, 0));
      expect(c.streak, 3, reason: 'stats: streak clamps to the wins');
      expect(c.longestMoves, 0);
      expect(
        (c.steps[Strength.club]!.played, c.steps[Strength.club]!.won),
        (2, 2),
      );
      expect(c.steps[Strength.master]!.played, 0);
      final t = doc.two;
      expect((t.played, t.whiteWins, t.blackWins, t.drawn), (1, 1, 0, 0));
      expect(t.longestMoves, 88, reason: 'stats: no upper bound');
      expect(t.clocks[StatsClock.blitz], 2);
      expect(t.clocks[StatsClock.custom], 0);
      expect(doc.recentIds, [idOf(1), idOf(2)]);
      expect(doc.resetAt, isNull);
      expect(doc.toJson().keys, ['computer', 'two', 'recentIds']);
      expect((doc.toJson()['computer']! as Map).containsKey('extra'), isFalse);
    });

    test('a missing or wrong-typed document reads as zeros', () {
      for (final json in [
        null,
        3,
        'x',
        <String, Object?>{},
        {'computer': 1},
      ]) {
        expect(
          jsonEncode(StatsDocument.fromJson(json).toJson()),
          jsonEncode(const StatsDocument.empty().toJson()),
          reason: 'stats: $json',
        );
      }
    });

    test('one fixed key order, every step and clock written', () {
      final written = jsonEncode(const StatsDocument.empty().toJson());
      expect(
        written,
        '{"computer":{"played":0,"won":0,"drawn":0,"lost":0,"streak":0,'
        '"longestMoves":0,"steps":{"beginner":{"played":0,"won":0},'
        '"casual":{"played":0,"won":0},"club":{"played":0,"won":0},'
        '"strong":{"played":0,"won":0},"master":{"played":0,"won":0}}},'
        '"two":{"played":0,"whiteWins":0,"blackWins":0,"drawn":0,'
        '"longestMoves":0,"clocks":{"untimed":{"played":0},'
        '"blitz":{"played":0},"rapid":{"played":0},"classical":{"played":0},'
        '"custom":{"played":0}}},"recentIds":[]}',
      );
      final doc = const StatsDocument.empty()
          .withResult(foolsMate(club), idOf(1))
          .reset(99);
      expect(
        jsonEncode(StatsDocument.fromJson(doc.toJson()).toJson()),
        jsonEncode(doc.toJson()),
        reason: 'stats: a read-back document writes the same bytes',
      );
    });

    test('the id list keeps the last 50, in recording order', () {
      var doc = const StatsDocument.empty();
      for (var i = 1; i <= 53; i++) {
        doc = doc.withResult(foolsMate(const TwoPlayer()), idOf(i));
      }
      expect(doc.recentIds, [for (var i = 4; i <= 53; i++) idOf(i)]);
      final read = StatsDocument.fromJson({
        'recentIds': [for (var i = 1; i <= 60; i++) idOf(i)],
      });
      expect(read.recentIds.first, idOf(11));
      expect(read.recentIds, hasLength(maxRecentIds));
    });

    test('a custom control equal to a preset counts under the preset', () {
      expect(StatsClock.of(Timed(5, 0)), StatsClock.blitz);
      expect(StatsClock.of(Timed(10, 5)), StatsClock.rapid);
      expect(StatsClock.of(Timed(30, 0)), StatsClock.classical);
      expect(StatsClock.of(Timed(5, 3)), StatsClock.custom);
      expect(StatsClock.of(const Untimed()), StatsClock.untimed);
    });

    test('longest game is White\'s moves, losses included', () {
      final doc = const StatsDocument.empty()
          .withResult(
            played(club, ['e2e4', 'e7e5', 'd2d4', 'e5d4']).resign(Colour.white),
            idOf(1),
          )
          .withResult(foolsMate(club), idOf(2));
      expect(doc.computer.longestMoves, 2);
      expect((doc.computer.lost, doc.computer.won), (2, 0));
    });

    test('isAbandonable: vs Computer, unfinished, started, not counted', () {
      final going = played(club, ['e2e4']);
      final id = idOf(1);
      expect(isAbandonable(going, RecordedState(id: id, started: true)), true);
      expect(isAbandonable(going, RecordedState(id: id)), false);
      expect(
        isAbandonable(
          going,
          RecordedState(id: id, started: true, outcome: true),
        ),
        false,
      );
      expect(
        isAbandonable(foolsMate(club), RecordedState(id: id, started: true)),
        false,
      );
      expect(
        isAbandonable(
          played(const TwoPlayer(), ['e2e4']),
          RecordedState(id: id, started: true),
        ),
        false,
      );
    });
  });

  group('recorded state', () {
    test('newGameId is 16 lowercase hex digits', () {
      expect(newGameId(), matches(RegExp(r'^[0-9a-f]{16}$')));
      expect(newGameId(Random(1)), newGameId(Random(1)));
      expect(newGameId(), isNot(newGameId()));
    });

    test('fromJson keeps a good id even when other fields are damaged', () {
      final game = played(club, ['e2e4', 'e7e5']);
      final kept = RecordedState.fromJson({
        'id': idOf(7),
        'started': 'yes',
        'outcome': 1,
      }, game);
      expect(kept, RecordedState(id: idOf(7), started: true));
      final drawn = RecordedState.fromJson(
        {'id': 'short'},
        played(club, []),
        newId: () => idOf(9),
      );
      expect(drawn, RecordedState(id: idOf(9)));
      expect(
        RecordedState.fromJson(null, played(club, [])).started,
        isFalse,
        reason: 'stats: no move of yours',
      );
      final computerFirst = played(
        const VsComputer(
          playerColour: Colour.black,
          step: Strength.club,
          seed: 1,
        ),
        ['e2e4'],
      );
      expect(RecordedState.fromJson(null, computerFirst).started, isFalse);
      expect(
        RecordedState.fromJson(
          null,
          played(const TwoPlayer(), ['e2e4']),
        ).started,
        isTrue,
      );
    });
  });

  group('recorder', () {
    test('load writes nothing; records wait for it', () async {
      final store = RefusingStore()
        ..putRaw(
          StoreDoc.stats,
          jsonEncode({
            'format': 1,
            'data': {
              'computer': {'played': 4, 'lost': 4},
              'recentIds': [idOf(1)],
            },
          }),
        );
      final recorder = StatsRecorder(store: store);
      addTearDown(recorder.dispose);
      final recording = recorder.recordResult(
        foolsMate(club),
        RecordedState(id: idOf(2), started: true),
      );
      expect(recorder.isLoaded, isFalse);
      expect(await recording, RecordOutcome.recorded);
      expect(recorder.isLoaded, isTrue);
      expect(recorder.document.computer.played, 5, reason: 'stats: on top');
      expect(store.writes, 1);
      expect(
        await recorder.recordResult(
          foolsMate(club),
          RecordedState(id: idOf(1), started: true),
        ),
        RecordOutcome.duplicate,
      );
      expect(
        await recorder.recordResult(
          foolsMate(club),
          RecordedState(id: idOf(3), started: true, outcome: true),
        ),
        RecordOutcome.duplicate,
      );
      expect(store.writes, 1, reason: 'stats: a duplicate writes nothing');
      expect(recorder.document.computer.played, 5);
    });

    test('a refused write keeps the count in memory', () async {
      final store = RefusingStore()..refuse = true;
      final recorder = StatsRecorder(store: store);
      addTearDown(recorder.dispose);
      await recorder.load();
      expect(
        await recorder.recordAbandon(
          played(club, ['e2e4']),
          RecordedState(id: idOf(1), started: true),
        ),
        isTrue,
      );
      expect(recorder.document.computer.lost, 1);
      store.refuse = false;
      await recorder.recordResult(foolsMate(club), RecordedState(id: idOf(2)));
      final stored = StatsDocument.fromJson(
        (jsonDecode(store.rawText(StoreDoc.stats)!) as Map)['data'],
      );
      expect(stored.computer.lost, 2, reason: 'stats: the disk catches up');
    });

    test(
      'resetAll zeroes both modes, keeps the ids and stamps resetAt',
      () async {
        final store = RefusingStore();
        final recorder = StatsRecorder(store: store, nowMillis: () => 1234);
        addTearDown(recorder.dispose);
        await recorder.recordResult(
          foolsMate(club),
          RecordedState(id: idOf(1)),
        );
        await recorder.recordResult(
          foolsMate(const TwoPlayer()),
          RecordedState(id: idOf(2)),
        );
        await recorder.resetAll();
        expect(recorder.document.computer.played, 0);
        expect(recorder.document.two.played, 0);
        expect(recorder.document.recentIds, [idOf(1), idOf(2)]);
        expect(recorder.document.resetAt, 1234);
        expect(
          await recorder.recordResult(
            foolsMate(club),
            RecordedState(id: idOf(1)),
          ),
          RecordOutcome.duplicate,
          reason: 'stats: counted before the reset, never again',
        );
      },
    );

    test('a refused reset throws and changes nothing', () async {
      final store = RefusingStore();
      final recorder = StatsRecorder(store: store, nowMillis: () => 1234);
      addTearDown(recorder.dispose);
      await recorder.recordResult(foolsMate(club), RecordedState(id: idOf(1)));
      store.refuse = true;
      await expectLater(recorder.resetAll(), throwsA(isA<StatsResetFailed>()));
      expect(recorder.document.computer.played, 1);
      expect(recorder.document.resetAt, isNull);
      store.refuse = false;
      expect(
        await recorder.recordResult(
          foolsMate(club),
          RecordedState(id: idOf(2)),
        ),
        RecordOutcome.recorded,
        reason: 'stats: the chain goes on after a failed reset',
      );
    });
  });
}
