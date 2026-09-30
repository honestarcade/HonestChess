import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

import 'package:honest_chess/platform/platform_channel.dart';
import 'package:honest_chess/ui/brand/honest_mark.dart';
import 'package:honest_chess/ui/brand/links.dart';
import 'package:honest_chess/ui/content/about_content.dart';
import 'package:honest_chess/ui/navigation.dart';
import 'package:honest_chess/ui/screens/about_app_screen.dart';
import 'package:honest_chess/ui/screens/about_arcade_screen.dart';
import 'package:honest_chess/ui/theme/palette.dart';
import 'package:honest_chess/ui/widgets/external_link.dart';

import '../support/app_harness.dart';

Finder _key(String key) => find.byKey(Key(key));

/// Pumps About the App on a 390×844 view, pushed above a plain home so
/// back has somewhere to go, with [version] answering `appVersion`.
Future<AppHarness> _pump(
  WidgetTester tester, {
  Future<AppVersion?> Function()? version,
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final platform = FakePlatformChannel();
  if (version != null) platform.onAppVersion = version;
  final harness = await pumpUnderScope(
    tester,
    const Scaffold(body: Text('home')),
    platform: platform,
  );
  unawaited(
    tester.state<NavigatorState>(find.byType(Navigator)).push(aboutAppRoute()),
  );
  await tester.pumpAndSettle();
  return harness;
}

String _version(WidgetTester tester) =>
    tester.widget<Text>(_key('aboutapp-version')).data!;

Color? _colour(WidgetTester tester, Finder text) =>
    tester.renderObject<RenderParagraph>(text).text.style?.color;

void main() {
  testWidgets('the header and the app card with the chess mark', (
    tester,
  ) async {
    await _pump(tester);
    expect(tester.widget<Text>(_key('aboutapp-title')).data, 'About the App');
    expect(_key('aboutapp-back'), findsOneWidget);
    final mark = tester.widget<HonestMark>(_key('aboutapp-mark'));
    expect(mark.withRook, isTrue, reason: 'the chess mark, not the studio');
    expect(tester.getSize(_key('aboutapp-mark')), const Size(48, 48));
    final tile = tester.widget<Container>(_key('aboutapp-mark-tile'));
    expect((tile.decoration! as BoxDecoration).color, Palette.onTeal);
    expect(tester.widget<Text>(_key('aboutapp-name')).data, 'Honest Chess');
  });

  testWidgets('the version line reads v<name> · OFFLINE', (tester) async {
    await _pump(
      tester,
      version: () async => const AppVersion(name: 'v0.1.0', code: 1),
    );
    expect(_version(tester), 'v0.1.0 · OFFLINE');
    expect(
      find.textContaining('vv'),
      findsNothing,
      reason: 'test: the leading v was doubled',
    );
  });

  final unknown = <String, Future<AppVersion?> Function()>{
    'pending': () => Completer<AppVersion?>().future,
    'null': () async => null,
    'failing': () async => throw PlatformException(code: 'x'),
    'blank': () async => const AppVersion(name: '  ', code: 3),
  };
  for (final MapEntry(key: name, value: answer) in unknown.entries) {
    testWidgets('a $name version shows OFFLINE alone', (tester) async {
      await _pump(tester, version: answer);
      expect(_version(tester), 'OFFLINE');
      expect(
        find.textContaining('v?', findRichText: true),
        findsNothing,
        reason: 'test: an unknown version showed a placeholder',
      );
    });
  }

  testWidgets('appVersion is asked once per visit', (tester) async {
    var calls = 0;
    await _pump(
      tester,
      version: () async {
        calls++;
        return const AppVersion(name: '0.1.0', code: 1);
      },
    );
    await tester.drag(_key('aboutapp-scroll'), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(calls, 1);
  });

  testWidgets('no size is shown', (tester) async {
    await _pump(tester);
    expect(
      find.textContaining('MB', findRichText: true),
      findsNothing,
      reason: 'test: the design\'s fixed app size is shown',
    );
    expect(
      find.descendant(
        of: _key('aboutapp-card'),
        matching: find.textContaining('OFFLINE', findRichText: true),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the description and the six features, two corrected', (
    tester,
  ) async {
    await _pump(tester);
    expect(
      tester.widget<Text>(_key('aboutapp-description')).data,
      startsWith('Chess, complete and offline.'),
    );
    expect(find.text("WHAT'S IN IT"), findsOneWidget);
    expect(features.map((f) => f.title), [
      'Every rule, no shortcuts',
      'Five strength steps',
      'Pass-and-play for two',
      'Clocks that behave',
      'Board you can live with',
      'Honest statistics',
    ]);
    for (final feature in features) {
      await tester.scrollUntilVisible(
        find.text(feature.body),
        200,
        scrollable: find.descendant(
          of: _key('aboutapp-scroll'),
          matching: find.byType(Scrollable),
        ),
      );
      expect(find.text(feature.title), findsOneWidget);
    }
    expect(features.first.body, contains('threefold repetition'));
    expect(features.last.body, contains('sends them nowhere'));
    expect(
      find.textContaining('nowhere else'),
      findsNothing,
      reason: 'test: the design\'s uncorrected statistics wording is shown',
    );
  });

  testWidgets('the seven promise chips, each with its tick', (tester) async {
    await _pump(tester);
    await tester.ensureVisible(_key('aboutapp-promises'));
    await tester.pumpAndSettle();
    expect(find.text('THE HONEST PROMISES'), findsOneWidget);
    const chips = [
      'NO ADS',
      'NO TRACKING',
      'NO ACCOUNTS',
      'NO PURCHASES',
      'NO PERMISSIONS',
      'OPEN SOURCE',
      'WORKS OFFLINE',
    ];
    final panel = _key('aboutapp-promises-panel');
    for (final chip in chips) {
      expect(
        find.descendant(of: panel, matching: find.text(chip)),
        findsOneWidget,
      );
    }
    expect(
      find.descendant(of: panel, matching: find.text('✓')),
      findsNWidgets(7),
    );
  });

  testWidgets('the promises button opens About Honest Arcade once, and back '
      'returns here', (tester) async {
    await _pump(tester);
    await tester.ensureVisible(_key('aboutapp-promises'));
    await tester.pumpAndSettle();
    // The second tap lands while the first push runs; the Navigator's own
    // pointer absorption would hide a missing guard from a real tap.
    final tap = tester
        .widget<GestureDetector>(_key('aboutapp-promises'))
        .onTap!;
    tap();
    tap();
    await tester.pumpAndSettle();
    expect(find.byType(AboutArcadeScreen), findsOneWidget);
    await tester.tap(_key('aboutstudio-back'));
    await tester.pumpAndSettle();
    expect(find.byType(AboutArcadeScreen), findsNothing);
    expect(find.byType(AboutAppScreen), findsOneWidget);
    expect(
      find.byType(AboutArcadeScreen, skipOffstage: false),
      findsNothing,
      reason: 'test: a double tap left a second About Honest Arcade',
    );
  });

  testWidgets('the promises button shows a teal border while pressed and '
      'takes 48 dp', (tester) async {
    await _pump(tester);
    await tester.ensureVisible(_key('aboutapp-promises'));
    await tester.pumpAndSettle();
    Color border() =>
        ((tester.widget<Container>(_key('aboutapp-promises-box')).decoration!
                        as BoxDecoration)
                    .border!
                as Border)
            .top
            .color;
    expect(border(), Palette.accentEdge);
    final gesture = await tester.startGesture(
      tester.getCenter(_key('aboutapp-promises')),
    );
    await tester.pump();
    expect(border(), Palette.teal);
    await gesture.cancel();
    await tester.pump();
    expect(border(), Palette.accentEdge);
    expect(
      tester.getSize(_key('aboutapp-promises')).height,
      greaterThanOrEqualTo(48),
    );
  });

  const links = {
    'aboutapp-link-arcade': 'https://honestarcade.app',
    'aboutapp-link-source': 'https://github.com/honestarcade/HonestChess',
  };
  for (final MapEntry(key: key, value: url) in links.entries) {
    testWidgets('$key opens exactly $url and stays here', (tester) async {
      final harness = await _pump(tester);
      await tester.ensureVisible(_key(key));
      await tester.pumpAndSettle();
      expect(tester.getSize(_key(key)).height, greaterThanOrEqualTo(48));
      await tester.tap(_key(key));
      await tester.pump();
      expect(harness.platform.openUrlCalls, [url]);
      expect(find.byType(AboutAppScreen), findsOneWidget);
    });
  }

  testWidgets('MADE BY and the links read in order, ↗ spoken', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester);
    await tester.ensureVisible(_key('aboutapp-link-source'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(_key('aboutapp-link-arcade-text')).data,
      'HONEST ARCADE ↗',
    );
    expect(
      tester.widget<Text>(_key('aboutapp-link-source-text')).data,
      'SOURCE ON GITHUB ↗',
    );
    expect(_colour(tester, _key('aboutapp-link-source-text')), Palette.textDim);
    expect(find.text('MADE BY'), findsOneWidget);
    expect(
      tester.getSemantics(_key('aboutapp-link-arcade')),
      isSemantics(isLink: true, label: 'Honest Arcade', hint: opensInBrowser),
    );
    expect(
      tester.getSemantics(_key('aboutapp-link-source')),
      isSemantics(
        isLink: true,
        label: 'Source on GitHub',
        hint: opensInBrowser,
      ),
    );
    expect(
      tester.getSemantics(_key('aboutapp-promises')),
      isSemantics(isButton: true, label: 'Honest Arcade Promises'),
    );
    handle.dispose();
  });

  // #166: each link used to fill the row's width, so the two links sat on
  // lines of their own at any width.
  for (final width in [320.0, 360.0, 390.0]) {
    testWidgets('MADE BY and both links share one line at ${width.toInt()} dp '
        'and 1.0× text', (tester) async {
      await _pump(tester, size: Size(width, 844));
      await tester.ensureVisible(_key('aboutapp-link-source'));
      await tester.pumpAndSettle();
      final parts = [
        tester.getRect(find.text('MADE BY')),
        tester.getRect(_key('aboutapp-link-arcade-text')),
        tester.getRect(find.text('·')),
        tester.getRect(_key('aboutapp-link-source-text')),
      ];
      for (final part in parts.skip(1)) {
        expect(
          (part.center.dy - parts.first.center.dy).abs(),
          lessThan(1),
          reason: 'made-by: $part is on MADE BY\'s line at $width dp',
        );
      }
      for (var i = 1; i < parts.length; i++) {
        expect(
          parts[i].left,
          greaterThan(parts[i - 1].right),
          reason: 'made-by: part $i sits right of part ${i - 1} at $width dp',
        );
      }
      final arcade = tester.getRect(_key('aboutapp-link-arcade'));
      final source = tester.getRect(_key('aboutapp-link-source'));
      expect(
        arcade.right,
        lessThanOrEqualTo(source.left),
        reason: 'made-by: the links\' touch areas do not overlap',
      );
      final scroll = tester.getRect(_key('aboutapp-scroll'));
      final inset = 20 * width / 390;
      expect(
        source.right,
        lessThanOrEqualTo(scroll.right - inset + .01),
        reason: 'made-by: the row fits inside the column at $width dp',
      );
    });
  }

  testWidgets('back returns to where the screen was opened from', (
    tester,
  ) async {
    await _pump(tester);
    await tester.tap(_key('aboutapp-back'));
    await tester.pumpAndSettle();
    expect(find.byType(AboutAppScreen), findsNothing);
    expect(find.text('home'), findsOneWidget);
  });

  test('appSourceUrl is this repository, as .n8/config.yml names it', () {
    final config =
        loadYaml(File('.n8/config.yml').readAsStringSync()) as YamlMap;
    expect(appSourceUrl, 'https://github.com/${config['repo']}');
  });
}
