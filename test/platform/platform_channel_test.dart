import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:honest_chess/platform/platform_channel.dart';

import '../support/fake_platform_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(platformChannelName);
  final calls = <MethodCall>[];

  void answer(Future<Object?> Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) {
          calls.add(call);
          return handler(call);
        });
  }

  setUp(calls.clear);
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  group('filesDir', () {
    test('answers the path Android gives, with no arguments', () async {
      answer((_) async => '/data/user/0/com.honestarcade.chess/files');
      expect(
        await MethodChannelPlatform().filesDir(),
        '/data/user/0/com.honestarcade.chess/files',
      );
      expect(calls.single.method, 'filesDir');
      expect(calls.single.arguments, isNull);
    });

    test('null on a platform error, a null or blank path', () async {
      answer((_) async => throw PlatformException(code: 'unavailable'));
      expect(await MethodChannelPlatform().filesDir(), isNull);
      answer((_) async => null);
      expect(await MethodChannelPlatform().filesDir(), isNull);
      answer((_) async => '  ');
      expect(await MethodChannelPlatform().filesDir(), isNull);
    });

    test('null when no Android side answers at all', () async {
      expect(await MethodChannelPlatform().filesDir(), isNull);
    });
  });

  group('openUrl', () {
    test('sends the URL in a map and answers what Android says', () async {
      answer((_) async => true);
      final platform = MethodChannelPlatform();
      expect(await platform.openUrl('https://honestarcade.com/chess'), isTrue);
      expect(calls.single.method, 'openUrl');
      expect(calls.single.arguments, {'url': 'https://honestarcade.com/chess'});
      answer((_) async => false);
      expect(
        await platform.openUrl('https://honestarcade.com'),
        isFalse,
        reason: 'platform: false when Android could not open it',
      );
    });

    test('refuses anything but https with a host, without calling', () async {
      answer((_) async => true);
      final platform = MethodChannelPlatform();
      for (final url in [
        'http://honestarcade.com',
        'mailto:a@b.c',
        'https://',
        'https:///path',
        'intent://x',
        'not a url',
        '',
      ]) {
        expect(await platform.openUrl(url), isFalse, reason: url);
      }
      expect(calls, isEmpty, reason: 'platform: refused before asking');
    });

    test('false on a platform error, a missing plugin or null', () async {
      answer((_) async => throw PlatformException(code: 'x'));
      expect(await MethodChannelPlatform().openUrl('https://a.b'), isFalse);
      answer((_) async => null);
      expect(await MethodChannelPlatform().openUrl('https://a.b'), isFalse);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      expect(await MethodChannelPlatform().openUrl('https://a.b'), isFalse);
    });
  });

  group('appVersion', () {
    test('reads the name and the code, and caches the first answer', () async {
      answer((_) async => {'name': '0.1.0', 'code': 1});
      final platform = MethodChannelPlatform();
      expect(
        await platform.appVersion(),
        const AppVersion(name: '0.1.0', code: 1),
      );
      expect(calls.single.method, 'appVersion');
      answer((_) async => {'name': '9.9.9', 'code': 99});
      expect(
        await platform.appVersion(),
        const AppVersion(name: '0.1.0', code: 1),
      );
    });

    test('a failure is not cached', () async {
      answer((_) async => throw PlatformException(code: 'unavailable'));
      final platform = MethodChannelPlatform();
      expect(await platform.appVersion(), isNull);
      answer((_) async => {'name': '0.1.0', 'code': 1});
      expect(await platform.appVersion(), isNotNull);
    });

    test('null for a null, blank or ill-typed answer', () async {
      for (final bad in <Object?>[
        null,
        {'name': ' ', 'code': 1},
        {'name': '0.1.0'},
        {'name': '0.1.0', 'code': '1'},
        {'code': 1},
      ]) {
        answer((_) async => bad);
        expect(
          await MethodChannelPlatform().appVersion(),
          isNull,
          reason: '$bad',
        );
      }
    });

    test('null with no Android side', () async {
      expect(await MethodChannelPlatform().appVersion(), isNull);
    });

    testWidgets('null when Android does not answer within 2 s', (tester) async {
      final never = Completer<Object?>();
      answer((_) => never.future);
      AppVersion? got = const AppVersion(name: 'unset', code: 0);
      var done = false;
      unawaited(
        MethodChannelPlatform().appVersion().then((v) {
          got = v;
          done = true;
        }),
      );
      await tester.pump(appVersionTimeout - const Duration(milliseconds: 1));
      expect(done, isFalse, reason: 'platform: still waiting before 2 s');
      await tester.pump(const Duration(milliseconds: 2));
      expect(done, isTrue);
      expect(got, isNull);
    });
  });

  group('AppVersion.displayName', () {
    const cases = {
      '0.1.0': '0.1.0',
      'v0.1.0': '0.1.0',
      'V0.1.0': '0.1.0',
      ' 0.2.0-rc.1 ': '0.2.0-rc.1',
      'v': null,
      '': null,
      'vv1': 'v1',
    };
    for (final MapEntry(key: name, value: shown) in cases.entries) {
      test('"$name" shows as ${shown == null ? 'nothing' : '"$shown"'}', () {
        expect(AppVersion(name: name, code: 1).displayName, shown);
      });
    }
  });

  group('the test fake', () {
    test('records every URL and refuses as production does', () async {
      final fake = FakePlatformChannel();
      expect(await fake.openUrl('https://a.b'), isTrue);
      expect(await fake.openUrl('http://a.b'), isFalse);
      fake.onOpenUrl = (_) async => false;
      expect(await fake.openUrl('https://a.b'), isFalse);
      expect(fake.openUrlCalls, ['https://a.b', 'http://a.b', 'https://a.b']);
      expect(await fake.filesDir(), isNull);
      expect(
        await fake.appVersion(),
        const AppVersion(name: '1.2.3', code: 1034),
      );
    });
  });
}
