// The Android side of the sound channel (#96), on a device or emulator: the
// real SoundBridge opens every bundled clip, plays one, starts the loop
// after an effect without holding up the main thread (#145), and refuses a
// method it does not carry.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:honest_chess/feedback/clips.dart';
import 'package:honest_chess/feedback/sound_player.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(soundChannelName);

  testWidgets('load opens all six clips; play and the loop answer', (
    tester,
  ) async {
    final opened = await channel.invokeMethod<int>('load', {
      for (final e in clips.entries) e.key.name: e.value.asset,
    });
    expect(opened, 6, reason: 'device: SoundBridge opened every clip');
    await channel.invokeMethod<void>('play', Clip.move.name);
    // An unknown clip name is ignored, not an error.
    await channel.invokeMethod<void>('play', 'nothing');
    expect(
      await channel.invokeMethod<bool>('musicStart'),
      isA<bool>(),
      reason: 'device: musicStart answers whether it started',
    );
    await channel.invokeMethod<void>('musicPause');
    await channel.invokeMethod<void>('musicStop');
    await channel.invokeMethod<void>('release');
  });

  testWidgets('a start right after an effect waits without blocking', (
    tester,
  ) async {
    await channel.invokeMethod<int>('load', {
      for (final e in clips.entries) e.key.name: e.value.asset,
    });
    // SoundPool decodes in the background; a clip plays only once ready.
    await Future<void>.delayed(const Duration(seconds: 1));
    await channel.invokeMethod<void>('play', Clip.move.name);
    final watch = Stopwatch()..start();
    final started = channel.invokeMethod<bool>('musicStart');
    // An unknown clip is a no-op call: its answer comes back only once the
    // main thread is free.
    await channel.invokeMethod<void>('play', 'nothing');
    expect(
      watch.elapsedMilliseconds,
      lessThan(300),
      reason: "device: the main thread answers during a start's wait",
    );
    expect(await started, isA<bool>(), reason: 'device: the start answers');
    expect(
      watch.elapsedMilliseconds,
      greaterThanOrEqualTo(500),
      reason: 'device: the start still waits out the effect',
    );
    await channel.invokeMethod<void>('musicStop');

    await channel.invokeMethod<void>('play', Clip.move.name);
    final waiting = channel.invokeMethod<bool>('musicStart');
    await channel.invokeMethod<void>('musicPause');
    expect(
      await waiting,
      isFalse,
      reason: 'device: a pause ends a waiting start, which did not start',
    );
    await channel.invokeMethod<void>('release');
  });

  testWidgets('the Dart player loads and plays without throwing', (
    tester,
  ) async {
    final logs = <String>[];
    final player = ChannelSoundPlayer(log: logs.add);
    await player.load(clips);
    player.play(Clip.capture);
    await tester.pump(const Duration(milliseconds: 300));
    await player.dispose();
    expect(logs, isEmpty, reason: 'device: nothing failed or was skipped');
  });

  testWidgets('an unknown method is refused', (tester) async {
    await expectLater(
      channel.invokeMethod<void>('vibrate'),
      throwsA(isA<MissingPluginException>()),
      reason: 'device: SoundBridge answers notImplemented',
    );
  });
}
