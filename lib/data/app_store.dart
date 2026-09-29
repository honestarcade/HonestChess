/// The device-side store (#80): small versioned JSON documents in the app's
/// private files directory, written atomically, read back tolerantly, never
/// sent anywhere.
///
/// Every document is `{"format": 1, "data": {...}}`. A missing document loads
/// as absent. A damaged one is moved aside as `<name>.bad-<epochMillis>.json`,
/// loads as absent and raises a notice the menu shows once (`meta` excepted).
/// A document that cannot be read for an I/O reason loads as absent, raises
/// the same notice and is never written again that session, so a passing
/// failure cannot overwrite intact data. Saving never blocks play: a failed
/// write is logged with `debugPrint` and otherwise swallowed.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../platform/platform_channel.dart';

/// The documents the app keeps, one file each.
enum StoreDoc {
  settings,
  stats,
  gameComputer,
  gameTwo,
  meta;

  /// The file's base name: `<fileName>.json`.
  String get fileName => switch (this) {
    settings => 'settings',
    stats => 'stats',
    gameComputer => 'game-computer',
    gameTwo => 'game-two',
    meta => 'meta',
  };

  /// `meta` holds nothing the player would miss, so its loss raises no
  /// banner.
  bool get raisesNotice => this != meta;
}

/// The envelope version this build reads and writes.
const storeFormat = 1;

/// How many set-aside copies of one document are kept.
const quarantineKeep = 3;

/// A document file longer than this is refused without being decoded.
const maxDocumentBytes = 1024 * 1024;

/// What [AppStore.read] found.
sealed class StoreRead {
  const StoreRead();
}

/// The document's `data`.
final class Loaded extends StoreRead {
  const Loaded(this.data);

  final Map<String, Object?> data;

  @override
  String toString() => 'Loaded($data)';
}

/// No usable document: missing, damaged, unreadable or deleted.
final class Absent extends StoreRead {
  const Absent();

  @override
  String toString() => 'Absent()';
}

class AppStore {
  /// A store over the directory [resolveDir] answers, created (recursively)
  /// if missing; stale `.tmp` files there are swept on first use. If the
  /// resolver throws or the directory cannot be created, the store keeps its
  /// documents in memory instead: persistence is off, nothing crashes.
  AppStore(
    Future<Directory> Function() resolveDir, {
    int Function()? nowMillis,
    this.readTimeout = const Duration(seconds: 5),
  }) : _resolveDir = resolveDir,
       _nowMillis = nowMillis ?? _epochMillis,
       _memory = null;

  /// The production store: `<filesDir>/data`, the directory coming from the
  /// platform channel.
  factory AppStore.onDevice(
    PlatformChannel platform, {
    int Function()? nowMillis,
  }) => AppStore(() async {
    final files = await platform.filesDir();
    if (files == null) throw StateError('no files directory');
    return Directory('$files/data');
  }, nowMillis: nowMillis);

  /// A store kept in memory, behind the same API, starting with [documents].
  /// Values round-trip through JSON as on disk, so readers see the same
  /// types.
  AppStore.memory({
    Map<StoreDoc, Map<String, Object?>> documents = const {},
    int Function()? nowMillis,
  }) : _resolveDir = null,
       _nowMillis = nowMillis ?? _epochMillis,
       readTimeout = null,
       _memory = _MemoryBackend() {
    for (final MapEntry(key: doc, value: data) in documents.entries) {
      _memory!.texts[doc.fileName] = _encode(data);
    }
    _backend = Future.value(_memory);
  }

  static int _epochMillis() => DateTime.now().millisecondsSinceEpoch;

  final Future<Directory> Function()? _resolveDir;
  final int Function() _nowMillis;
  final _MemoryBackend? _memory;

  /// How long a disk read (or a quarantine move) may take, counted from the
  /// call with directory resolution included; null for a memory store,
  /// which never times out.
  final Duration? readTimeout;

  Future<_Backend>? _backend;
  final Map<StoreDoc, _DocState> _docs = {
    for (final doc in StoreDoc.values) doc: _DocState(),
  };

  /// Documents found damaged or unreadable this session, until the menu's
  /// banner is dismissed (#91).
  final ValueNotifier<Set<StoreDoc>> corruptionNotices = ValueNotifier(
    const {},
  );

  /// Clears [corruptionNotices] (the banner's dismiss).
  void dismissNotices() => corruptionNotices.value = const {};

  /// Whether the documents are kept on disk (false in memory, including the
  /// fallback).
  Future<bool> get persistent async => (await _store) is _FileBackend;

  Future<_Backend> get _store => _backend ??= _open();

  Future<_Backend> _open() async {
    final Directory dir;
    try {
      dir = await _resolveDir!();
    } on Object catch (e) {
      debugPrint('app store: no directory ($e); persistence is off');
      return _MemoryBackend();
    }
    try {
      await dir.create(recursive: true);
      final backend = _FileBackend(dir);
      await backend.sweepTemps();
      return backend;
    } on Object catch (e) {
      debugPrint('app store: cannot use ${dir.path} ($e); persistence is off');
      return _MemoryBackend();
    }
  }

  /// The document's `data`, or [Absent]. A write or delete still queued is
  /// answered without touching the disk. Never throws.
  Future<StoreRead> read(StoreDoc doc) async {
    final state = _docs[doc]!;
    if (state.latest case final pending?) {
      final text = pending.text;
      return text == null ? const Absent() : Loaded(_unwrap(text)!);
    }
    if (state.locked) return const Absent();
    final op = _ReadOp();
    final result = _enqueue(doc, () => _readFromDisk(doc, op));
    final limit = readTimeout;
    if (limit == null) return result;
    return result.timeout(
      limit,
      onTimeout: () {
        op.abandoned = true;
        _ioFailure(doc, 'read timed out');
        return const Absent();
      },
    );
  }

  Future<StoreRead> _readFromDisk(StoreDoc doc, _ReadOp op) async {
    final state = _docs[doc]!;
    final generation = state.generation;
    final _Raw raw;
    try {
      raw = await (await _store).read(doc.fileName);
    } on Object catch (e) {
      if (!op.abandoned) _ioFailure(doc, '$e');
      return const Absent();
    }
    if (op.abandoned) return const Absent();
    state.readGeneration = generation;
    if (raw case _Missing()) return const Absent();
    final data = switch (raw) {
      _Bytes(:final bytes) => _unwrapBytes(bytes),
      _ => null,
    };
    if (data != null) return Loaded(data);
    if (state.generation == generation) {
      await _moveAside(doc, 'damaged content');
    } else {
      // A write or delete queued meanwhile replaces the damaged file anyway.
      _raiseNotice(doc);
    }
    return const Absent();
  }

  /// A document that could not be read loads as absent, raises its notice
  /// and is locked: nothing writes over what may still be intact data.
  void _ioFailure(StoreDoc doc, String why) {
    final state = _docs[doc]!;
    if (!state.locked) {
      debugPrint('app store: ${doc.fileName} unreadable: $why');
    }
    state.locked = true;
    _raiseNotice(doc);
  }

  void _raiseNotice(StoreDoc doc) {
    if (!doc.raisesNotice || corruptionNotices.value.contains(doc)) return;
    corruptionNotices.value = {...corruptionNotices.value, doc};
  }

  static Map<String, Object?>? _unwrapBytes(List<int> bytes) {
    if (bytes.length > maxDocumentBytes) return null;
    try {
      return _unwrap(utf8.decode(bytes));
    } on FormatException {
      return null;
    }
  }

  /// The `data` of a valid envelope, or null when [text] is not one.
  static Map<String, Object?>? _unwrap(String text) {
    if (text.trim().isEmpty) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, Object?>) return null;
    final format = decoded['format'];
    if (format is! int || format != storeFormat) return null;
    final data = decoded['data'];
    if (data is! Map<String, Object?>) return null;
    return data;
  }

  static String _encode(Map<String, Object?> data) {
    try {
      return jsonEncode({'format': storeFormat, 'data': data});
    } on JsonUnsupportedObjectError catch (e) {
      throw ArgumentError.value(data, 'data', 'not encodable as JSON: $e');
    }
  }

  /// Queues [data] as the document's new value, encoded now: a value
  /// `jsonEncode` rejects throws [ArgumentError] at once. The future is true
  /// once this value, or a later one that replaced it, is in place; false
  /// when the write failed, a delete dropped it, or the document is locked.
  /// It never completes with an error.
  Future<bool> write(StoreDoc doc, Map<String, Object?> data) {
    final text = _encode(data);
    final state = _docs[doc]!;
    if (state.locked) {
      debugPrint('app store: ${doc.fileName} is locked; write refused');
      return Future.value(false);
    }
    state.generation++;
    final waiter = Completer<bool>();
    final queued = state.queued.lastOrNull;
    if (queued != null && queued.text != null) {
      queued
        ..text = text
        ..waiters.add(waiter);
      return waiter.future;
    }
    final mutation = _Mutation(text)..waiters.add(waiter);
    _queue(doc, mutation);
    return waiter.future;
  }

  /// Removes the document with every trace of it: `<name>.json`, a leftover
  /// `.tmp` and every set-aside `.bad-*` copy. Queued writes not yet started
  /// are dropped (their futures answer false). A locked document refuses.
  Future<void> delete(StoreDoc doc) {
    final state = _docs[doc]!;
    if (state.locked) {
      debugPrint('app store: ${doc.fileName} is locked; delete refused');
      return Future.value();
    }
    state.generation++;
    for (final dropped in state.queued) {
      dropped.cancel();
    }
    state.queued.clear();
    final mutation = _Mutation(null);
    final done = Completer<bool>();
    mutation.waiters.add(done);
    _queue(doc, mutation);
    return done.future;
  }

  void _queue(StoreDoc doc, _Mutation mutation) {
    final state = _docs[doc]!;
    state
      ..queued.add(mutation)
      ..latest = mutation;
    _enqueue(doc, () => _apply(doc, mutation));
  }

  Future<void> _apply(StoreDoc doc, _Mutation mutation) async {
    final state = _docs[doc]!;
    state.queued.remove(mutation);
    if (mutation.cancelled) return;
    var ok = false;
    if (state.locked) {
      debugPrint('app store: ${doc.fileName} is locked; queued change dropped');
    } else {
      try {
        final backend = await _store;
        final text = mutation.text;
        if (text == null) {
          await backend.delete(doc.fileName);
        } else {
          await backend.write(doc.fileName, text);
        }
        ok = true;
      } on Object catch (e) {
        debugPrint('app store: saving ${doc.fileName} failed ($e)');
      }
    }
    if (identical(state.latest, mutation)) state.latest = null;
    mutation.complete(ok);
  }

  /// Removes only the document's set-aside `.bad-*` copies.
  Future<void> purgeQuarantined(StoreDoc doc) => _enqueue(doc, () async {
    try {
      await (await _store).purgeQuarantined(doc.fileName);
    } on Object catch (e) {
      debugPrint('app store: purging ${doc.fileName} copies failed ($e)');
    }
  });

  /// Refuses the document's content for a reason found above the store
  /// (#81's `GameLoadError`): moves `<name>.json` aside as damaged, unless a
  /// write or delete has been queued since it was last read from disk (then
  /// the refused content is already gone), and raises its notice either way
  /// (never for `meta`). Queued writes are kept. Never throws.
  Future<void> quarantine(StoreDoc doc, String reason) {
    debugPrint('app store: ${doc.fileName} refused: $reason');
    _raiseNotice(doc);
    final op = _ReadOp();
    final moved = _enqueue(doc, () async {
      final state = _docs[doc]!;
      if (op.abandoned || state.readGeneration != state.generation) return;
      await _moveAside(doc, reason);
    });
    final limit = readTimeout;
    if (limit == null) return moved;
    return moved.timeout(
      limit,
      onTimeout: () {
        op.abandoned = true;
        _ioFailure(doc, 'quarantine move timed out');
      },
    );
  }

  Future<void> _moveAside(StoreDoc doc, String reason) async {
    debugPrint('app store: setting ${doc.fileName} aside: $reason');
    try {
      await (await _store).quarantine(doc.fileName, _nowMillis());
    } on Object catch (e) {
      debugPrint('app store: setting ${doc.fileName} aside failed ($e)');
    }
    _raiseNotice(doc);
  }

  /// Completes when every queued operation, including ones queued while
  /// waiting, has finished.
  Future<void> flush() async {
    while (true) {
      final tails = [for (final state in _docs.values) state.tail];
      await Future.wait(tails);
      var i = 0;
      if (_docs.values.every((state) => identical(state.tail, tails[i++]))) {
        return;
      }
    }
  }

  /// Runs [op] after everything already queued for [doc].
  Future<T> _enqueue<T>(StoreDoc doc, Future<T> Function() op) {
    final state = _docs[doc]!;
    final result = Completer<T>();
    state.tail = state.tail.then((_) async {
      try {
        result.complete(await op());
      } on Object catch (e, stack) {
        result.completeError(e, stack);
      }
    });
    return result.future;
  }

  /// A memory store's exact stored text for [doc], or null when it holds
  /// none. For tests asserting byte-identical saves.
  @visibleForTesting
  String? rawText(StoreDoc doc) => _memoryOnly.texts[doc.fileName];

  /// Stores [text] as [doc]'s content in a memory store, as is: tests seed
  /// damaged content with it.
  @visibleForTesting
  void putRaw(StoreDoc doc, String text) =>
      _memoryOnly.texts[doc.fileName] = text;

  _MemoryBackend get _memoryOnly =>
      _memory ?? (throw UnsupportedError('only a memory store holds raw text'));
}

/// One document's queue and what is known about it this session.
class _DocState {
  Future<void> tail = Future.value();

  /// Writes and deletes queued but not started, oldest first.
  final List<_Mutation> queued = [];

  /// The newest write or delete not yet in place: what a read answers.
  _Mutation? latest;

  /// Counts writes and deletes queued; compared with [readGeneration].
  int generation = 0;

  /// [generation] when the file was last read from disk.
  int? readGeneration;

  /// Set after an I/O read failure: no write or delete this session.
  bool locked = false;
}

/// A queued write ([text]) or delete (null [text]).
class _Mutation {
  _Mutation(this.text);

  String? text;
  bool cancelled = false;
  final List<Completer<bool>> waiters = [];

  void cancel() {
    cancelled = true;
    complete(false);
  }

  void complete(bool ok) {
    for (final waiter in waiters) {
      if (!waiter.isCompleted) waiter.complete(ok);
    }
  }
}

class _ReadOp {
  bool abandoned = false;
}

sealed class _Raw {
  const _Raw();
}

class _Missing extends _Raw {
  const _Missing();
}

/// A file over [maxDocumentBytes], not read.
class _Oversize extends _Raw {
  const _Oversize();
}

class _Bytes extends _Raw {
  const _Bytes(this.bytes);

  final List<int> bytes;
}

abstract class _Backend {
  Future<_Raw> read(String name);
  Future<void> write(String name, String text);
  Future<void> delete(String name);
  Future<void> purgeQuarantined(String name);
  Future<void> quarantine(String name, int millis);
}

class _MemoryBackend implements _Backend {
  final Map<String, String> texts = {};

  @override
  Future<_Raw> read(String name) async {
    final text = texts[name];
    if (text == null) return const _Missing();
    final bytes = utf8.encode(text);
    return bytes.length > maxDocumentBytes ? const _Oversize() : _Bytes(bytes);
  }

  @override
  Future<void> write(String name, String text) async => texts[name] = text;

  @override
  Future<void> delete(String name) async => texts.remove(name);

  @override
  Future<void> purgeQuarantined(String name) async {}

  @override
  Future<void> quarantine(String name, int millis) async => texts.remove(name);
}

/// `<dir>/<name>.json`, written through `<name>.json.tmp` and a rename.
class _FileBackend implements _Backend {
  _FileBackend(this.dir);

  final Directory dir;

  File _file(String name) => File('${dir.path}/$name.json');
  File _temp(String name) => File('${dir.path}/$name.json.tmp');

  /// A `.tmp` is what an interrupted write leaves; it is never recovered.
  Future<void> sweepTemps() async {
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.json.tmp')) {
        await entity.delete();
      }
    }
  }

  @override
  Future<_Raw> read(String name) async {
    final file = _file(name);
    final int length;
    try {
      length = await file.length();
    } on PathNotFoundException {
      return const _Missing();
    }
    if (length > maxDocumentBytes) return const _Oversize();
    return _Bytes(await file.readAsBytes());
  }

  @override
  Future<void> write(String name, String text) async {
    final temp = _temp(name);
    await temp.writeAsString(text, flush: true);
    await temp.rename(_file(name).path);
  }

  @override
  Future<void> delete(String name) async {
    for (final file in [_file(name), _temp(name), ...await _bad(name)]) {
      if (await file.exists()) await file.delete();
    }
  }

  @override
  Future<void> purgeQuarantined(String name) async {
    for (final file in await _bad(name)) {
      await file.delete();
    }
  }

  @override
  Future<void> quarantine(String name, int millis) async {
    final file = _file(name);
    if (!await file.exists()) return;
    var target = File('${dir.path}/$name.bad-$millis.json');
    for (var n = 1; await target.exists(); n++) {
      target = File('${dir.path}/$name.bad-$millis-$n.json');
    }
    try {
      await file.rename(target.path);
    } on FileSystemException {
      await file.delete();
      return;
    }
    final bad = await _bad(name);
    for (final old in bad.reversed.skip(quarantineKeep)) {
      await old.delete();
    }
  }

  /// The set-aside copies of [name], oldest first: by the millis in the
  /// name, then the collision suffix.
  Future<List<File>> _bad(String name) async {
    final pattern = RegExp(
      '^${RegExp.escape(name)}\\.bad-(\\d+)(?:-(\\d+))?\\.json\$',
    );
    final found = <(int, int, File)>[];
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final match = pattern.firstMatch(entity.uri.pathSegments.last);
      if (match == null) continue;
      found.add((int.parse(match[1]!), int.parse(match[2] ?? '0'), entity));
    }
    found.sort((a, b) => a.$1 != b.$1 ? a.$1 - b.$1 : a.$2 - b.$2);
    return [for (final (_, _, file) in found) file];
  }
}
