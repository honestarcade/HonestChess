/// Plays the game's sounds through `SoundBridge.kt` (#96; Honest
/// Solitaire's player): SoundPool for the effects, a looping MediaPlayer
/// for the music, no plugin. Anywhere the channel is missing (a platform
/// without the bridge) it logs once and stays silent; a sound is never
/// allowed to throw into the UI.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'clips.dart';

/// The channel SoundBridge.kt listens on.
const soundChannelName = 'honestchess/sound';

abstract interface class SoundPlayer {
  /// Loads every clip's asset once. Plays before this completes are
  /// dropped.
  Future<void> load(Map<Clip, ClipSpec> clips);

  /// Plays [clip], if it loaded. Never waits and never throws.
  void play(Clip clip);

  /// Starts the loop; false when it did not (another app's audio, no
  /// bridge, a dead player).
  Future<bool> startMusic();

  /// Holds the loop where it is.
  Future<void> pauseMusic();

  /// Holds the loop and resets it to the beginning.
  Future<void> stopMusic();

  /// Releases everything loaded.
  Future<void> dispose();
}

class ChannelSoundPlayer implements SoundPlayer {
  ChannelSoundPlayer({
    this.channel = const MethodChannel(soundChannelName),
    void Function(String message)? log,
  }) : _log = log ?? debugPrint;

  final MethodChannel channel;
  final void Function(String) _log;
  bool _loaded = false;
  bool _dead = false;
  final Set<Clip> _playFailed = {};

  @override
  Future<void> load(Map<Clip, ClipSpec> clips) async {
    if (_dead) return;
    try {
      final opened = await channel.invokeMethod<int>('load', {
        for (final e in clips.entries) e.key.name: e.value.asset,
      });
      _loaded = true;
      if (opened != clips.length) {
        _log('sound: ${opened ?? 0} of ${clips.length} clips loaded');
      }
    } on Object catch (e) {
      // A failed load leaves sound off for the session, logged once.
      _dead = true;
      _log('sound: no player, playing nothing ($e)');
    }
  }

  @override
  void play(Clip clip) {
    if (_dead || !_loaded) return;
    channel.invokeMethod<void>('play', clip.name).catchError((Object error) {
      if (_playFailed.add(clip)) {
        _log('sound: ${clip.name} did not play ($error)');
      }
    });
  }

  Future<T?> _guarded<T>(String what, Future<T?> Function() call) async {
    if (_dead || !_loaded) return null;
    try {
      return await call();
    } on Object catch (e) {
      _log('sound: $what failed ($e)');
      return null;
    }
  }

  @override
  Future<bool> startMusic() async =>
      await _guarded(
        'musicStart',
        () => channel.invokeMethod<bool>('musicStart'),
      ) ??
      false;

  @override
  Future<void> pauseMusic() =>
      _guarded('musicPause', () => channel.invokeMethod<void>('musicPause'));

  @override
  Future<void> stopMusic() =>
      _guarded('musicStop', () => channel.invokeMethod<void>('musicStop'));

  @override
  Future<void> dispose() async {
    if (_dead || !_loaded) return;
    _loaded = false;
    try {
      await channel.invokeMethod<void>('release');
    } on Object catch (e) {
      _log('sound: release failed ($e)');
    }
  }
}
