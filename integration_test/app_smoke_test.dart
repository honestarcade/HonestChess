// The device-level smoke test (#38, rewritten by #75 and #91, and #93 for
// the splash): the real app, launched on an Android device or emulator,
// goes splash → menu → vs Computer →
// Beginner → Start game, plays five moves against the real computer, and
// the screen keeps drawing frames while it thinks on its background isolate.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:honest_chess/data/app_store.dart';
import 'package:honest_chess/engine/engine.dart';
import 'package:honest_chess/main.dart' as app;
import 'package:honest_chess/ui/app_scope.dart';

/// The longest the computer may take to reply before the test fails.
const replyTimeout = Duration(seconds: 30);

/// The longest gap between two frames while the computer thinks.
const maxFrameGap = Duration(milliseconds: 200);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('five moves against Beginner, frames flowing while it thinks', (
    tester,
  ) async {
    // A memory store, so no game saved by an earlier run is offered.
    app.main(seed: 2026, store: AppStore.memory());
    Future<void> waitFor(Finder finder) async {
      for (var i = 0; i < 100 && finder.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(finder, findsOneWidget);
    }

    Future<void> tapAndWait(String key) async {
      final finder = find.byKey(Key(key));
      if (finder.evaluate().isEmpty) {
        await tester.scrollUntilVisible(
          finder,
          300,
          scrollable: find.byType(Scrollable).last,
        );
      }
      await tester.ensureVisible(finder);
      await tester.pump();
      await tester.tap(finder);
      await tester.pump();
    }

    // The splash shows while the saved data loads, then the menu fades in;
    // the navigating flag ignores taps until the fade ends.
    final menu = find.byKey(const Key('menu-vs-computer'));
    final launched = Stopwatch()..start();
    while (menu.evaluate().isEmpty) {
      expect(
        launched.elapsed,
        lessThan(replyTimeout),
        reason: 'smoke: the menu follows the splash within $replyTimeout',
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
    await tapAndWait('menu-vs-computer');
    await waitFor(find.byKey(const Key('csetup-back')));
    // Start goes through the navigating flag, which the setup screen's push
    // holds until its transition ends.
    await tester.pumpAndSettle();
    await tapAndWait('csetup-strength-beginner');
    await tapAndWait('csetup-start');
    await waitFor(find.byKey(const Key('sq-e1')));
    final controller = AppScope.of(
      tester.element(find.byKey(const Key('sq-e1'))),
    ).controller;
    expect(controller.game.mode, isA<VsComputer>());
    expect(
      (controller.game.mode as VsComputer).step,
      Strength.beginner,
      reason: 'smoke: the setup screen\'s step is the game\'s',
    );
    expect(
      (controller.game.mode as VsComputer).seed,
      2026,
      reason: 'smoke: main\'s seed reaches the game',
    );
    // Let the board's push finish before the first move.
    await tester.pump(const Duration(milliseconds: 500));

    var mostFrames = 0;
    for (var turn = 0; turn < 5; turn++) {
      final move = legalMoves(controller.game.position).first;
      await tester.tap(find.byKey(Key('cell-${move.from.name}')));
      await tester.pump();
      await tester.tap(find.byKey(Key('cell-${move.to.name}')));
      await tester.pump();
      if (move.promotion != null) {
        await tester.tap(find.byKey(const Key('promo-q')));
        await tester.pump();
      }
      final played = controller.game.history.length;
      expect(controller.state.thinking, isTrue, reason: 'smoke: its turn');

      final waited = Stopwatch()..start();
      final gap = Stopwatch()..start();
      var frames = 0;
      var longest = Duration.zero;
      while (controller.game.history.length == played) {
        expect(
          waited.elapsed,
          lessThan(replyTimeout),
          reason: 'smoke: the computer replies within $replyTimeout',
        );
        await tester.pump(const Duration(milliseconds: 16));
        frames++;
        if (gap.elapsed > longest) longest = gap.elapsed;
        gap.reset();
      }
      if (frames > mostFrames) mostFrames = frames;
      // The first reply follows the board's push closely (on the sudoku-dev
      // emulator, 2026-09-29, when the app still launched onto the board: a
      // 178 ms gap there, at most 73 ms in the replies after it), so the gap
      // is held from the second.
      if (turn > 0) {
        expect(
          longest,
          lessThanOrEqualTo(maxFrameGap),
          reason: 'smoke: no frame waited on the search',
        );
      }
      if (controller.game.isOver) break;
    }
    expect(
      mostFrames,
      greaterThanOrEqualTo(10),
      reason: 'smoke: frames kept coming during a reply',
    );
    expect(
      controller.game.moves.length >= 10 || controller.game.isOver,
      isTrue,
      reason: 'smoke: five moves each, or a game that ended sooner',
    );
  });
}
