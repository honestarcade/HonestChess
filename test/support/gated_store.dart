import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:honest_chess/data/app_store.dart';

/// A memory store whose reads each wait for their document's release.
class GatedStore implements AppStore {
  GatedStore([AppStore? delegate]) : _delegate = delegate ?? AppStore.memory();

  final AppStore _delegate;
  final _gates = {for (final doc in StoreDoc.values) doc: Completer<void>()};

  /// Lets [doc]'s read, and every later one, through.
  void release(StoreDoc doc) {
    if (!_gates[doc]!.isCompleted) _gates[doc]!.complete();
  }

  void releaseAll() => StoreDoc.values.forEach(release);

  @override
  Future<StoreRead> read(StoreDoc doc) async {
    await _gates[doc]!.future;
    return _delegate.read(doc);
  }

  @override
  Duration? get readTimeout => _delegate.readTimeout;

  @override
  ValueNotifier<Set<StoreDoc>> get corruptionNotices =>
      _delegate.corruptionNotices;

  @override
  void dismissNotices() => _delegate.dismissNotices();

  @override
  Future<bool> get persistent => _delegate.persistent;

  @override
  Future<bool> write(StoreDoc doc, Map<String, Object?> data) =>
      _delegate.write(doc, data);

  @override
  Future<void> delete(StoreDoc doc) => _delegate.delete(doc);

  @override
  Future<void> purgeQuarantined(StoreDoc doc) =>
      _delegate.purgeQuarantined(doc);

  @override
  Future<void> quarantine(StoreDoc doc, String reason) =>
      _delegate.quarantine(doc, reason);

  @override
  Future<void> flush() => _delegate.flush();

  @override
  String? rawText(StoreDoc doc) => _delegate.rawText(doc);

  @override
  void putRaw(StoreDoc doc, String text) => _delegate.putRaw(doc, text);
}
