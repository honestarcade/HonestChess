import 'dart:async';

import 'package:flutter/foundation.dart';

import 'app_store.dart';
import 'game_saves.dart';
import 'play_mode.dart';
import 'settings_store.dart';
import 'stats.dart';

/// The launch load: one step per stored document, each the owning store's
/// own load, which fills that store in place. The steps run at once;
/// [progress] counts the ones finished and [done] completes once all have.
///
/// A step never fails the launch. The stores answer a missing, damaged or
/// unreadable document with their defaults (and the store's notice, which
/// the menu's banner shows); anything that still throws is logged and the
/// step counts as finished on its defaults.
class AppLoader {
  AppLoader({
    required AppStore store,
    required SettingsStore settings,
    required StatsRecorder stats,
    required GameSaves saves,
  }) : _steps = {
         StoreDoc.settings: () => settings.load(store),
         StoreDoc.stats: stats.load,
         StoreDoc.gameComputer: () => saves.loadSlot(PlayMode.computer),
         StoreDoc.gameTwo: () => saves.loadSlot(PlayMode.two),
         StoreDoc.meta: saves.loadMeta,
       };

  final Map<StoreDoc, Future<void> Function()> _steps;
  final _progress = ValueNotifier<double>(0);
  final _done = Completer<void>();
  var _finished = 0;
  var _started = false;
  var _disposed = false;

  /// The documents loaded, one step each, in the order [StoreDoc] names
  /// them.
  Iterable<StoreDoc> get steps => _steps.keys;

  /// The fraction of steps finished, from 0 to 1; it holds the latest
  /// value, so a late listener reads it at once.
  ValueListenable<double> get progress => _progress;

  /// Completes right after [progress] reaches 1.
  Future<void> get done => _done.future;

  /// Starts every step. Later calls do nothing: the load runs once.
  void start() {
    if (_started) return;
    _started = true;
    for (final MapEntry(key: doc, value: load) in _steps.entries) {
      _run(doc, load);
    }
  }

  Future<void> _run(StoreDoc doc, Future<void> Function() load) async {
    try {
      await load();
    } on Object catch (e) {
      debugPrint('launch: ${doc.fileName} could not be loaded: $e');
    }
    _finished++;
    if (!_disposed) _progress.value = _finished / _steps.length;
    if (_finished == _steps.length) _done.complete();
  }

  void dispose() {
    _disposed = true;
    _progress.dispose();
  }
}
