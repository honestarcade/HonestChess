import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:honest_chess/main.dart';
import 'package:honest_chess/ui/board/board_options.dart';
import 'package:honest_chess/ui/board/board_view.dart';

void main() {
  testWidgets('the app opens on the start position, White at the bottom', (
    tester,
  ) async {
    await tester.pumpWidget(const HonestChessApp());

    final board = tester.widget<BoardView>(find.byType(BoardView));
    expect(
      board.position.toFen(),
      'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
      reason: 'app: the preview shows the start position',
    );
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
