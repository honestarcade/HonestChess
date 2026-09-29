// The pause card, auto-pause and the draw offer (#77), driven by a fake
// time source and the fake computer. The complements: no time passes while
// paused, a finished game is never paused, a declined or failed offer never
// ends the game, an offer is refused before each side has moved and again
// until the next move after a decline, and a promotion open at the pause
// is not played. Where Rules, Settings and Main menu lead is tested in
// test/ui/game_cards_navigation_test.dart (#92).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:honest_chess/engine/engine.dart' hide play;
import 'package:honest_chess/ui/game/computer_turns.dart';
import 'package:honest_chess/ui/game/game_controller.dart';
import 'package:honest_chess/ui/game/pause_overlay.dart';
import 'package:honest_chess/ui/theme/palette.dart';

import 'computer_turns_test.dart' show asWhite, moves, pumpVs;
import 'fake_computer.dart';
import 'player_panel_test.dart'
    show FakeClock, Harness, clockOf, play, pumpGame, text, tickers;

final _overlay = find.byKey(const Key('pause-overlay'));
final _draw = find.byKey(const Key('pause-draw'));

/// Taps the pause pill and waits out the card's fade.
Future<void> pausePill(WidgetTester tester, FakeClock clock) async {
  await tester.tap(find.byKey(const Key('pause-pill')));
  await tester.pump();
  await clock.advance(pauseFadeDuration);
}

/// Waits out the card's fade, a frame's slack, and the frame that then
/// removes it.
Future<void> fadeOut(WidgetTester tester, FakeClock clock) async {
  await clock.advance(pauseFadeDuration + const Duration(milliseconds: 16));
  await tester.pump();
}

Future<void> pressCard(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(Key(key)));
  await tester.pump();
}

bool live(WidgetTester tester, String key) =>
    tester.widget<InkWell>(find.byKey(Key(key))).onTap != null;

/// Leaves the app as far as [state] (inactive or hidden), passing through
/// every state between, as the platform does; the test's end comes back.
Future<void> leave(WidgetTester tester, AppLifecycleState state) async {
  addTearDown(() => comeBack(tester));
  for (final step in [AppLifecycleState.inactive, AppLifecycleState.hidden]) {
    tester.binding.handleAppLifecycleStateChanged(step);
    if (step == state) break;
  }
  await tester.pump();
}

/// Returns to the app from wherever [leave] went.
Future<void> comeBack(WidgetTester tester) async {
  final binding = tester.binding;
  if (binding.lifecycleState == AppLifecycleState.hidden) {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  }
  if (binding.lifecycleState == AppLifecycleState.inactive) {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  }
  await tester.pump();
}

/// Answers the computer's pending request with [uci] and waits out its
/// thinking floor, so the move lands.
Future<void> reply(Harness h, FakeComputers fakes, String uci) async {
  fakes.current.last.move(uci);
  await h.clock.advance(minThinkTime);
}

/// You (White) and the computer have each moved once: 1. e4 e5.
Future<(Harness, FakeComputers)> bothMoved(WidgetTester tester) async {
  final (h, fakes) = await pumpVs(tester);
  await play(tester, h.controller, 'e2e4');
  await reply(h, fakes, 'e7e5');
  expect(moves(h.controller), ['e2e4', 'e7e5']);
  return (h, fakes);
}

void main() {
  group('pausing', () {
    testWidgets('the pill opens the card; no time passes while paused', (
      tester,
    ) async {
      final h = await pumpGame(tester, timeControl: Timed.rapid);
      await play(tester, h.controller, 'e2e4');
      await h.clock.advance(const Duration(seconds: 3));
      expect(_overlay, findsNothing, reason: 'pause: no card before a pause');
      await pausePill(tester, h.clock);
      expect(_overlay, findsOneWidget);
      expect(h.controller.state.paused, isTrue);
      final white = h.controller.remaining(Colour.white);
      final black = h.controller.remaining(Colour.black);
      final shown = clockOf(tester, Colour.black);
      await h.clock.advance(const Duration(seconds: 90));
      expect(
        h.controller.remaining(Colour.white),
        white,
        reason: 'pause: White\'s clock moved while paused',
      );
      expect(
        h.controller.remaining(Colour.black),
        black,
        reason: 'pause: Black\'s running clock moved while paused',
      );
      expect(clockOf(tester, Colour.black), shown);
      expect(tickers, 0, reason: 'pause: something still ticks while paused');
      expect(
        find.byKey(const Key('board')),
        findsOneWidget,
        reason: 'pause: the board stays behind the card',
      );
      expect(
        Palette.scrim.a,
        lessThan(1),
        reason: 'pause: the scrim lets the board show through',
      );
    });

    testWidgets('Resume continues the clocks exactly where they stopped', (
      tester,
    ) async {
      final h = await pumpGame(tester, timeControl: Timed.rapid);
      await play(tester, h.controller, 'e2e4');
      await h.clock.advance(const Duration(seconds: 3));
      await pausePill(tester, h.clock);
      final black = h.controller.remaining(Colour.black)!;
      await h.clock.advance(const Duration(minutes: 5));
      await pressCard(tester, 'pause-resume');
      expect(h.controller.state.paused, isFalse);
      expect(h.controller.remaining(Colour.black), black);
      await h.clock.advance(const Duration(seconds: 1));
      expect(
        h.controller.remaining(Colour.black),
        black - const Duration(seconds: 1),
        reason: 'resume: the clock picked up from where it stopped',
      );
      await fadeOut(tester, h.clock);
      expect(_overlay, findsNothing, reason: 'resume: the card stayed up');
    });

    testWidgets('the scrim (over the top bar) and Android back resume', (
      tester,
    ) async {
      final h = await pumpGame(tester, timeControl: Timed.rapid);
      await pausePill(tester, h.clock);
      // The pill's own spot, now under the scrim.
      await tester.tapAt(const Offset(20, 20));
      await tester.pump();
      expect(h.controller.state.paused, isFalse, reason: 'scrim: not resumed');
      await h.clock.advance(pauseFadeDuration);
      await pausePill(tester, h.clock);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(h.controller.state.paused, isFalse, reason: 'back: not resumed');
      expect(
        find.byKey(const Key('pause-pill')),
        findsOneWidget,
        reason: 'back: left the play screen',
      );
    });

    testWidgets('focus moves to Resume', (tester) async {
      final h = await pumpGame(tester);
      await pausePill(tester, h.clock);
      expect(
        Focus.of(tester.element(find.text('Resume'))).hasPrimaryFocus,
        isTrue,
      );
    });

    testWidgets('pausing while the promotion card is open closes it unplayed', (
      tester,
    ) async {
      final h = await pumpGame(tester, fen: '8/4P3/8/8/8/8/k7/4K3 w - - 0 1');
      expect(h.controller.move(Square.parse('e7'), Square.parse('e8')), isTrue);
      await tester.pump();
      expect(h.controller.state.pendingPromotion, isNotNull);
      await pausePill(tester, h.clock);
      expect(h.controller.state.pendingPromotion, isNull);
      expect(h.controller.game.moves, isEmpty, reason: 'pause: e8 was played');
      expect(
        h.controller.game.position.pieceAt(Square.parse('e7')),
        Piece.whitePawn,
      );
      expect(_overlay, findsOneWidget);
    });

    testWidgets('the pill is disabled once the game is over', (tester) async {
      final h = await pumpGame(tester);
      expect(h.controller.resign(), isTrue);
      await tester.pump();
      await tester.tap(find.byKey(const Key('pause-pill')));
      await tester.pump();
      expect(h.controller.state.paused, isFalse);
      expect(_overlay, findsNothing, reason: 'pause: a finished game paused');
    });

    testWidgets('an untimed game before any move pauses as usual', (
      tester,
    ) async {
      final h = await pumpGame(tester);
      await pausePill(tester, h.clock);
      expect(_overlay, findsOneWidget);
    });
  });

  group('the card', () {
    testWidgets('meta line vs the computer: VS CLUB · RAPID 10+5 · MOVE 12', (
      tester,
    ) async {
      final h = await pumpGame(
        tester,
        mode: asWhite,
        timeControl: Timed.rapid,
        fen:
            'r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 12',
      );
      await pausePill(tester, h.clock);
      expect(text(tester, 'pause-meta'), 'VS CLUB · RAPID 10+5 · MOVE 12');
      expect(find.text('Claim a draw'), findsOneWidget);
    });

    testWidgets('meta line between two players', (tester) async {
      final h = await pumpGame(tester);
      await pausePill(tester, h.clock);
      expect(text(tester, 'pause-meta'), 'TWO PLAYERS · UNTIMED · MOVE 1');
      expect(find.text('Agree a draw'), findsOneWidget);
    });

    testWidgets('Resume, the draw, Resign, Rules, Settings and Main menu', (
      tester,
    ) async {
      final h = await pumpGame(tester);
      await pausePill(tester, h.clock);
      expect(find.text('Paused'), findsOneWidget);
      const keys = [
        'pause-resume',
        'pause-draw',
        'pause-resign',
        'pause-rules',
        'pause-settings',
        'pause-main-menu',
      ];
      for (final key in keys) {
        expect(find.byKey(Key(key)), findsOneWidget, reason: 'card: $key');
      }
      for (final label in ['Rules', 'Settings', 'Main menu']) {
        expect(find.text(label), findsOneWidget, reason: 'card: "$label"');
      }
      expect(
        find.descendant(of: _overlay, matching: find.byType(InkWell)),
        findsNWidgets(keys.length),
        reason: 'card: a button beyond the design\'s six',
      );
    });

    testWidgets('Resign ends the game as a resignation and closes the card', (
      tester,
    ) async {
      final h = await pumpGame(tester, timeControl: Timed.rapid);
      await play(tester, h.controller, 'e2e4');
      await pausePill(tester, h.clock);
      await pressCard(tester, 'pause-resign');
      expect(
        h.controller.game.status,
        const Win(Colour.white, GameEndReason.resignation),
      );
      expect(h.controller.state.paused, isFalse);
      await fadeOut(tester, h.clock);
      expect(_overlay, findsNothing);
    });
  });

  group('two players', () {
    testWidgets('Agree a draw is unavailable until each side has moved', (
      tester,
    ) async {
      final h = await pumpGame(tester, timeControl: Timed.rapid);
      for (final uci in [null, 'e2e4']) {
        if (uci != null) {
          await pressCard(tester, 'pause-resume');
          await h.clock.advance(pauseFadeDuration);
          await play(tester, h.controller, uci);
        }
        await pausePill(tester, h.clock);
        expect(live(tester, 'pause-draw'), isFalse);
        expect(h.controller.drawOffer, DrawOffer.tooEarly);
        expect(text(tester, 'pause-draw-hint'), 'After both sides have moved');
        await tester.tap(_draw, warnIfMissed: false);
        await tester.pump();
        expect(
          h.controller.game.isOver,
          isFalse,
          reason: 'draw: agreed before each side had moved',
        );
      }
      expect(await h.controller.offerDraw(), isFalse);
      expect(h.controller.game.isOver, isFalse);
    });

    testWidgets('one tap ends the game drawn by agreement', (tester) async {
      final h = await pumpGame(tester, timeControl: Timed.rapid);
      await play(tester, h.controller, 'e2e4');
      await play(tester, h.controller, 'e7e5');
      await pausePill(tester, h.clock);
      expect(live(tester, 'pause-draw'), isTrue);
      expect(find.byKey(const Key('pause-draw-hint')), findsNothing);
      await pressCard(tester, 'pause-draw');
      expect(h.controller.game.status, const Draw(GameEndReason.agreement));
      expect(h.controller.state.paused, isFalse);
      await fadeOut(tester, h.clock);
      expect(_overlay, findsNothing);
    });
  });

  group('vs the computer', () {
    testWidgets('unavailable until each side has moved', (tester) async {
      final (h, fakes) = await pumpVs(tester);
      await pausePill(tester, h.clock);
      expect(live(tester, 'pause-draw'), isFalse);
      expect(text(tester, 'pause-draw-hint'), 'After both sides have moved');
      expect(await h.controller.offerDraw(), isFalse);
      expect(fakes.current.draws, isEmpty, reason: 'draw: asked too early');
    });

    testWidgets('accepted: the game ends drawn by agreement', (tester) async {
      final (h, fakes) = await bothMoved(tester);
      await pausePill(tester, h.clock);
      await pressCard(tester, 'pause-draw');
      final draw = fakes.current.draws.single;
      expect(
        draw.game.position.key,
        h.controller.game.position.key,
        reason: 'draw: the computer was asked about another position',
      );
      expect(h.controller.state.drawAsking, isTrue);
      expect(find.byKey(const Key('pause-draw-spinner')), findsOneWidget);
      for (final key in ['pause-resume', 'pause-draw', 'pause-resign']) {
        expect(live(tester, key), isFalse, reason: 'asking: $key is live');
      }
      // Back and the scrim are shut while it answers.
      await tester.binding.handlePopRoute();
      await tester.tapAt(const Offset(20, 20));
      await tester.pump();
      expect(h.controller.state.paused, isTrue);
      expect(h.controller.game.isOver, isFalse);
      draw.accept();
      await tester.pump();
      expect(h.controller.game.status, const Draw(GameEndReason.agreement));
      expect(h.controller.state.paused, isFalse);
      await fadeOut(tester, h.clock);
      expect(_overlay, findsNothing);
    });

    testWidgets('declined: "Club declines — play on" for 2 s, then play', (
      tester,
    ) async {
      final (h, fakes) = await bothMoved(tester);
      await play(tester, h.controller, 'g1f3');
      // The computer is thinking; claiming now cancels its search.
      final computer = fakes.current;
      final asked = computer.requests.length;
      final cancels = computer.cancels;
      await pausePill(tester, h.clock);
      expect(
        computer.cancels,
        cancels + 1,
        reason: 'pause: search not cancelled',
      );
      await pressCard(tester, 'pause-draw');
      computer.draws.single.decline();
      await tester.pump();
      expect(h.controller.game.isOver, isFalse, reason: 'draw: a no ended it');
      expect(text(tester, 'pause-declined'), 'Club declines — play on');
      expect(h.controller.state.paused, isTrue);
      await h.clock.advance(drawDeclineShown - const Duration(milliseconds: 1));
      expect(h.controller.state.paused, isTrue);
      await h.clock.advance(const Duration(milliseconds: 1));
      expect(h.controller.state.paused, isFalse, reason: 'decline: no resume');
      await tester.pump();
      expect(
        computer.requests.length,
        asked + 1,
        reason: 'decline: the computer was not asked for its move again',
      );
      expect(h.controller.clockRunning(Colour.black), isTrue);
      await reply(h, fakes, 'b8c6');
      await play(tester, h.controller, 'f1c4');
      expect(h.controller.drawOffer, DrawOffer.open);
      await h.clock.advance(minThinkTime);
    });

    testWidgets('one offer per move: refused again until you move', (
      tester,
    ) async {
      final (h, fakes) = await bothMoved(tester);
      await pausePill(tester, h.clock);
      await pressCard(tester, 'pause-draw');
      fakes.current.draws.single.decline();
      await tester.pump();
      await pressCard(tester, 'pause-resume');
      await h.clock.advance(pauseFadeDuration);
      expect(h.controller.state.paused, isFalse);
      await pausePill(tester, h.clock);
      expect(h.controller.drawOffer, DrawOffer.afterNextMove);
      expect(live(tester, 'pause-draw'), isFalse);
      expect(text(tester, 'pause-draw-hint'), 'After your next move');
      expect(await h.controller.offerDraw(), isFalse);
      expect(fakes.current.draws, hasLength(1), reason: 'draw: asked twice');
      await pressCard(tester, 'pause-resume');
      await play(tester, h.controller, 'g1f3');
      await reply(h, fakes, 'b8c6');
      expect(h.controller.drawOffer, DrawOffer.open);
    });

    testWidgets('a takeback below the declined move frees the offer', (
      tester,
    ) async {
      final (h, fakes) = await bothMoved(tester);
      await play(tester, h.controller, 'g1f3');
      await reply(h, fakes, 'b8c6');
      await pausePill(tester, h.clock);
      await pressCard(tester, 'pause-draw');
      fakes.current.draws.single.decline();
      await tester.pump();
      await pressCard(tester, 'pause-resume');
      expect(h.controller.drawOffer, DrawOffer.afterNextMove);
      expect(h.controller.takeBack(), isTrue);
      await tester.pump();
      expect(moves(h.controller), ['e2e4', 'e7e5']);
      expect(h.controller.drawOffer, DrawOffer.open);
    });

    testWidgets('an error while answering counts as a decline', (tester) async {
      final (h, fakes) = await bothMoved(tester);
      await pausePill(tester, h.clock);
      await pressCard(tester, 'pause-draw');
      fakes.current.draws.single.fail();
      await tester.pump();
      expect(
        h.controller.game.isOver,
        isFalse,
        reason: 'draw: an error ended it',
      );
      expect(text(tester, 'pause-declined'), 'Club declines — play on');
      await h.clock.advance(drawDeclineShown);
      expect(h.controller.state.paused, isFalse);
    });

    testWidgets('Resume during the decline message closes it early', (
      tester,
    ) async {
      final (h, fakes) = await bothMoved(tester);
      await pausePill(tester, h.clock);
      await pressCard(tester, 'pause-draw');
      fakes.current.draws.single.decline();
      await tester.pump();
      expect(live(tester, 'pause-resume'), isTrue);
      await pressCard(tester, 'pause-resume');
      expect(h.controller.state.paused, isFalse);
      expect(h.controller.state.drawDeclined, isFalse);
      await h.clock.advance(drawDeclineShown);
      expect(h.controller.state.paused, isFalse);
    });
  });

  group('leaving the app', () {
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
    ]) {
      testWidgets('${state.name} pauses a running game; return keeps it', (
        tester,
      ) async {
        final h = await pumpGame(tester, timeControl: Timed.rapid);
        await play(tester, h.controller, 'e2e4');
        await leave(tester, state);
        await h.clock.advance(pauseFadeDuration);
        expect(h.controller.state.paused, isTrue);
        expect(_overlay, findsOneWidget);
        final black = h.controller.remaining(Colour.black);
        await h.clock.advance(const Duration(minutes: 2));
        expect(
          h.controller.remaining(Colour.black),
          black,
          reason: 'auto-pause: the clock ran while the app was away',
        );
        await comeBack(tester);
        expect(
          h.controller.state.paused,
          isTrue,
          reason: 'auto-pause: returning resumed by itself',
        );
        expect(_overlay, findsOneWidget);
      });
    }

    testWidgets('a finished game is not paused', (tester) async {
      final h = await pumpGame(tester, timeControl: Timed.rapid);
      await play(tester, h.controller, 'e2e4');
      expect(h.controller.resign(), isTrue);
      await tester.pump();
      await leave(tester, AppLifecycleState.hidden);
      expect(h.controller.state.paused, isFalse);
      expect(_overlay, findsNothing, reason: 'auto-pause: a finished game');
      await comeBack(tester);
    });

    testWidgets('during the decline message: the card stays up', (
      tester,
    ) async {
      final (h, fakes) = await bothMoved(tester);
      await pausePill(tester, h.clock);
      await pressCard(tester, 'pause-draw');
      fakes.current.draws.single.decline();
      await tester.pump();
      await leave(tester, AppLifecycleState.hidden);
      await h.clock.advance(drawDeclineShown * 2);
      expect(
        h.controller.state.paused,
        isTrue,
        reason:
            'auto-pause: the decline message resumed play in the background',
      );
      await comeBack(tester);
      expect(_overlay, findsOneWidget);
    });

    testWidgets('while the computer answers: accept lands, decline waits', (
      tester,
    ) async {
      final (h, fakes) = await bothMoved(tester);
      await pausePill(tester, h.clock);
      await pressCard(tester, 'pause-draw');
      await leave(tester, AppLifecycleState.hidden);
      fakes.current.draws.single.decline();
      await tester.pump();
      await h.clock.advance(drawDeclineShown * 2);
      expect(h.controller.state.paused, isTrue);
      await comeBack(tester);
      expect(text(tester, 'pause-declined'), 'Club declines — play on');
      await pressCard(tester, 'pause-resume');
      await play(tester, h.controller, 'g1f3');
      await reply(h, fakes, 'b8c6');
      await pausePill(tester, h.clock);
      await pressCard(tester, 'pause-draw');
      await leave(tester, AppLifecycleState.hidden);
      fakes.current.draws.last.accept();
      await tester.pump();
      expect(h.controller.game.status, const Draw(GameEndReason.agreement));
      await comeBack(tester);
    });
  });
}
