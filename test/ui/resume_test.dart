// A saved game put back on the board (#81): it comes back paused, with the
// pause card up, and the computer is asked for nothing until Resume — then
// exactly once. The clocks read the same before and after.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:honest_chess/data/app_store.dart';
import 'package:honest_chess/data/game_saves.dart';
import 'package:honest_chess/data/play_mode.dart';
import 'package:honest_chess/engine/engine.dart';
import 'package:honest_chess/ui/board/board_options.dart';
import 'package:honest_chess/ui/game/computer_turns.dart';
import 'package:honest_chess/ui/game/game_controller.dart';
import 'package:honest_chess/ui/game/game_screen.dart';
import 'package:honest_chess/ui/game/pause_overlay.dart';

import '../support/app_harness.dart';
import 'game/fake_computer.dart';
import 'game/player_panel_test.dart' show FakeClock, clockOf, tickers;

const _mode = VsComputer(
  playerColour: Colour.white,
  step: Strength.club,
  seed: 77,
);

/// A store holding a Rapid game against Club at the computer's turn, its
/// clocks part-used.
AppStore _storeWithSavedGame() {
  var ms = 0;
  var game = Game.start(_mode, Timed.rapid, time: () => ms);
  for (final uci in ['e2e4', 'e7e5', 'g1f3']) {
    ms += 4200;
    game = game.play(
      Move.fromUci(game.position, uci),
      byComputer: game.sideToMove == _mode.computerColour,
    );
  }
  ms += 9000;
  return AppStore.memory()..putRaw(
    StoreDoc.gameComputer,
    jsonEncode({
      'format': 1,
      'data': {
        'game': game.toJson(),
        'recorded': {'id': '5a5a5a5a5a5a5a5a'},
      },
    }),
  );
}

void main() {
  testWidgets('a restored game waits, paused, for Resume; then the computer '
      'is asked once', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final clock = FakeClock(tester);
    final store = _storeWithSavedGame();
    final saves = GameSaves(store, time: clock.now);
    await saves.loadAll();
    final fakes = FakeComputers();
    final controller = GameController.idle(
      now: clock.now,
      computerFactory: fakes.call,
    );
    saves.attach(controller.events);
    addTearDown(() {
      saves.dispose();
      controller.dispose();
    });

    expect(saves.offered?.mode, PlayMode.computer);
    final game = saves.load(PlayMode.computer)!;
    expect(
      controller.restore(game, recorded: saves.recorded(PlayMode.computer)),
      isTrue,
    );
    expect(controller.recorded, {
      'id': '5a5a5a5a5a5a5a5a',
      'started': true,
      'outcome': false,
    }, reason: 'resume: the saved statistics id is kept');
    await pumpUnderScope(
      tester,
      GameScreen(options: const BoardOptions(), controller: controller),
      store: store,
      controller: controller,
      saves: saves,
    );
    await clock.advance(pauseFadeDuration);

    expect(
      find.byKey(const Key('pause-card')),
      findsOneWidget,
      reason: 'resume: a restored game shows the pause card',
    );
    expect(controller.state.paused, isTrue);
    expect(
      fakes.built.single.seed,
      _mode.seed,
      reason: 'resume: the computer has the saved step and seed',
    );
    expect(fakes.current.strength, Strength.club);
    final before = {
      for (final side in Colour.values) side: clockOf(tester, side),
    };
    expect(before[Colour.white], '10:01');
    expect(before[Colour.black], '9:52');

    await clock.advance(const Duration(seconds: 3));
    expect(
      fakes.current.requests,
      isEmpty,
      reason: 'resume: no move is asked for while paused',
    );
    expect(tickers, 0, reason: 'resume: nothing ticks while paused');
    for (final side in Colour.values) {
      expect(clockOf(tester, side), before[side], reason: 'resume: $side');
    }

    await tester.tap(find.byKey(const Key('pause-resume')));
    await tester.pump();
    await tester.pump();
    expect(controller.state.paused, isFalse);
    expect(
      fakes.current.requests,
      hasLength(1),
      reason: 'resume: the computer is asked once, after Resume',
    );
    expect(fakes.current.last.game.moves, game.moves);
    for (final side in Colour.values) {
      expect(
        clockOf(tester, side),
        before[side],
        reason: 'resume: $side\'s clock goes on from where it stopped',
      );
    }

    fakes.current.last.move('b8c6');
    await clock.advance(minThinkTime);
    expect(controller.game.moves, hasLength(4));
    expect(fakes.current.requests, hasLength(1));
    // The running clock keeps a ticker alive; leaving stops it.
    await tester.pumpWidget(const SizedBox());
  });
}
