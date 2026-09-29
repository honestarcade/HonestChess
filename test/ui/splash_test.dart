import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:honest_chess/data/app_store.dart';
import 'package:honest_chess/main.dart';
import 'package:honest_chess/ui/brand/honest_mark.dart';
import 'package:honest_chess/ui/screens/menu_screen.dart';
import 'package:honest_chess/ui/screens/splash_screen.dart';
import 'package:honest_chess/ui/theme/palette.dart';

import '../support/app_harness.dart';
import '../support/gated_store.dart';
import 'game/fake_computer.dart';

Finder _key(String key) => find.byKey(Key(key));

/// Whether the menu's route is in the tree, at any opacity. A pushed page
/// is built offstage for its first frame (the hero controller measures it
/// there), so this counts it offstage too.
bool get _menuShown => find
    .byKey(const Key('menu-vs-computer'), skipOffstage: false)
    .evaluate()
    .isNotEmpty;

String _label(WidgetTester tester) =>
    tester.widget<Text>(_key('splash-label')).data!;

/// Pumps the whole app over [store] on a 390 × 844 phone, at test time 0.
Future<HonestChessAppState> _launch(
  WidgetTester tester,
  GatedStore store, {
  bool disableAnimations = false,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  if (disableAnimations) {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  }
  await tester.pumpWidget(
    HonestChessApp(
      computerFactory: FakeComputers().call,
      store: store,
      platform: FakePlatformChannel(),
    ),
  );
  return tester.state<HonestChessAppState>(find.byType(HonestChessApp));
}

Future<void> _pumpMs(WidgetTester tester, int ms) =>
    tester.pump(Duration(milliseconds: ms));

void main() {
  test('the label follows the design\'s thresholds', () {
    expect(splashLabel(0), 'SETTING UP');
    expect(splashLabel(.4499), 'SETTING UP');
    expect(splashLabel(.45), 'SORTING PIECES');
    expect(splashLabel(.8499), 'SORTING PIECES');
    expect(splashLabel(.85), 'READY');
    expect(splashLabel(1), 'READY');
  });

  testWidgets('the first frame is the launch screen\'s flat navy, the '
      'gradient fading in over 150 ms', (tester) async {
    final xml = File('android/app/src/main/res/values/colors.xml')
        .readAsStringSync();
    final hex = RegExp(r'<color name="launch_navy">#([0-9A-Fa-f]{6})</color>')
        .firstMatch(xml)!
        .group(1)!;
    await _launch(tester, GatedStore());
    final navy = tester.widget<ColoredBox>(_key('splash-navy'));
    expect(
      navy.color,
      Color(0xFF000000 | int.parse(hex, radix: 16)),
      reason: 'splash: its first frame is colors.xml\'s launch_navy',
    );
    expect(navy.color, Palette.screenBg);
    FadeTransition gradient() =>
        tester.widget<FadeTransition>(_key('splash-gradient'));
    expect(
      gradient().opacity.value,
      0,
      reason: 'splash: no gradient on the first frame',
    );
    // The rest shows at full opacity from the first frame.
    expect(_key('splash-mark'), findsOneWidget);
    expect(_key('splash-wordmark'), findsOneWidget);
    expect(_label(tester), 'SETTING UP');
    await _pumpMs(tester, 150);
    expect(gradient().opacity.value, 1);
  });

  testWidgets('the design\'s sizes: mark 132, wordmark 40, the 220 × 5 bar, '
      'and one semantics node', (tester) async {
    final handle = tester.ensureSemantics();
    await _launch(tester, GatedStore());
    expect(tester.getSize(find.byType(HonestMark)), const Size(132, 132));
    final wordmark = tester.widget<Text>(_key('splash-wordmark')).textSpan!;
    expect(wordmark.toPlainText(), 'HonestChess');
    expect(wordmark.style!.fontSize, 40);
    expect((wordmark as TextSpan).children!.single.style!.color, Palette.teal);
    expect(find.text(splashBylineText), findsOneWidget);
    expect(tester.getSize(_key('splash-bar')), const Size(220, 5));
    expect(
      tester.widget<Text>(_key('splash-label')).style!.color,
      Palette.textLabel,
    );
    expect(
      tester.getSemantics(_key('splash')),
      isSemantics(label: splashSemanticsLabel),
      reason: 'splash: one node reading "Loading Honest Chess"',
    );
    expect(
      find.bySemanticsLabel(splashBylineText),
      findsNothing,
      reason: 'splash: nothing inside it is read on its own',
    );
    handle.dispose();
  });

  testWidgets('the bar and the label follow each finished step', (
    tester,
  ) async {
    final store = GatedStore();
    await _launch(tester, store);
    double fill() => tester.getSize(_key('splash-bar-fill')).width;
    expect(fill(), 0);
    const labels = [
      'SETTING UP', // 1 of 5
      'SETTING UP', // 2
      'SORTING PIECES', // 3
      'SORTING PIECES', // 4
      'READY', // 5
    ];
    for (final (i, doc) in StoreDoc.values.indexed) {
      store.release(doc);
      await tester.pump();
      expect(_label(tester), labels[i], reason: 'splash: ${i + 1} of 5');
      // The bar glides there over 200 ms.
      await _pumpMs(tester, 200);
      expect(fill(), moreOrLessEquals(220 * (i + 1) / 5, epsilon: .01));
    }
  });

  testWidgets('instant reads: the menu comes after the 0.6 s floor and the '
      'READY hold, not before', (tester) async {
    final store = GatedStore();
    final root = await _launch(tester, store);
    store.releaseAll();
    await _pumpMs(tester, 849);
    expect(_menuShown, isFalse, reason: 'splash: no menu before 850 ms');
    expect(_label(tester), 'READY');
    await _pumpMs(tester, 2);
    expect(_menuShown, isTrue, reason: 'splash: the menu at 850 ms');
    expect(
      root.navigation.busy,
      isTrue,
      reason: 'splash: taps wait out the fade',
    );
    final fade = tester.widget<FadeTransition>(
      find
          .ancestor(
            of: find.byType(MenuScreen, skipOffstage: false),
            matching: find.byType(FadeTransition, skipOffstage: false),
          )
          .first,
    );
    expect(fade.opacity.value, lessThan(1), reason: 'splash: it fades in');
    await tester.pumpAndSettle();
    expect(find.byType(SplashScreen), findsNothing);
    expect(root.navigation.busy, isFalse);
  });

  testWidgets('a held read holds the splash; the menu follows its release by '
      'the READY hold', (tester) async {
    final store = GatedStore();
    await _launch(tester, store);
    for (final doc in StoreDoc.values) {
      if (doc != StoreDoc.gameTwo) store.release(doc);
    }
    await _pumpMs(tester, 10000);
    expect(_menuShown, isFalse, reason: 'splash: no menu before every read');
    expect(_label(tester), 'SORTING PIECES');
    store.release(StoreDoc.gameTwo);
    await _pumpMs(tester, 249);
    expect(_menuShown, isFalse, reason: 'splash: READY holds 250 ms');
    await _pumpMs(tester, 2);
    expect(_menuShown, isTrue, reason: 'splash: then the menu');
    // The fade finishes before the navigating flag's timer is checked.
    await tester.pumpAndSettle();
  });

  testWidgets('a damaged saved game completes its step, and the menu reports '
      'it', (tester) async {
    final store = GatedStore(
      AppStore.memory(
        documents: {
          StoreDoc.gameComputer: {
            'game': {'format': 'not a game'},
            'recorded': <String, Object?>{},
          },
        },
      ),
    );
    await _launch(tester, store);
    store.releaseAll();
    await _pumpMs(tester, 851);
    expect(
      _menuShown,
      isTrue,
      reason: 'splash: damage never holds the splash up',
    );
    expect(store.corruptionNotices.value, {StoreDoc.gameComputer});
    await tester.pumpAndSettle();
    expect(_key('menu-banner'), findsOneWidget);
    expect(_key('menu-continue'), findsNothing);
  });

  testWidgets('back during the splash keeps it and never leaves the app', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        calls.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final store = GatedStore();
    await _launch(tester, store);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(SplashScreen), findsOneWidget);
    expect(
      calls.map((c) => c.method),
      isNot(contains('SystemNavigator.pop')),
      reason: 'splash: back is ignored',
    );
    store.releaseAll();
    await _pumpMs(tester, 851);
    expect(_menuShown, isTrue);
    // The fade finishes before the navigating flag's timer is checked.
    await tester.pumpAndSettle();
  });

  testWidgets('sent away mid-load, the hand-over waits for the return, then '
      'holds READY afresh', (tester) async {
    final store = GatedStore();
    await _launch(tester, store);
    final binding = tester.binding;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    store.releaseAll();
    await _pumpMs(tester, 2000);
    expect(
      _menuShown,
      isFalse,
      reason: 'splash: no hand-over while the app is away',
    );
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await _pumpMs(tester, 500);
    expect(_menuShown, isFalse, reason: 'splash: inactive is not back in view');
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _pumpMs(tester, 249);
    expect(_menuShown, isFalse, reason: 'splash: a fresh READY hold');
    await _pumpMs(tester, 2);
    expect(_menuShown, isTrue, reason: 'splash: then the menu');
    // The fade finishes before the navigating flag's timer is checked.
    await tester.pumpAndSettle();
  });

  testWidgets('leaving during the READY hold restarts it on the return', (
    tester,
  ) async {
    final store = GatedStore();
    await _launch(tester, store);
    store.releaseAll();
    await _pumpMs(tester, 800);
    final binding = tester.binding;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await _pumpMs(tester, 1000);
    expect(_menuShown, isFalse);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _pumpMs(tester, 249);
    expect(_menuShown, isFalse, reason: 'splash: a fresh READY hold');
    await _pumpMs(tester, 2);
    expect(_menuShown, isTrue);
    // The fade finishes before the navigating flag's timer is checked.
    await tester.pumpAndSettle();
  });

  testWidgets('with animations off: the gradient from the first frame, the '
      'bar jumps, and the menu cuts in at the same instants', (tester) async {
    final store = GatedStore();
    final root = await _launch(tester, store, disableAnimations: true);
    expect(
      tester.widget<FadeTransition>(_key('splash-gradient')).opacity.value,
      1,
      reason: 'splash: no gradient fade without animations',
    );
    store.release(StoreDoc.settings);
    await tester.pump();
    expect(tester.getSize(_key('splash-bar-fill')).width, 44);
    store.releaseAll();
    await _pumpMs(tester, 849);
    expect(_menuShown, isFalse, reason: 'splash: the floor and hold stay');
    await _pumpMs(tester, 2);
    expect(_menuShown, isTrue);
    final fade = tester.widget<FadeTransition>(
      find
          .ancestor(
            of: find.byType(MenuScreen, skipOffstage: false),
            matching: find.byType(FadeTransition, skipOffstage: false),
          )
          .first,
    );
    expect(
      fade.opacity.value,
      1,
      reason: 'splash: the menu is opaque on its first frame',
    );
    expect(root.navigation.busy, isFalse);
    await tester.pumpAndSettle();
  });
}
