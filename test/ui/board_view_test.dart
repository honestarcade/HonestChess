// The board as the design draws it: squares, surfaces, pieces, coordinates
// and orientation (#71). No golden images — CI and local renders differ —
// so colours, glyphs, fonts and positions are asserted directly.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:honest_chess/engine/engine.dart';
import 'package:honest_chess/ui/board/board_options.dart';
import 'package:honest_chess/ui/board/board_view.dart';
import 'package:honest_chess/ui/board/orientation.dart';
import 'package:honest_chess/ui/theme/palette.dart';

const _phone = Size(390, 844);

Future<void> pumpBoard(
  WidgetTester tester, {
  Position? position,
  Colour bottom = Colour.white,
  BoardOptions options = const BoardOptions(),
  Size size = _phone,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: BoardView(
        position: position ?? Position.initial(),
        bottom: bottom,
        options: options,
      ),
    ),
  );
}

Color squareColour(WidgetTester tester, String name) {
  final box = tester.widget<ColoredBox>(
    find.descendant(
      of: find.byKey(Key('sq-$name')),
      matching: find.byType(ColoredBox),
    ),
  );
  return box.color;
}

Text piece(WidgetTester tester, String name) =>
    tester.widget<Text>(find.byKey(Key('piece-$name')));

Rect squareRect(WidgetTester tester, String name) =>
    tester.getRect(find.byKey(Key('sq-$name')));

void main() {
  group('size and frame', () {
    testWidgets('full width less the 8 dp margins, in whole-pixel squares', (
      tester,
    ) async {
      await pumpBoard(tester);
      final board = tester.getRect(find.byKey(const Key('board')));
      expect(squareSide(_phone), 46, reason: 'board: floor((390 − 16) / 8)');
      expect(board.width, 368, reason: 'board: eight whole squares');
      expect(board.center.dx, 195, reason: 'board: centred in the leftover');
      expect(squareRect(tester, 'a1').size, const Size(46, 46));
    });

    testWidgets('a short height bounds the board instead', (tester) async {
      await pumpBoard(tester, size: const Size(390, 300));
      expect(
        squareSide(const Size(390, 300)),
        37,
        reason: 'board: floor(300/8)',
      );
      expect(tester.getRect(find.byKey(const Key('board'))).height, 296);
    });

    testWidgets('the rounded frame, its shadow and its ring', (tester) async {
      await pumpBoard(tester);
      final frame = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byKey(const Key('board')),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      final decoration = frame.decoration as BoxDecoration;
      expect(
        decoration.borderRadius,
        BorderRadius.circular(10),
        reason: 'frame: the design\'s 10 px corner',
      );
      expect(decoration.boxShadow, const [
        BoxShadow(
          color: Color(0x73000000),
          offset: Offset(0, 12),
          blurRadius: 30,
        ),
      ], reason: 'frame: 0 12px 30px rgba(0,0,0,.45)');
      final ring = tester.widget<DecoratedBox>(
        find.byKey(const Key('board-ring')),
      );
      final border = (ring.decoration as BoxDecoration).border as Border;
      expect(border.top, const BorderSide(color: Color(0x1FFFFFFF)));
    });
  });

  group('themes', () {
    const expected = {
      BoardTheme.navy: (Color(0xFFDCE9F8), Color(0xFF0F3E86)),
      BoardTheme.teal: (Color(0xFFD6F0EB), Color(0xFF0B615A)),
      BoardTheme.violet: (Color(0xFFE4DAFB), Color(0xFF3B2076)),
      BoardTheme.bone: (Color(0xFFF1EFE7), Color(0xFF6A7586)),
    };
    for (final MapEntry(key: theme, value: (light, dark)) in expected.entries) {
      testWidgets('${theme.name}: a1 dark, h1 light', (tester) async {
        await pumpBoard(tester, options: BoardOptions(theme: theme));
        expect(squareColour(tester, 'a1'), dark, reason: 'theme: a1 is dark');
        expect(squareColour(tester, 'h1'), light, reason: 'theme: h1 light');
        expect(
          squareColour(tester, 'a1'),
          isNot(light),
          reason: 'theme: a1 is never the light colour',
        );
      });
    }
    test('the default is navy, classic, felt', () {
      const o = BoardOptions();
      expect(
        (o.theme, o.pieceStyle, o.surface),
        (BoardTheme.navy, PieceStyle.classic, BoardSurface.felt),
      );
    });
  });

  group('surfaces', () {
    testWidgets('plain draws no overlay', (tester) async {
      await pumpBoard(
        tester,
        options: const BoardOptions(surface: BoardSurface.plain),
      );
      expect(
        find.byKey(const Key('surface')),
        findsNothing,
        reason: 'surface: plain paints nothing over the squares',
      );
    });

    for (final (surface, angle, period) in [
      (BoardSurface.felt, 45.0, 4.0),
      (BoardSurface.wood, 87.0, 7.0),
    ]) {
      testWidgets('${surface.name} stripes at $angle° every ${period}px', (
        tester,
      ) async {
        await pumpBoard(tester, options: BoardOptions(surface: surface));
        final paint = tester.widget<CustomPaint>(
          find.byKey(const Key('surface')),
        );
        final painter = paint.painter! as SurfacePainter;
        expect(painter.pattern.angleDegrees, angle);
        expect(painter.pattern.period, period);
        expect(painter.scale, 1, reason: 'surface: 390 wide is scale 1');
        expect(
          tester.getRect(find.byKey(const Key('surface'))),
          tester.getRect(find.byKey(const Key('board'))),
          reason: 'surface: one layer across the whole board',
        );
      });
    }

    test('the design\'s stripe colours', () {
      expect(
        [for (final b in BoardSurface.felt.pattern!.bands) (b.colour, b.width)],
        [(const Color(0x0DFFFFFF), 1.0), (const Color(0x08000000), 3.0)],
      );
      expect(
        [for (final b in BoardSurface.wood.pattern!.bands) (b.colour, b.width)],
        [(const Color(0x17000000), 2.0), (const Color(0x0DFFFFFF), 5.0)],
      );
    });

    testWidgets('the painter draws inside the board only', (tester) async {
      await pumpBoard(tester);
      expect(
        find.byKey(const Key('surface')),
        paints..rect(color: const Color(0x0DFFFFFF)),
      );
    });
  });

  group('pieces', () {
    const knights = {
      PieceStyle.classic: ('♞\u{FE0E}', '♞\u{FE0E}'),
      PieceStyle.outline: ('♘\u{FE0E}', '♘\u{FE0E}'),
      PieceStyle.flat: ('N', 'N'),
    };
    for (final MapEntry(key: style, value: (white, black)) in knights.entries) {
      testWidgets('${style.name}: the knights', (tester) async {
        await pumpBoard(tester, options: BoardOptions(pieceStyle: style));
        final w = piece(tester, 'g1');
        final b = piece(tester, 'g8');
        expect(w.data, white, reason: 'pieces: white knight in ${style.name}');
        expect(b.data, black, reason: 'pieces: black knight in ${style.name}');
        expect(w.style!.color, Palette.pieceWhite);
        expect(b.style!.color, Palette.pieceBlack);
        final flat = style == PieceStyle.flat;
        expect(
          w.style!.fontFamily,
          flat ? 'PlexMono' : 'HonestPieces',
          reason: 'pieces: drawn in the bundled piece font',
        );
        expect(
          w.style!.fontSize,
          flat ? 29 : 42,
          reason: 'pieces: round(46 × ${flat ? 0.62 : 0.92})',
        );
        expect(w.style!.fontWeight, flat ? FontWeight.w600 : FontWeight.w400);
      });
    }

    testWidgets('white pieces are outlined dark; black ones haloed light', (
      tester,
    ) async {
      await pumpBoard(tester);
      final w = piece(tester, 'e1').style!.shadows!;
      final b = piece(tester, 'e8').style!.shadows!;
      expect(w, hasLength(7), reason: 'pieces: the design\'s seven shadows');
      expect(
        w.where((s) => s.color == Palette.pieceBlack && s.blurRadius == 0),
        hasLength(4),
        reason: 'pieces: the four 1 px outline offsets',
      );
      expect(b, hasLength(2));
      expect(
        b.every((s) => s.color.b == 1 && s.color.r == 1),
        isTrue,
        reason: 'pieces: black pieces never get the dark outline',
      );
    });

    testWidgets('every piece of the start position, none elsewhere', (
      tester,
    ) async {
      await pumpBoard(tester);
      expect(piece(tester, 'e1').data, '♚\u{FE0E}');
      expect(piece(tester, 'd8').data, '♛\u{FE0E}');
      expect(find.byKey(const Key('piece-e4')), findsNothing);
      for (final rank in [1, 2, 7, 8]) {
        for (final file in 'abcdefgh'.split('')) {
          expect(find.byKey(Key('piece-$file$rank')), findsOneWidget);
        }
      }
    });

    testWidgets('a glyph\'s box sits on its square\'s centre, moved by its '
        'ink shift', (tester) async {
      await pumpBoard(tester);
      final knight = piece(tester, 'g1');
      expect(
        tester.getCenter(find.byKey(const Key('piece-g1'))),
        squareRect(tester, 'g1').center +
            pieceInkShift(
                  Piece.of(Colour.white, PieceKind.knight),
                  PieceStyle.classic,
                ) *
                knight.style!.fontSize!,
        reason: 'pieces: the box moves by the ink shift, so the ink is centred',
      );
    });
  });

  group('coordinates', () {
    for (final bottom in Colour.values) {
      testWidgets('only the left file and bottom rank, ${bottom.name} below', (
        tester,
      ) async {
        await pumpBoard(tester, bottom: bottom);
        final leftFile = bottom == Colour.white ? 'a' : 'h';
        final bottomRank = bottom == Colour.white ? 1 : 8;
        for (final square in Square.values) {
          final name = square.name;
          expect(
            find.byKey(Key('rank-$name')),
            name[0] == leftFile ? findsOneWidget : findsNothing,
            reason: 'coords: rank numbers only on the left-hand file',
          );
          expect(
            find.byKey(Key('file-$name')),
            name[1] == '$bottomRank' ? findsOneWidget : findsNothing,
            reason: 'coords: file letters only on the bottom rank',
          );
        }
      });
    }

    testWidgets('labels read the square, in the theme\'s label colours', (
      tester,
    ) async {
      await pumpBoard(tester);
      final a1Rank = tester.widget<Text>(find.byKey(const Key('rank-a1')));
      final a2Rank = tester.widget<Text>(find.byKey(const Key('rank-a2')));
      final h1File = tester.widget<Text>(find.byKey(const Key('file-h1')));
      expect(a1Rank.data, '1');
      expect(h1File.data, 'h');
      expect(
        a1Rank.style!.color,
        BoardTheme.navy.labelOnDark,
        reason: 'a1 is dark',
      );
      expect(
        a2Rank.style!.color,
        BoardTheme.navy.labelOnLight,
        reason: 'a2 is light',
      );
      expect(a1Rank.style!.fontFamily, 'PlexMono');
      expect(a1Rank.style!.fontSize, 8);
      final a1 = squareRect(tester, 'a1');
      expect(
        tester.getTopLeft(find.byKey(const Key('rank-a1'))),
        a1.topLeft + const Offset(2, 1),
      );
      expect(
        tester.getBottomRight(find.byKey(const Key('file-a1'))),
        a1.bottomRight - const Offset(2, 1),
      );
    });
  });

  group('orientation', () {
    testWidgets('White below: a1 bottom-left, h8 top-right', (tester) async {
      await pumpBoard(tester);
      final board = tester.getRect(find.byKey(const Key('board')));
      expect(squareRect(tester, 'a1').bottomLeft, board.bottomLeft);
      expect(squareRect(tester, 'h8').topRight, board.topRight);
    });

    testWidgets('Black below: h8 bottom-left, a1 top-right', (tester) async {
      await pumpBoard(tester, bottom: Colour.black);
      final board = tester.getRect(find.byKey(const Key('board')));
      expect(
        squareRect(tester, 'h8').bottomLeft,
        board.bottomLeft,
        reason: 'orientation: flipped for Black',
      );
      expect(squareRect(tester, 'a1').topRight, board.topRight);
      expect(
        squareRect(tester, 'a1').bottomLeft,
        isNot(board.bottomLeft),
        reason: 'orientation: a1 is not at bottom-left for Black',
      );
    });

    const whiteToMove = '4k3/8/8/8/8/8/8/4K3 w - - 0 1';
    const blackToMove = '4k3/8/8/8/8/8/8/4K3 b - - 0 1';
    Colour sideOf(String fen) => Position.fromFen(fen).sideToMove;

    test('against the computer your side is at the bottom', () {
      for (final you in Colour.values) {
        final mode = VsComputer(
          playerColour: you,
          step: Strength.club,
          seed: 1,
        );
        for (final fen in [whiteToMove, blackToMove]) {
          for (final rotate in [false, true]) {
            expect(
              boardBottom(mode, sideOf(fen), rotate: rotate),
              you,
              reason: 'orientation: vs computer never rotates',
            );
          }
        }
      }
    });

    test('two players: rotate on faces the side to move', () {
      const mode = TwoPlayer();
      expect(
        boardBottom(mode, sideOf(whiteToMove), rotate: true),
        Colour.white,
      );
      expect(
        boardBottom(mode, sideOf(blackToMove), rotate: true),
        Colour.black,
        reason: 'orientation: rotate flips after White moves',
      );
    });

    test('two players: rotate off keeps White at the bottom', () {
      const mode = TwoPlayer();
      for (final fen in [whiteToMove, blackToMove]) {
        expect(
          boardBottom(mode, sideOf(fen), rotate: false),
          Colour.white,
          reason: 'orientation: no rotation when the option is off',
        );
      }
    });

    Game twoPlayer(List<String> uci) {
      var game = Game.start(const TwoPlayer(), const Untimed());
      for (final m in uci) {
        game = game.play(Move.fromUci(game.position, m));
      }
      return game;
    }

    test('a game follows moves and takebacks, and stays put once over', () {
      final opened = twoPlayer(['e2e4']);
      expect(boardBottomOf(opened, rotate: true), Colour.black);
      expect(boardBottomOf(opened.takeBack(), rotate: true), Colour.white);
      expect(boardBottomOf(opened, rotate: false), Colour.white);

      // Fool's mate: Black mates, so the board keeps facing Black.
      final mated = twoPlayer(['f2f3', 'e7e5', 'g2g4', 'd8h4']);
      expect(mated.isOver, isTrue);
      expect(
        boardBottomOf(mated, rotate: true),
        Colour.black,
        reason: 'orientation: no turn to the mated side',
      );
      expect(
        boardBottomOf(mated.takeBack(), rotate: true),
        Colour.black,
        reason: 'orientation: after a takeback it follows the side to move',
      );

      // A resignation ends the game without a move: nothing turns.
      final resigned = opened.resign(Colour.black);
      expect(boardBottomOf(resigned, rotate: true), Colour.black);
    });

    testWidgets('the widget follows a rotate after a move', (tester) async {
      final game = twoPlayer(['e2e4']);
      await pumpBoard(
        tester,
        position: game.position,
        bottom: boardBottomOf(game, rotate: true),
      );
      final board = tester.getRect(find.byKey(const Key('board')));
      expect(squareRect(tester, 'h8').bottomLeft, board.bottomLeft);
      await pumpBoard(
        tester,
        position: game.position,
        bottom: boardBottomOf(game, rotate: false),
      );
      expect(
        squareRect(tester, 'a1').bottomLeft,
        board.bottomLeft,
        reason: 'orientation: off keeps White below after a move',
      );
    });
  });

  group('options', () {
    test('copyWith changes one field and keeps the rest', () {
      const o = BoardOptions();
      final t = o.copyWith(theme: BoardTheme.bone);
      expect(t.theme, BoardTheme.bone);
      expect(t, isNot(o));
      expect(t.copyWith(theme: BoardTheme.navy), o);
      expect(
        (
          o.legalMoveDots,
          o.lastMoveHighlight,
          o.flagCheck,
          o.takebackAllowed,
          o.autoQueen,
          o.rotateEachTurn,
          o.animations,
        ),
        (true, true, true, true, false, false, true),
        reason: 'options: the design\'s Settings defaults',
      );
    });
  });
}
