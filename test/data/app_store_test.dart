import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:honest_chess/data/app_store.dart';

void main() {
  late Directory dir;
  var clock = 1000;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('app_store_test');
    clock = 1000;
  });
  tearDown(() => dir.deleteSync(recursive: true));

  AppStore open({Duration readTimeout = const Duration(seconds: 5)}) =>
      AppStore(
        () async => dir,
        nowMillis: () => clock,
        readTimeout: readTimeout,
      );

  File file(String name) => File('${dir.path}/$name');
  List<String> names() => [
    for (final f in dir.listSync().whereType<File>()) f.uri.pathSegments.last,
  ]..sort();
  List<String> badCopies(String base) => [
    for (final n in names())
      if (n.startsWith('$base.bad-')) n,
  ];

  Map<String, Object?> dataOf(StoreRead read) => switch (read) {
    Loaded(:final data) => data,
    Absent() => fail('expected a loaded document, got $read'),
  };

  group('round trip', () {
    test(
      'each document is written as a versioned envelope and read back',
      () async {
        final store = open();
        for (final doc in StoreDoc.values) {
          expect(await store.write(doc, {'doc': doc.name, 'n': 1}), isTrue);
        }
        expect(
          names(),
          [for (final d in StoreDoc.values) '${d.fileName}.json']..sort(),
        );
        expect(jsonDecode(file('game-computer.json').readAsStringSync()), {
          'format': 1,
          'data': {'doc': 'gameComputer', 'n': 1},
        });
        expect(
          file('stats.json').readAsStringSync(),
          '{"format":1,"data":{"doc":"stats","n":1}}',
          reason: 'store: compact JSON',
        );
        final reopened = open();
        for (final doc in StoreDoc.values) {
          expect(dataOf(await reopened.read(doc)), {'doc': doc.name, 'n': 1});
        }
        expect(await reopened.persistent, isTrue);
        expect(reopened.corruptionNotices.value, isEmpty);
      },
    );

    test('a missing document is absent and raises no notice', () async {
      final store = open();
      expect(await store.read(StoreDoc.settings), isA<Absent>());
      expect(store.corruptionNotices.value, isEmpty);
      expect(names(), isEmpty, reason: 'store: reading creates nothing');
    });

    test('the documents directory is created when missing', () async {
      final nested = Directory('${dir.path}/files/data');
      final store = AppStore(() async => nested);
      expect(await store.write(StoreDoc.meta, {'a': 1}), isTrue);
      expect(File('${nested.path}/meta.json').existsSync(), isTrue);
    });
  });

  group('atomic writes', () {
    test(
      'a leftover .tmp beside an intact .json leaves the old value',
      () async {
        file('settings.json')
            .writeAsStringSync('{"format":1,"data":{"theme":"light"}}');
        // What a write killed before its rename leaves behind.
        file('settings.json.tmp')
            .writeAsStringSync('{"format":1,"data":{"theme":"da');
        final store = open();
        expect(dataOf(await store.read(StoreDoc.settings)), {'theme': 'light'});
        expect(
          file('settings.json.tmp').existsSync(),
          isFalse,
          reason: 'store: a stale .tmp is swept on first use',
        );
        expect(store.corruptionNotices.value, isEmpty);
      },
    );

    test('a write goes through .tmp and leaves none behind', () async {
      final store = open();
      await store.write(StoreDoc.stats, {'played': 3});
      expect(names(), ['stats.json']);
    });

    test(
      'queued writes: the last value wins and every future is true',
      () async {
        final store = open();
        final futures = [
          for (var i = 0; i < 5; i++) store.write(StoreDoc.stats, {'i': i}),
        ];
        expect(dataOf(await store.read(StoreDoc.stats)), {
          'i': 4,
        }, reason: 'store: a pending value is read without the disk');
        expect(await Future.wait(futures), everyElement(isTrue));
        expect(jsonDecode(file('stats.json').readAsStringSync())['data'], {
          'i': 4,
        });
      },
    );

    test('a value JSON cannot encode throws at the call', () {
      final store = open();
      expect(
        () => store.write(StoreDoc.meta, {'x': DateTime(2026)}),
        throwsArgumentError,
      );
    });

    test('flush waits for every queued write', () async {
      final store = open();
      unawaited(store.write(StoreDoc.settings, {'a': 1}));
      unawaited(store.write(StoreDoc.stats, {'b': 2}));
      await store.flush();
      expect(names(), ['settings.json', 'stats.json']);
    });
  });

  group('damaged content', () {
    final damaged = <String, List<int>>{
      'garbage bytes': [0xff, 0xfe, 0x00, 0x41],
      'empty': [],
      'not an object': utf8.encode('[1, 2]'),
      'no envelope': utf8.encode('{}'),
      'a string format': utf8.encode('{"format":"1","data":{}}'),
      'a newer format': utf8.encode('{"format":2,"data":{}}'),
      'a float format': utf8.encode('{"format":1.0,"data":{}}'),
      'a missing data': utf8.encode('{"format":1}'),
      'data not an object': utf8.encode('{"format":1,"data":[]}'),
      'truncated JSON': utf8.encode('{"format":1,"data":{"a"'),
    };

    for (final MapEntry(key: what, value: bytes) in damaged.entries) {
      test('$what is set aside, absent, noticed once', () async {
        file('stats.json').writeAsBytesSync(bytes);
        final store = open();
        var fired = 0;
        store.corruptionNotices.addListener(() => fired++);
        expect(await store.read(StoreDoc.stats), isA<Absent>());
        expect(names(), ['stats.bad-1000.json']);
        expect(
          file('stats.bad-1000.json').readAsBytesSync(),
          bytes,
          reason: 'store: the refused bytes are kept as they were',
        );
        expect(store.corruptionNotices.value, {StoreDoc.stats});
        expect(await store.read(StoreDoc.stats), isA<Absent>());
        await store.quarantine(StoreDoc.stats, 'again');
        expect(fired, 1, reason: 'store: the notice is raised once');
      });
    }

    test('extra top-level keys are ignored', () async {
      file('settings.json')
          .writeAsStringSync('{"format":1,"data":{"a":1},"note":"x"}');
      expect(dataOf(await open().read(StoreDoc.settings)), {'a': 1});
    });

    test('meta corruption is set aside without a notice', () async {
      file('meta.json').writeAsStringSync('not json');
      final store = open();
      expect(await store.read(StoreDoc.meta), isA<Absent>());
      expect(badCopies('meta'), hasLength(1));
      expect(store.corruptionNotices.value, isEmpty);
    });

    test('a set-aside copy is never read again', () async {
      file('settings.json').writeAsStringSync('{"format":2,"data":{"a":1}}');
      final store = open();
      await store.read(StoreDoc.settings);
      final kept = file('settings.bad-1000.json').readAsBytesSync();
      expect(await store.write(StoreDoc.settings, {'b': 2}), isTrue);
      expect(dataOf(await open().read(StoreDoc.settings)), {'b': 2});
      expect(file('settings.bad-1000.json').readAsBytesSync(), kept);
    });

    test(
      'the size limit: one byte over is refused, exactly at loads',
      () async {
        String padded(int size) {
          const head = '{"format":1,"data":{},"pad":"';
          const tail = '"}';
          return head + 'x' * (size - head.length - tail.length) + tail;
        }

        file('stats.json').writeAsStringSync(padded(maxDocumentBytes));
        final store = open();
        expect(dataOf(await store.read(StoreDoc.stats)), isEmpty);
        file('settings.json').writeAsStringSync(padded(maxDocumentBytes + 1));
        expect(await store.read(StoreDoc.settings), isA<Absent>());
        expect(badCopies('settings'), hasLength(1));
        expect(store.corruptionNotices.value, {StoreDoc.settings});
      },
    );

    test('three set-aside copies are kept, the oldest pruned', () async {
      final store = open();
      for (var i = 0; i < 5; i++) {
        clock = 2000 + i;
        file('stats.json').writeAsStringSync('bad $i');
        expect(await store.read(StoreDoc.stats), isA<Absent>());
      }
      expect(badCopies('stats'), [
        'stats.bad-2002.json',
        'stats.bad-2003.json',
        'stats.bad-2004.json',
      ]);
    });

    test('a same-millisecond collision gets a suffix', () async {
      final store = open();
      for (var i = 0; i < 3; i++) {
        file('stats.json').writeAsStringSync('bad $i');
        await store.read(StoreDoc.stats);
      }
      expect(badCopies('stats'), [
        'stats.bad-1000-1.json',
        'stats.bad-1000-2.json',
        'stats.bad-1000.json',
      ]);
      file('stats.json').writeAsStringSync('bad 3');
      await store.read(StoreDoc.stats);
      expect(badCopies('stats'), [
        'stats.bad-1000-1.json',
        'stats.bad-1000-2.json',
        'stats.bad-1000-3.json',
      ], reason: 'store: pruning orders by millis, then suffix');
    });
  });

  group('I/O failures', () {
    test(
      'an unreadable document is absent, noticed, and never written',
      () async {
        // A directory where the file should be: reading it fails for an I/O
        // reason, not its content.
        Directory('${dir.path}/stats.json').createSync();
        final store = open();
        expect(await store.read(StoreDoc.stats), isA<Absent>());
        expect(store.corruptionNotices.value, {StoreDoc.stats});
        expect(badCopies('stats'), isEmpty, reason: 'store: nothing moved');
        expect(await store.write(StoreDoc.stats, {'played': 0}), isFalse);
        await store.delete(StoreDoc.stats);
        expect(
          Directory('${dir.path}/stats.json').existsSync(),
          isTrue,
          reason: 'store: a locked document refuses deletes too',
        );
        expect(
          await store.write(StoreDoc.settings, {'a': 1}),
          isTrue,
          reason: 'store: only that document is locked',
        );
      },
    );

    test(
      'a read that times out is absent, noticed, and locks the file',
      () async {
        file('stats.json').writeAsStringSync('{"format":1,"data":{"n":7}}');
        final before = file('stats.json').readAsBytesSync();
        final late = Completer<Directory>();
        final store = AppStore(
          () => late.future,
          readTimeout: const Duration(milliseconds: 20),
        );
        expect(await store.read(StoreDoc.stats), isA<Absent>());
        expect(store.corruptionNotices.value, {StoreDoc.stats});
        late.complete(dir);
        expect(await store.write(StoreDoc.stats, {'n': 0}), isFalse);
        await store.flush();
        expect(
          file('stats.json').readAsBytesSync(),
          before,
          reason: 'store: defaults never overwrite a file that timed out',
        );
      },
    );

    test('with a prompt directory the same read and write succeed', () async {
      file('stats.json').writeAsStringSync('{"format":1,"data":{"n":7}}');
      final store = open(readTimeout: const Duration(milliseconds: 20));
      expect(dataOf(await store.read(StoreDoc.stats)), {'n': 7});
      expect(await store.write(StoreDoc.stats, {'n': 0}), isTrue);
      expect(dataOf(await open().read(StoreDoc.stats)), {'n': 0});
      expect(store.corruptionNotices.value, isEmpty);
    });

    test('a resolver that throws falls back to memory', () async {
      final store = AppStore(() async => throw const FileSystemException('x'));
      expect(await store.write(StoreDoc.settings, {'a': 1}), isTrue);
      expect(dataOf(await store.read(StoreDoc.settings)), {'a': 1});
      expect(await store.persistent, isFalse);
    });

    test('a directory that cannot be created falls back to memory', () async {
      file('blocker').writeAsStringSync('');
      final store = AppStore(() async => Directory('${dir.path}/blocker/data'));
      expect(await store.write(StoreDoc.settings, {'a': 1}), isTrue);
      expect(await store.persistent, isFalse);
    });
  });

  group('delete, purge and quarantine', () {
    test('delete removes the file, a .tmp and every set-aside copy', () async {
      file('stats.json').writeAsStringSync('bad');
      final store = open();
      await store.read(StoreDoc.stats);
      await store.write(StoreDoc.stats, {'n': 1});
      file('stats.json.tmp').writeAsStringSync('x');
      file('settings.json').writeAsStringSync('{"format":1,"data":{}}');
      await store.delete(StoreDoc.stats);
      expect(names(), ['settings.json']);
      expect(await store.read(StoreDoc.stats), isA<Absent>());
    });

    test('a delete drops pending writes; a read meanwhile is absent', () async {
      final store = open();
      final first = store.write(StoreDoc.stats, {'n': 1});
      final second = store.write(StoreDoc.stats, {'n': 2});
      final deleted = store.delete(StoreDoc.stats);
      expect(await store.read(StoreDoc.stats), isA<Absent>());
      await deleted;
      expect(
        [await first, await second],
        [false, false],
        reason: 'store: a dropped write answers false',
      );
      expect(names(), isEmpty);
    });

    test('purgeQuarantined removes only the set-aside copies', () async {
      file('stats.json').writeAsStringSync('bad');
      final store = open();
      await store.read(StoreDoc.stats);
      await store.write(StoreDoc.stats, {'n': 1});
      await store.purgeQuarantined(StoreDoc.stats);
      expect(names(), ['stats.json']);
    });

    test('quarantine after a read moves the file aside and notices', () async {
      file('game-two.json').writeAsStringSync('{"format":1,"data":{"x":1}}');
      final store = open();
      expect(await store.read(StoreDoc.gameTwo), isA<Loaded>());
      await store.quarantine(StoreDoc.gameTwo, 'replay failed');
      expect(names(), ['game-two.bad-1000.json']);
      expect(store.corruptionNotices.value, {StoreDoc.gameTwo});
    });

    test(
      'quarantine after a newer write moves nothing, still notices',
      () async {
        file('game-two.json').writeAsStringSync('{"format":1,"data":{"x":1}}');
        final store = open();
        await store.read(StoreDoc.gameTwo);
        final saved = store.write(StoreDoc.gameTwo, {'x': 2});
        await store.quarantine(StoreDoc.gameTwo, 'replay failed');
        expect(await saved, isTrue, reason: 'store: queued writes are kept');
        expect(names(), ['game-two.json']);
        expect(dataOf(await open().read(StoreDoc.gameTwo)), {'x': 2});
        expect(store.corruptionNotices.value, {StoreDoc.gameTwo});
      },
    );

    test('quarantining meta raises no notice', () async {
      final store = open();
      await store.quarantine(StoreDoc.meta, 'why not');
      expect(store.corruptionNotices.value, isEmpty);
    });

    test('dismissNotices clears the banner', () async {
      file('stats.json').writeAsStringSync('bad');
      final store = open();
      await store.read(StoreDoc.stats);
      store.dismissNotices();
      expect(store.corruptionNotices.value, isEmpty);
    });
  });

  group('the memory store', () {
    test('starts with its documents and stores exact text', () async {
      final store = AppStore.memory(
        documents: {
          StoreDoc.settings: {'a': 1},
        },
      );
      expect(dataOf(await store.read(StoreDoc.settings)), {'a': 1});
      await store.write(StoreDoc.stats, {'b': 2.5});
      expect(store.rawText(StoreDoc.stats), '{"format":1,"data":{"b":2.5}}');
      expect(store.rawText(StoreDoc.meta), isNull);
      expect(await store.persistent, isFalse);
    });

    test('damaged raw content is refused like a file', () async {
      final store = AppStore.memory();
      store.putRaw(StoreDoc.stats, '{"format":2,"data":{}}');
      expect(await store.read(StoreDoc.stats), isA<Absent>());
      expect(store.corruptionNotices.value, {StoreDoc.stats});
      expect(store.rawText(StoreDoc.stats), isNull);
    });

    test('values round-trip through JSON', () async {
      final store = AppStore.memory();
      await store.write(StoreDoc.settings, {
        'list': [1, 2],
        'nested': {'k': true},
      });
      final data = dataOf(await store.read(StoreDoc.settings));
      expect(data['list'], isA<List<Object?>>());
      expect(data['nested'], isA<Map<String, Object?>>());
    });

    test('raw text belongs to the memory store only', () {
      expect(() => open().rawText(StoreDoc.meta), throwsUnsupportedError);
    });
  });
}
