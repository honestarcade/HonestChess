import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:honest_chess/ui/theme/palette.dart';
import 'package:honest_chess/ui/widgets/external_link.dart';

import '../../support/app_harness.dart';

const _url = 'https://honestarcade.app/contribute';

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

final _pressedLog = <bool>[];

Widget _link({String url = _url}) => Scaffold(
  body: Center(
    child: ExternalLink(
      key: const Key('link'),
      url: url,
      semanticsLabel: 'SUPPORT, opens in browser',
      builder: (context, pressed) {
        _pressedLog.add(pressed);
        return SizedBox(
          width: 200,
          height: 60,
          child: Text(pressed ? 'pressed' : 'idle'),
        );
      },
    ),
  ),
);

Future<({AppHarness harness, _Routes routes})> _pump(
  WidgetTester tester, {
  Widget? child,
}) async {
  _pressedLog.clear();
  final routes = _Routes();
  final harness = await pumpUnderScope(
    tester,
    child ?? _link(),
    observers: [routes],
  );
  return (harness: harness, routes: routes);
}

Finder get _message => find.text(noBrowserText);

Future<void> _tap(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('link')));
  await tester.pump();
}

void main() {
  testWidgets('a tap asks Android to open exactly the URL, once', (
    tester,
  ) async {
    final rig = await _pump(tester);
    await _tap(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(rig.harness.platform.openUrlCalls, [_url]);
    expect(_message, findsNothing, reason: 'test: an opened link says nothing');
    expect(rig.routes.changes, 0);
  });

  testWidgets('a refused open shows "No browser found" and nothing else', (
    tester,
  ) async {
    final rig = await _pump(tester);
    rig.harness.platform.onOpenUrl = (_) async => false;
    await _tap(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));
    expect(_message, findsOneWidget);
    expect(rig.harness.platform.openUrlCalls, [_url], reason: 'no retry');
    expect(rig.routes.changes, 0, reason: 'test: a failed link navigates');
    // Floating, in the card's colours.
    final bar = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(bar.behavior, SnackBarBehavior.floating);
    expect(bar.duration, noBrowserDuration);
    expect(bar.action, isNull);
    expect(bar.backgroundColor, Palette.cardSurface);
    final shape = bar.shape! as RoundedRectangleBorder;
    expect(shape.side.color, Palette.cardEdge);
    expect(shape.borderRadius, BorderRadius.circular(14));
    // Gone after its three seconds.
    await tester.pump(noBrowserDuration);
    await tester.pumpAndSettle();
    expect(_message, findsNothing);
    expect(rig.harness.platform.openUrlCalls, [_url]);
  });

  testWidgets('a thrown error counts as not opened', (tester) async {
    final rig = await _pump(tester);
    rig.harness.platform.onOpenUrl = (_) async => throw StateError('boom');
    await _tap(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));
    expect(_message, findsOneWidget);
    await tester.pumpAndSettle(noBrowserDuration);
  });

  testWidgets('taps are ignored while a call is pending', (tester) async {
    final rig = await _pump(tester);
    final answer = Completer<bool>();
    rig.harness.platform.onOpenUrl = (_) => answer.future;
    await _tap(tester);
    await _tap(tester);
    await _tap(tester);
    expect(rig.harness.platform.openUrlCalls, [_url]);
    answer.complete(false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));
    expect(_message, findsOneWidget);
    // Taps count again once the answer is in.
    await _tap(tester);
    expect(rig.harness.platform.openUrlCalls, [_url, _url]);
    await tester.pumpAndSettle(noBrowserDuration);
  });

  testWidgets('past five seconds the link is free again and a late answer is '
      'dropped', (tester) async {
    final rig = await _pump(tester);
    final late = Completer<bool>();
    rig.harness.platform.onOpenUrl = (_) => late.future;
    await _tap(tester);
    await tester.pump(openUrlWait - const Duration(milliseconds: 10));
    await _tap(tester);
    expect(rig.harness.platform.openUrlCalls, hasLength(1));
    await tester.pump(const Duration(milliseconds: 20));
    expect(_message, findsNothing, reason: 'the wait ending says nothing');
    rig.harness.platform.onOpenUrl = (_) async => true;
    await _tap(tester);
    expect(rig.harness.platform.openUrlCalls, hasLength(2));
    late.complete(false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));
    expect(_message, findsNothing, reason: 'test: a late answer shows');
  });

  testWidgets('a second failure replaces the first message', (tester) async {
    final rig = await _pump(tester);
    rig.harness.platform.onOpenUrl = (_) async => false;
    await _tap(tester);
    await tester.pump(const Duration(milliseconds: 750));
    await tester.pump(const Duration(seconds: 2));
    await _tap(tester);
    await tester.pump(const Duration(milliseconds: 750));
    expect(_message, findsOneWidget);
    // The three seconds restarted with the second message.
    await tester.pump(const Duration(seconds: 2));
    expect(_message, findsOneWidget);
    await tester.pumpAndSettle(noBrowserDuration);
    expect(_message, findsNothing);
  });

  testWidgets('an answer after the screen has gone shows nothing', (
    tester,
  ) async {
    final rig = await _pump(tester, child: const Scaffold(body: SizedBox()));
    final answer = Completer<bool>();
    rig.harness.platform.onOpenUrl = (_) => answer.future;
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(navigator.push(MaterialPageRoute<void>(builder: (_) => _link())));
    await tester.pumpAndSettle();
    await _tap(tester);
    navigator.pop();
    await tester.pumpAndSettle();
    answer.complete(false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));
    expect(_message, findsNothing);
  });

  testWidgets('the pressed look follows the finger only', (tester) async {
    final rig = await _pump(tester);
    final answer = Completer<bool>();
    rig.harness.platform.onOpenUrl = (_) => answer.future;
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('link'))),
    );
    await tester.pump();
    expect(find.text('pressed'), findsOneWidget);
    await gesture.up();
    await tester.pump();
    expect(find.text('idle'), findsOneWidget, reason: 'not while pending');
    expect(rig.harness.platform.openUrlCalls, [_url]);
    answer.complete(true);
    await tester.pump();
  });

  testWidgets('it is one link node with its spoken text', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester);
    expect(
      tester.getSemantics(find.byKey(const Key('link'))),
      isSemantics(
        isLink: true,
        label: 'SUPPORT, opens in browser',
        hasTapAction: true,
      ),
    );
    handle.dispose();
  });
}
