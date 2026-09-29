// The navigating flag (#85): a forward action is ignored while another runs
// or while a route transition animates, and never held past the fallback.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:honest_chess/ui/navigation.dart';

import '../support/app_harness.dart';

void main() {
  test('run ignores a second action while the first is under way', () async {
    final guard = NavigationGuard();
    final first = Completer<void>();
    var ran = 0;
    final running = guard.run(() {
      ran++;
      return first.future;
    });
    expect(guard.busy, isTrue);
    expect(await guard.run(() => ran++), isFalse);
    expect(ran, 1, reason: 'navigation: the second tap is swallowed');
    first.complete();
    expect(await running, isTrue);
    expect(guard.busy, isFalse);
    expect(await guard.run(() => ran++), isTrue);
    expect(ran, 2);
  });

  test('an action that throws releases the flag', () async {
    final guard = NavigationGuard();
    await expectLater(guard.run(() => throw StateError('x')), throwsStateError);
    expect(guard.busy, isFalse);
  });

  testWidgets('a push holds the flag until its transition completes', (
    tester,
  ) async {
    final harness = await pumpUnderScope(tester, const Text('first'));
    final guard = harness.navigation;
    expect(guard.busy, isFalse);
    tester
        .state<NavigatorState>(find.byType(Navigator))
        .push(MaterialPageRoute<void>(builder: (_) => const Text('second')));
    await tester.pump();
    expect(guard.busy, isTrue, reason: 'navigation: busy during the push');
    await tester.pumpAndSettle();
    expect(guard.busy, isFalse, reason: 'navigation: released when it ends');

    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pump();
    expect(guard.busy, isTrue, reason: 'navigation: busy during the pop');
    await tester.pumpAndSettle();
    expect(guard.busy, isFalse);
  });

  testWidgets('a transition that never finishes is released after 1 s', (
    tester,
  ) async {
    final harness = await pumpUnderScope(tester, const Text('first'));
    final guard = harness.navigation;
    tester
        .state<NavigatorState>(find.byType(Navigator))
        .push(MaterialPageRoute<void>(builder: (_) => const Text('second')));
    await tester.pump();
    expect(guard.busy, isTrue);
    // Time passes with no frame, so the animation stalls part-way and only
    // the fallback timer runs.
    await tester.binding.delayed(navigationFallback);
    expect(guard.busy, isFalse, reason: 'navigation: the 1 s fallback');
    await tester.pumpAndSettle();
  });
}
