import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:honest_chess/engine/engine.dart';
import 'package:honest_chess/main.dart';
import 'package:honest_chess/ui/board/board_options.dart';
import 'package:honest_chess/ui/board/board_view.dart';
import 'package:honest_chess/ui/game/computer_turns.dart';
import 'package:honest_chess/ui/game/game_screen.dart';

import 'ui/game/fake_computer.dart';
import 'ui/game/player_panel_test.dart' show text;

void main() {
  testWidgets('the app opens on a game against Club: you White, Rapid 10+5', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fakes = FakeComputers();
    await tester.pumpWidget(HonestChessApp(computerFactory: fakes.call));

    final board = tester.widget<BoardView>(find.byType(BoardView));
    expect(
      board.position.toFen(),
      'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
      reason: 'app: the play screen starts from the start position',
    );
    expect(board.bottom, Colour.white, reason: 'app: White at the bottom');
    expect(board.options, const BoardOptions(), reason: 'app: design defaults');

    final game = tester
        .state<GameScreenState>(find.byType(GameScreen))
        .controller
        .game;
    expect(game.mode, isA<VsComputer>(), reason: 'app: against the computer');
    final mode = game.mode as VsComputer;
    expect((mode.step, mode.playerColour), (Strength.club, Colour.white));
    expect(game.clock.control, Timed.rapid);
    expect(
      (fakes.current.strength, fakes.current.seed),
      (Strength.club, mode.seed),
      reason: 'app: the computer is built for this game',
    );
    expect(fakes.current.requests, isEmpty, reason: 'app: your move first');

    expect(text(tester, 'name-black'), 'Club');
    expect(text(tester, 'sub-white'), contains('YOU · WHITE'));
    expect(text(tester, 'sub-white'), contains('RAPID 10+5'));
    expect(text(tester, 'status-text'), 'WHITE TO MOVE');

    final state = tester.state<HonestChessAppState>(
      find.byType(HonestChessApp),
    );
    expect(
      state.boardOptions,
      const BoardOptions(),
      reason: 'app: the root holds the board options',
    );

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, const Color(0xFF05285F));

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.debugShowCheckedModeBanner, isFalse);
    expect(app.title, 'Honest Chess');
    expect(
      app.theme!.textTheme.bodyMedium!.fontFamily,
      'Outfit',
      reason: 'app: Outfit is the app-wide text face',
    );
  });

  testWidgets('from launch: play e2-e4 and the computer replies', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fakes = FakeComputers();
    await tester.pumpWidget(
      HonestChessApp(computerFactory: fakes.call, seed: 42),
    );
    expect(fakes.current.seed, 42, reason: 'app: the seed override is used');
    await tester.tap(find.byKey(const Key('cell-e2')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('cell-e4')));
    await tester.pump();
    fakes.current.last.move('e7e5');
    await tester.pump(minThinkTime);
    final screen = tester.state<GameScreenState>(find.byType(GameScreen));
    expect(screen.controller.game.moves.map((m) => m.toUci()), [
      'e2e4',
      'e7e5',
    ], reason: 'app: the computer answers on the home board');
    // The running clock keeps a ticker alive; leaving stops it.
    await tester.pumpWidget(const SizedBox());
  });

  test(
    'every bundled font licence is registered for the licence page',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      registerFontLicences();
      final entries = await LicenseRegistry.licenses.toList();
      final packages = <String>{for (final e in entries) ...e.packages};
      for (final family in fontLicences.keys) {
        expect(
          packages,
          contains(family),
          reason: 'licences: $family\'s OFL is on the licence page',
        );
      }
      final ofl = entries.where(
        (e) => e.packages.contains('Noto Sans Symbols 2'),
      );
      expect(
        ofl.single.paragraphs.map((p) => p.text).join(' '),
        contains('SIL Open Font License'),
        reason: 'licences: the registered text is the OFL itself',
      );
    },
  );
}
