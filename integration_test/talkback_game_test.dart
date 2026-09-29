// The TalkBack device test (#102): the real app on an Android device or
// emulator, as a screen reader drives it — every move made through the
// squares' semantics tap actions, never a touch on the board. An emulator's
// TalkBack cannot be relied on to be on, so the app is told it is
// (`forceAccessibleNavigation`) and speaks into a recording announcer the
// test reads. It plays fool's mate between two players and ends when the
// result is spoken.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:honest_chess/a11y/announcer.dart';
import 'package:honest_chess/data/app_store.dart';
import 'package:honest_chess/main.dart';

/// The longest any step may take before the test fails.
const stepTimeout = Duration(seconds: 30);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('fool\'s mate through semantics actions, spoken to the end', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final announcer = RecordingAnnouncer();
    registerFontLicences();
    // A memory store, so no game saved by an earlier run is offered.
    await tester.pumpWidget(
      HonestChessApp(
        store: AppStore.memory(),
        announcer: announcer,
        forceAccessibleNavigation: true,
      ),
    );

    Future<void> until(bool Function() done, String what) async {
      final waited = Stopwatch()..start();
      while (!done()) {
        expect(
          waited.elapsed,
          lessThan(stepTimeout),
          reason: 'talkback: $what within $stepTimeout',
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    Future<void> tapKey(String key) async {
      final finder = find.byKey(Key(key));
      if (finder.evaluate().isEmpty) {
        await tester.scrollUntilVisible(
          finder,
          300,
          scrollable: find.byType(Scrollable).last,
        );
      }
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.tap(finder);
      await tester.pump();
    }

    final menu = find.byKey(const Key('menu-two-players'));
    await until(() => menu.evaluate().isNotEmpty, 'the menu follows');
    await tester.pumpAndSettle();
    await tapKey('menu-two-players');
    await until(
      () =>
          find.byKey(const Key('psetup-start')).evaluate().isNotEmpty ||
          find.byKey(const Key('psetup-back')).evaluate().isNotEmpty,
      'the setup screen opens',
    );
    await tester.pumpAndSettle();
    await tapKey('psetup-start');
    final board = find.semantics.byLabel(
      'Chess board, two players, White at the bottom',
    );
    await until(() => board.evaluate().isNotEmpty, 'the board opens');
    // The board's push, before the first move.
    await tester.pump(const Duration(milliseconds: 500));

    Future<void> doubleTap(String square) async {
      tester.semantics.tap(find.semantics.byLabel(RegExp('^$square, ')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
    }

    for (final uci in ['f2f3', 'e7e5', 'g2g4', 'd8h4']) {
      await doubleTap(uci.substring(0, 2));
      await doubleTap(uci.substring(2));
    }
    await until(
      () => announcer.spoken.any((s) => s.contains('Black delivers checkmate')),
      'the result is spoken',
    );
    expect(
      announcer.spoken.where((s) => !s.endsWith('selected')),
      containsAllInOrder([
        'New game, two players',
        'White pawn to f3',
        'Black pawn to e5',
        'White pawn to g4',
        'Black queen to h4, checkmate',
        'Black wins. Black delivers checkmate.',
      ]),
    );
    expect(announcer.spoken, contains('White pawn selected'));
    semantics.dispose();
  });
}
