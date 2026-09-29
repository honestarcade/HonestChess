// The Android side of the app's own channel (#80), on a device or emulator:
// the real MainActivity answers each method, and refuses a plain-http link
// itself, not only through the Dart wrapper's check.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:honest_chess/platform/platform_channel.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('filesDir answers a writable directory', (tester) async {
    final path = await MethodChannelPlatform().filesDir();
    expect(path, isNotNull, reason: 'device: filesDir answered');
    final probe = File('$path/platform_channel_probe.txt');
    await probe.writeAsString('ok', flush: true);
    expect(await probe.readAsString(), 'ok');
    await probe.delete();
  });

  testWidgets('appVersion answers a name and a positive code', (tester) async {
    final version = await MethodChannelPlatform().appVersion();
    expect(version, isNotNull, reason: 'device: appVersion answered');
    expect(version!.name.trim(), isNotEmpty);
    expect(version.code, greaterThan(0));
  });

  testWidgets('Kotlin refuses an http link on its own', (tester) async {
    const channel = MethodChannel(platformChannelName);
    expect(
      await channel.invokeMethod<bool>('openUrl', {
        'url': 'http://honestarcade.com',
      }),
      isFalse,
      reason: 'device: MainActivity checks the scheme too',
    );
    expect(
      await channel.invokeMethod<bool>('openUrl', <String, Object?>{}),
      isFalse,
      reason: 'device: a missing url is refused',
    );
  });
}
