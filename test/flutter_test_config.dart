// Runs before every test file (flutter_test finds it by name).
//
// Loads the app's three bundled font families from assets/fonts/, so a
// widget test lays text out in the faces the app ships rather than the test
// font, and a piece glyph missing from the piece font is a real gap.
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Family → the files pubspec.yaml registers for it.
const testFonts = {
  'Outfit': [
    'assets/fonts/outfit/Outfit-Light.ttf',
    'assets/fonts/outfit/Outfit-Regular.ttf',
    'assets/fonts/outfit/Outfit-Medium.ttf',
    'assets/fonts/outfit/Outfit-SemiBold.ttf',
    'assets/fonts/outfit/Outfit-Bold.ttf',
  ],
  'PlexMono': [
    'assets/fonts/plexmono/IBMPlexMono-Regular.ttf',
    'assets/fonts/plexmono/IBMPlexMono-Medium.ttf',
    'assets/fonts/plexmono/IBMPlexMono-SemiBold.ttf',
  ],
  'HonestPieces': ['assets/fonts/pieces/HonestPieces.ttf'],
};

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final MapEntry(key: family, value: files) in testFonts.entries) {
    final loader = FontLoader(family);
    for (final file in files) {
      final bytes = File(file).readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }
  await testMain();
}
