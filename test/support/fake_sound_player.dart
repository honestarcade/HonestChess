import 'package:honest_chess/feedback/clips.dart';
import 'package:honest_chess/feedback/sound_player.dart';

/// A [SoundPlayer] that records what it was asked to do, in order.
class FakeSoundPlayer implements SoundPlayer {
  /// What [startMusic] answers: false stands for another app's audio.
  bool startAnswers = true;

  /// The effects played, oldest first.
  final List<Clip> played = [];

  /// Every music call, oldest first: `start`, `pause`, `stop`.
  final List<String> music = [];

  /// Every load, and whether [dispose] ran.
  final List<Map<Clip, ClipSpec>> loads = [];
  bool disposed = false;

  @override
  Future<void> load(Map<Clip, ClipSpec> clips) async => loads.add(clips);

  @override
  void play(Clip clip) => played.add(clip);

  @override
  Future<bool> startMusic() async {
    music.add('start');
    return startAnswers;
  }

  @override
  Future<void> pauseMusic() async => music.add('pause');

  @override
  Future<void> stopMusic() async => music.add('stop');

  @override
  Future<void> dispose() async => disposed = true;
}
