import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:honest_chess/engine/engine.dart';
import 'package:honest_chess/main.dart';
import 'package:honest_chess/ui/board/board_options.dart';
import 'package:honest_chess/ui/board/board_view.dart';
import 'package:honest_chess/ui/game/game_screen.dart';

void main() {
  testWidgets('the app opens on the start position, White at the bottom', (
    tester,
  ) async {
    await tester.pumpWidget(const HonestChessApp());

    final board = tester.widget<BoardView>(find.byType(BoardView));
    expect(
      board.position.toFen(),
      'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
      reason: 'app: the play screen starts from the start position',
    );
    expect(board.bottom, Colour.white, reason: 'app: White at the bottom');
    expect(board.options, const BoardOptions(), reason: 'app: design defaults');

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

  testWidgets('the home board is playable by two: e2-e4, then e7-e5', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const HonestChessApp());
    for (final square in ['e2', 'e4', 'e7', 'e5']) {
      await tester.tap(find.byKey(Key('cell-$square')));
      await tester.pump();
    }
    final screen = tester.state<GameScreenState>(find.byType(GameScreen));
    expect(screen.controller.game.moves.map((m) => m.toUci()), [
      'e2e4',
      'e7e5',
    ], reason: 'app: two players take turns on the home board');
    expect(screen.controller.game.mode, const TwoPlayer());
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
