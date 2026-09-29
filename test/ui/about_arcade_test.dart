import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:honest_chess/ui/brand/honest_mark.dart';
import 'package:honest_chess/ui/navigation.dart';
import 'package:honest_chess/ui/screens/about_arcade_screen.dart';
import 'package:honest_chess/ui/theme/palette.dart';
import 'package:honest_chess/ui/widgets/external_link.dart';
import 'package:honest_chess/ui/widgets/screen_background.dart';

import '../flutter_test_config.dart';
import '../support/app_harness.dart';
import 'piece_font_test.dart' show cmapCodePoints;

/// Counts every route pushed or popped after the first.
class _Routes extends NavigatorObserver {
  int changes = 0;
  bool _home = false;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_home) changes++;
    _home = true;
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => changes++;
}

Finder _key(String key) => find.byKey(Key(key));

Future<({AppHarness harness, _Routes routes})> _pump(
  WidgetTester tester, {
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final routes = _Routes();
  final harness = await pumpUnderScope(
    tester,
    const AboutArcadeScreen(),
    observers: [routes],
  );
  return (harness: harness, routes: routes);
}

Future<void> _reveal(WidgetTester tester, String key) async {
  await tester.scrollUntilVisible(
    _key(key),
    200,
    scrollable: find.descendant(
      of: _key('aboutstudio-scroll'),
      matching: find.byType(Scrollable),
    ),
  );
  await tester.pump();
}

Color? _colour(WidgetTester tester, Finder text) =>
    tester.renderObject<RenderParagraph>(text).text.style?.color;

const _links = {
  'aboutstudio-support': 'https://honestarcade.app/contribute',
  'aboutstudio-link-site': 'https://honestarcade.app',
  'aboutstudio-link-github': 'https://github.com/honestarcade',
};

void main() {
  testWidgets('the header, the mark and the two paragraphs', (tester) async {
    await _pump(tester);
    expect(
      tester.widget<Text>(_key('aboutstudio-title')).data,
      'About Honest Arcade',
    );
    expect(_key('aboutstudio-back'), findsOneWidget);
    final mark = tester.widget<HonestMark>(_key('aboutstudio-mark'));
    expect(mark.withRook, isFalse, reason: 'the studio mark, not the chess');
    expect(tester.getSize(_key('aboutstudio-mark')), const Size(120, 120));
    expect(
      tester.widget<Text>(_key('aboutstudio-lead')).data,
      startsWith('Honest Arcade makes simple games and useful apps'),
    );
    expect(
      tester.widget<Text>(_key('aboutstudio-second')).data,
      'Just good software that respects your time, privacy, and device.',
    );
  });

  testWidgets('the mark scales with the width, capped at 480', (tester) async {
    await _pump(tester, size: const Size(780, 1200));
    expect(
      tester.getSize(_key('aboutstudio-mark')).width,
      closeTo(120 * 480 / 390, 1e-9),
    );
  });

  testWidgets('the Support card, the seven promises and the chips', (
    tester,
  ) async {
    await _pump(tester);
    expect(
      find.descendant(
        of: _key('aboutstudio-support'),
        matching: find.text('SUPPORT HONEST ARCADE'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _key('aboutstudio-support'),
        matching: find.textContaining('Our games stay free and ad-free'),
      ),
      findsOneWidget,
    );
    expect(
      tester.widget<Text>(_key('aboutstudio-support-link')).data,
      'honestarcade.app/contribute →',
    );
    expect(find.text('OUR PROMISES'), findsOneWidget);
    const titles = [
      'No ads. Ever.',
      'No tracking, no analytics',
      'No accounts, no sign-in',
      'No in-app purchases',
      'No permissions',
      'Open source',
      'Works offline, stays small',
    ];
    const ticks = [
      Palette.teal,
      Palette.skyBlue,
      Palette.violetText,
      Palette.teal,
      Palette.skyBlue,
      Palette.violetText,
      Palette.teal,
    ];
    for (var i = 0; i < 7; i++) {
      await _reveal(tester, 'aboutstudio-promise-$i');
      expect(
        tester.widget<Text>(_key('aboutstudio-promise-title-$i')).data,
        titles[i],
      );
      expect(tester.widget<Text>(_key('aboutstudio-tick-$i')).data, '✓');
      expect(_colour(tester, _key('aboutstudio-tick-$i')), ticks[i]);
    }
    expect(_key('aboutstudio-promise-7'), findsNothing);
    expect(
      tester.widget<Text>(_key('aboutstudio-promise-body-2')).data,
      'Your progress is kept on your device, and this app never sends it '
      'anywhere.',
    );
    expect(
      find.textContaining('unless an account is explicitly needed'),
      findsNothing,
      reason: 'test: the design\'s no-accounts wording is still shown',
    );
    await _reveal(tester, 'aboutstudio-chip-2');
    for (final (i, chip) in ['NO ADS', 'NO TRACKING', 'OPEN SOURCE'].indexed) {
      expect(
        find.descendant(
          of: _key('aboutstudio-chip-$i'),
          matching: find.text(chip),
        ),
        findsOneWidget,
      );
    }
  });

  for (final MapEntry(key: key, value: url) in _links.entries) {
    testWidgets('$key opens exactly $url, once', (tester) async {
      final rig = await _pump(tester);
      await _reveal(tester, key);
      await tester.tap(_key(key));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(rig.harness.platform.openUrlCalls, [url]);
      expect(find.text(noBrowserText), findsNothing);
      expect(rig.routes.changes, 0, reason: 'test: a link navigated');
    });

    testWidgets('$key with no browser says so and nothing else', (
      tester,
    ) async {
      final rig = await _pump(tester);
      rig.harness.platform.onOpenUrl = (_) async => false;
      await _reveal(tester, key);
      final scroll = tester
          .state<ScrollableState>(
            find.descendant(
              of: _key('aboutstudio-scroll'),
              matching: find.byType(Scrollable),
            ),
          )
          .position
          .pixels;
      await tester.tap(_key(key));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 750));
      expect(find.text(noBrowserText), findsOneWidget);
      expect(rig.harness.platform.openUrlCalls, [url], reason: 'no retry');
      expect(rig.routes.changes, 0, reason: 'test: a failed link navigated');
      expect(find.byType(AboutArcadeScreen), findsOneWidget);
      expect(
        tester
            .state<ScrollableState>(
              find.descendant(
                of: _key('aboutstudio-scroll'),
                matching: find.byType(Scrollable),
              ),
            )
            .position
            .pixels,
        scroll,
      );
      await tester.pumpAndSettle(noBrowserDuration);
      expect(find.text(noBrowserText), findsNothing);
    });
  }

  testWidgets('a pressed text link turns its text teal, not its underline', (
    tester,
  ) async {
    await _pump(tester);
    await _reveal(tester, 'aboutstudio-link-site');
    final text = _key('aboutstudio-link-site-text');
    expect(tester.widget<Text>(text).data, 'HONESTARCADE.APP ↗');
    expect(_colour(tester, text), Palette.textDim);
    final gesture = await tester.startGesture(tester.getCenter(text));
    await tester.pump();
    expect(_colour(tester, text), Palette.teal);
    final underline =
        tester
                .widget<DecoratedBox>(_key('aboutstudio-link-site-underline'))
                .decoration
            as BoxDecoration;
    expect((underline.border! as Border).bottom.color, Palette.linkUnderline);
    await gesture.cancel();
    await tester.pump();
    expect(_colour(tester, text), Palette.textDim);
  });

  testWidgets('the links take a 48 dp touch height', (tester) async {
    await _pump(tester);
    await _reveal(tester, 'aboutstudio-link-github');
    expect(
      tester.getSize(_key('aboutstudio-link-github')).height,
      greaterThanOrEqualTo(48),
    );
  });

  testWidgets('the links read their text, ↗ spoken "opens in browser"', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(tester);
    await _reveal(tester, 'aboutstudio-link-github');
    expect(
      tester.getSemantics(_key('aboutstudio-link-site')),
      isSemantics(
        isLink: true,
        label: 'honestarcade.app',
        hint: opensInBrowser,
      ),
    );
    expect(
      tester.getSemantics(_key('aboutstudio-link-github')),
      isSemantics(
        isLink: true,
        label: 'Source on GitHub',
        hint: opensInBrowser,
      ),
    );
    handle.dispose();
  });

  testWidgets('back returns to where the screen was opened from', (
    tester,
  ) async {
    await pumpUnderScope(tester, const Scaffold(body: Text('home')));
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(aboutArcadeRoute());
    await tester.pumpAndSettle();
    expect(find.byType(AboutArcadeScreen), findsOneWidget);
    await tester.tap(_key('aboutstudio-back'));
    await tester.pumpAndSettle();
    expect(find.byType(AboutArcadeScreen), findsNothing);
    expect(find.text('home'), findsOneWidget);
  });

  test('the fonts draw the screen\'s symbols ✓ → ↗ ·', () {
    for (final file in testFonts['Outfit']!) {
      expect(
        cmapCodePoints(File(file).readAsBytesSync()),
        allOf(contains(0x2713), contains(0x2192)),
        reason: 'test: $file lacks ✓ or →',
      );
    }
    for (final file in testFonts['PlexMono']!) {
      expect(
        cmapCodePoints(File(file).readAsBytesSync()),
        allOf(contains(0x2197), contains(0x00B7)),
        reason: 'test: $file lacks ↗ or ·',
      );
    }
  });

  test('the background is the design\'s ellipse, 110% × 80% at 78% 12%', () {
    const rect = Rect.fromLTWH(0, 0, 390, 844);
    final g = ScreenGradient.aboutStudio.over(rect);
    expect(g.center, const Alignment(0.56, -0.76));
    expect(g.radius, closeTo(1.1, 1e-9), reason: 'rx = 110% of the width');
    expect(g.colors, [
      Palette.gradientInner,
      Palette.screenBg,
      Palette.gradientOuter,
    ]);
    expect(g.stops, [0, .58, 1]);
    // The transform squashes the circle to ry = 80% of the height about
    // the centre: a point 1 unit below the centre maps to yScale below it.
    final m = g.transform!.transform(rect)!;
    final centreY = 0.12 * 844;
    final mapped = MatrixUtils.transformPoint(m, Offset(0, centreY + 1));
    expect(mapped.dy - centreY, closeTo(0.8 * 844 / (1.1 * 390), 1e-9));
    expect(
      MatrixUtils.transformPoint(m, Offset(0, centreY)).dy,
      closeTo(centreY, 1e-9),
    );
  });

  testWidgets('the background covers the whole window on a tall screen', (
    tester,
  ) async {
    await _pump(tester, size: const Size(390, 2000));
    expect(
      tester.getSize(find.byType(ScreenBackground)),
      const Size(390, 2000),
    );
  });
}
