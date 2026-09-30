// The end-to-end games (#107): the real app on an Android device or
// emulator, over the device's own store, driven through the menu the way a
// player would. A game against Beginner is played, taken back, left, put
// back by a relaunch and resigned; a two-player fool's mate is played by
// drag and rematched. Statistics must count each game once.
//
// A real process kill cannot be scripted from inside `integration_test`, so
// a relaunch disposes the app and calls `main` again with a new store over
// the same directory: the game comes back from disk, not from memory. The
// owner's phone run (#110) covers a real close.
//
// The store is the device's real one, so each case wipes it at its start and
// end; `tools/e2e.sh` refuses a phone without `--allow-wipe` for that reason.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:honest_chess/data/app_store.dart';
import 'package:honest_chess/engine/engine.dart';
import 'package:honest_chess/main.dart' as app;
import 'package:honest_chess/platform/platform_channel.dart';
import 'package:honest_chess/ui/app_scope.dart';
import 'package:honest_chess/ui/game/game_controller.dart';

import '../test/support/app_harness.dart' show pumpUntilFound;

/// Every new game's computer seed.
const seed = 42;

/// The longest any one step may take: a launch, a screen, a reply.
const stepTimeout = Duration(seconds: 30);

/// How far apart the saved and the resumed clocks may read.
const clockSlackMs = 100;

/// How long you think on your turn before leaving: many times
/// [clockSlackMs], so a clock saved only at the last move reads wrong.
const thinkBeforeLeaving = Duration(seconds: 2);

/// A store over the device's own `<filesDir>/data`: each call is a new
/// instance over the same directory, as a new process would build.
AppStore deviceStore() => AppStore.onDevice(MethodChannelPlatform());

/// Deletes every document, so a case starts and ends with nothing saved.
Future<void> wipe() async {
  final store = deviceStore();
  for (final doc in StoreDoc.values) {
    await store.delete(doc);
  }
  await store.flush();
}

Finder key(String name) => find.byKey(Key(name));

/// Pumps until [finder] matches, up to [stepTimeout].
Future<void> waitFound(WidgetTester tester, Finder finder) =>
    pumpUntilFound(tester, finder, timeout: stepTimeout);

/// Pumps until [done], up to [stepTimeout]: a wait on the game rather than
/// on a widget, which `pumpUntilFound` cannot express.
Future<void> waitUntil(
  WidgetTester tester,
  bool Function() done,
  String what,
) async {
  final waited = Stopwatch()..start();
  while (!done()) {
    expect(
      waited.elapsed,
      lessThan(stepTimeout),
      reason: 'e2e: $what within $stepTimeout',
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Lets a route's transition or a card's fade finish. A running clock keeps
/// a ticker alive, so `pumpAndSettle` would never end on a timed board.
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump();
}

/// Scrolls [name] into view if it is off screen, taps it and settles.
Future<void> tapKey(WidgetTester tester, String name) async {
  final finder = key(name);
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      300,
      scrollable: find.byType(Scrollable).last,
    );
  }
  await tester.ensureVisible(finder);
  await settle(tester);
  await tester.tap(finder);
  await settle(tester);
}

/// Writes sound, music and haptics off into [store]'s settings before the
/// app reads them: a scripted game should not play out loud.
Future<void> quiet(AppStore store) async {
  await store.write(StoreDoc.settings, {
    'board': {'sfx': false, 'music': false, 'haptics': false},
  });
  await store.flush();
}

/// Launches the app over [store] and waits out the splash for the menu.
Future<void> launch(WidgetTester tester, AppStore store) async {
  app.main(seed: seed, store: store);
  await waitFound(tester, key('menu-vs-computer'));
  // The menu's fade holds the navigating flag, which ignores taps.
  await tester.pumpAndSettle();
}

/// Disposes the running app, as closing it would, over a lifecycle already
/// back in the foreground (frames stop while the app is hidden).
Future<void> close(WidgetTester tester) async {
  final scope = AppScope.of(tester.element(find.byType(Navigator).first));
  await scope.saves.flush();
  await scope.stats.idle;
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}

GameController controllerOf(WidgetTester tester) =>
    AppScope.of(tester.element(key('sq-e1'))).controller;

/// Plays [move] by tapping its from- and to-squares.
Future<void> tapMove(WidgetTester tester, Move move) async {
  await tester.tap(key('cell-${move.from.name}'));
  await tester.pump();
  await tester.tap(key('cell-${move.to.name}'));
  await tester.pump();
  if (move.promotion != null) {
    await tester.tap(key('promo-q'));
    await tester.pump();
  }
}

/// You move the first legal move in engine order; then the computer's
/// reply is waited for, so it is your turn again.
Future<void> playRound(WidgetTester tester, GameController c) async {
  final move = legalMoves(c.game.position).first;
  final played = c.game.history.length;
  await tapMove(tester, move);
  expect(
    c.game.history.length,
    played + 1,
    reason: 'e2e: the tapped move ${move.toUci()} was played',
  );
  await waitUntil(
    tester,
    () => c.game.history.length == played + 2 || c.game.isOver,
    'the computer replies',
  );
  expect(c.game.isOver, isFalse, reason: 'e2e: the game is still going');
}

/// The game's JSON without its clock, and the clock on its own.
(Map<String, Object?>, Map<String, Object?>) split(Game game) {
  final json = Map<String, Object?>.of(game.toJson());
  final clock = json.remove('clock')! as Map<String, Object?>;
  return (json, clock);
}

String textOf(WidgetTester tester, String name) =>
    tester.widget<Text>(key(name)).data!;

/// Opens Statistics from the menu.
Future<void> openStats(WidgetTester tester) async {
  await tapKey(tester, 'menu-statistics');
  await waitFound(tester, key('stats-card-games-played-value'));
}

/// From a finished game's board to the menu, by the system back: over the
/// result card the first back only lowers the card to View board, so back
/// is pressed until the menu shows, at most twice.
Future<void> backToMenu(WidgetTester tester) async {
  final menu = key('menu-statistics');
  for (var i = 0; i < 2 && menu.evaluate().isEmpty; i++) {
    await tester.binding.handlePopRoute();
    await settle(tester);
  }
  await waitFound(tester, menu);
  await settle(tester);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('against Beginner: moves, a takeback, leave, relaunch, '
      'Continue, resign; Statistics counts one game', (tester) async {
    await wipe();
    addTearDown(wipe);
    final first = deviceStore();
    await quiet(first);
    await launch(tester, first);
    expect(
      key('menu-continue'),
      findsNothing,
      reason: 'e2e: a wiped store offers no game',
    );

    await tapKey(tester, 'menu-vs-computer');
    await waitFound(tester, key('csetup-back'));
    await tapKey(tester, 'csetup-strength-beginner');
    await tapKey(tester, 'csetup-colour-white');
    await tapKey(tester, 'csetup-time-rapid');
    await tapKey(tester, 'csetup-start');
    await waitFound(tester, key('sq-e1'));
    await settle(tester);
    final c = controllerOf(tester);
    final mode = c.game.mode as VsComputer;
    expect(
      (mode.step, mode.playerColour, mode.seed),
      (Strength.beginner, Colour.white, seed),
      reason: 'e2e: the setup screen\'s choices are the game\'s',
    );
    expect(c.game.clock.control, Timed.rapid, reason: 'e2e: Rapid 10+5');

    for (var i = 0; i < 2; i++) {
      await playRound(tester, c);
    }
    final fenBefore = c.game.position.toFen();
    final movesBefore = c.game.moves.length;
    await playRound(tester, c);
    await tapKey(tester, 'tool-takeback');
    expect(
      c.game.position.toFen(),
      fenBefore,
      reason: 'e2e: the takeback undoes your move and the reply',
    );
    expect(c.game.moves.length, movesBefore);
    expect(c.game.sideToMove, Colour.white, reason: 'e2e: your turn again');
    for (var i = 0; i < 2; i++) {
      await playRound(tester, c);
    }
    expect(c.game.sideToMove, Colour.white, reason: 'e2e: left on your turn');
    // You think before leaving, so your clock has run well past the last
    // move's save: only the save made on leaving holds the time used since.
    await tester.pump(thinkBeforeLeaving);

    // Leaving: the platform's inactive, then hidden. The app pauses the
    // game and saves it; nothing is pumped while hidden, as frames stop.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await AppScope.of(tester.element(key('sq-e1'))).saves.flush();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(c.state.paused, isTrue, reason: 'e2e: leaving pauses the game');
    final (savedGame, savedClock) = split(c.game);
    final savedId = c.recorded['id'];
    expect(savedId, isA<String>(), reason: 'e2e: the game has a stats id');
    await close(tester);

    await launch(tester, deviceStore());
    expect(
      key('menu-continue'),
      findsOneWidget,
      reason: 'e2e: the relaunch offers the saved game',
    );
    await tapKey(tester, 'menu-continue');
    await waitFound(tester, key('pause-card'));
    await settle(tester);
    final resumed = controllerOf(tester);
    expect(
      identical(resumed, c),
      isFalse,
      reason: 'e2e: the relaunch built a new controller',
    );
    expect(resumed.state.paused, isTrue, reason: 'e2e: restored paused');
    final (game, clock) = split(resumed.game);
    expect(
      game,
      savedGame,
      reason: 'e2e: the resumed game is the saved one, not a new game',
    );
    for (final side in ['whiteMs', 'blackMs']) {
      expect(
        ((clock[side]! as int) - (savedClock[side]! as int)).abs(),
        lessThanOrEqualTo(clockSlackMs),
        reason: 'e2e: $side reads as it was saved',
      );
    }
    expect(
      clock['snapshots'],
      savedClock['snapshots'],
      reason: 'e2e: every move\'s clock reading came back',
    );
    expect(
      resumed.recorded['id'],
      savedId,
      reason: 'e2e: the statistics id is kept, so the game counts once',
    );

    await tapKey(tester, 'pause-resign');
    await waitFound(tester, key('result-tag'));
    await settle(tester);
    expect(textOf(tester, 'result-tag'), 'YOU LOSE');
    expect(textOf(tester, 'result-title'), 'White resigned');
    await backToMenu(tester);
    expect(
      key('menu-continue'),
      findsNothing,
      reason: 'e2e: a finished game is not offered',
    );

    await openStats(tester);
    final stats = AppScope.of(tester.element(key('stats-scroll'))).stats;
    await stats.idle;
    expect(
      (stats.document.computer.played, stats.document.computer.lost),
      (1, 1),
      reason: 'e2e: one game, lost, not two',
    );
    expect(textOf(tester, 'stats-card-games-played-value'), '1');
    expect(textOf(tester, 'stats-row-beginner-value'), '0 / 1 · 0%');
    await tester.binding.handlePopRoute();
    await waitFound(tester, key('menu-statistics'));
    await close(tester);

    await launch(tester, deviceStore());
    await openStats(tester);
    expect(
      textOf(tester, 'stats-card-games-played-value'),
      '1',
      reason: 'e2e: a relaunch counts nothing twice',
    );
    expect(textOf(tester, 'stats-row-beginner-value'), '0 / 1 · 0%');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('two players: fool\'s mate by drag, the result, a rematch; '
      'Statistics counts it for Black', (tester) async {
    await wipe();
    addTearDown(wipe);
    final store = deviceStore();
    await quiet(store);
    await launch(tester, store);

    await tapKey(tester, 'menu-two-players');
    await waitFound(tester, key('psetup-back'));
    await tapKey(tester, 'psetup-time-untimed');
    await tapKey(tester, 'psetup-start');
    await waitFound(tester, key('sq-e1'));
    await settle(tester);
    final c = controllerOf(tester);
    expect(c.game.mode, isA<TwoPlayer>());
    expect(c.game.clock.control, const Untimed());
    expect(c.options.rotateEachTurn, isFalse, reason: 'e2e: rotate is off');

    for (final uci in ['f2f3', 'e7e5', 'g2g4', 'd8h4']) {
      final from = tester.getCenter(key('cell-${uci.substring(0, 2)}'));
      final to = tester.getCenter(key('cell-${uci.substring(2)}'));
      final played = c.game.moves.length;
      await tester.timedDrag(
        key('cell-${uci.substring(0, 2)}'),
        to - from,
        const Duration(milliseconds: 400),
      );
      await settle(tester);
      expect(c.game.moves.map((m) => m.toUci()).skip(played), [
        uci,
      ], reason: 'e2e: the drag played $uci');
    }
    expect(c.game.isOver, isTrue, reason: 'e2e: fool\'s mate ends the game');

    await waitFound(tester, key('result-tag'));
    await settle(tester);
    expect(textOf(tester, 'result-tag'), 'BLACK WINS');
    expect(textOf(tester, 'result-title'), 'Black delivers checkmate');

    await tapKey(tester, 'result-rematch');
    await waitUntil(tester, () => c.game.moves.isEmpty, 'the rematch starts');
    await settle(tester);
    expect(
      key('result-card'),
      findsNothing,
      reason: 'e2e: the rematch shows a fresh board',
    );
    expect(c.game.isOver, isFalse);
    expect(c.game.mode, isA<TwoPlayer>());
    expect(c.game.clock.control, const Untimed(), reason: 'e2e: same setup');

    // Back on a live board pauses it; the pause card's Main menu leaves.
    await tester.binding.handlePopRoute();
    await waitFound(tester, key('pause-card'));
    await settle(tester);
    await tapKey(tester, 'pause-main-menu');
    await waitFound(tester, key('menu-statistics'));
    await settle(tester);
    await openStats(tester);
    final stats = AppScope.of(tester.element(key('stats-scroll'))).stats;
    await stats.idle;
    expect(
      (stats.document.two.played, stats.document.two.blackWins),
      (1, 1),
      reason: 'e2e: the mate counts once, for Black; the rematch not yet',
    );
    expect(textOf(tester, 'stats-card-games-played-value'), '1');
    expect(textOf(tester, 'stats-card-black-wins-value'), '1');
    expect(textOf(tester, 'stats-card-white-wins-value'), '0');
    await tapKey(tester, 'stats-tab-computer');
    expect(
      textOf(tester, 'stats-card-games-played-value'),
      '—',
      reason: 'e2e: the vs Computer tab is untouched',
    );
    expect(stats.document.computer.played, 0);
    await tester.pumpWidget(const SizedBox());
  });
}
