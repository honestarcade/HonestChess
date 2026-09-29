// Every board state reads without colour (#100): the pieces' two sides by
// luminance, and each highlight by a shape of its own — a thicker ring for
// the selected piece, a dot or a thinner ring for a target, a corner mark
// on the last move and a "!" on a king in check. The complement: with
// "Last-move highlight" or "Flag check on the board" off, its shape goes
// with its tint.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:honest_chess/engine/engine.dart';
import 'package:honest_chess/ui/board/board_interaction.dart';
import 'package:honest_chess/ui/board/board_options.dart';
import 'package:honest_chess/ui/board/board_view.dart';
import 'package:honest_chess/ui/game/game_controller.dart';
import 'package:honest_chess/ui/theme/contrast.dart';
import 'package:honest_chess/ui/theme/palette.dart';

import 'board/board_interaction_test.dart'
    show centre, dragTo, keyed, pumpPlayable, tap;

/// Each shape's key prefix, as the board draws it.
const Map<BoardShape, String> shapeKeys = {
  BoardShape.selectedRing: 'ring-selected-',
  BoardShape.lastMoveMark: 'mark-last-',
  BoardShape.moveDot: 'dot-',
  BoardShape.captureRing: 'ring-capture-',
  BoardShape.checkBadge: 'badge-check-',
};

/// The shapes drawn on [square], found by key.
Set<BoardShape> drawnOn(WidgetTester tester, String square) => {
  for (final MapEntry(:key, :value) in shapeKeys.entries)
    if (find.byKey(Key('$value$square')).evaluate().isNotEmpty) key,
};

/// Every square carrying any shape.
Set<String> shapedSquares(WidgetTester tester) => {
  for (final prefix in shapeKeys.values) ...keyed(tester, prefix),
};

double ringWidth(WidgetTester tester, String key) {
  final ring = tester.widget<DecoratedBox>(find.byKey(Key(key)));
  return (ring.decoration as BoxDecoration).border!.top.width;
}

/// Where [key]'s layer sits among its square's layers, bottom first.
int layerIndex(WidgetTester tester, String square, Finder layer) {
  final cell = find.descendant(
    of: find.byKey(Key('cell-$square')),
    matching: find.byType(Stack),
  );
  final stack = tester.widget<Stack>(cell.first);
  for (var i = 0; i < stack.children.length; i++) {
    final child = find.descendant(
      of: find.byWidget(stack.children[i]),
      matching: layer,
      matchRoot: true,
    );
    if (child.evaluate().isNotEmpty) return i;
  }
  fail('board shapes: no layer of $square holds $layer');
}

int pieceLayer(WidgetTester tester, String square) =>
    layerIndex(tester, square, find.byKey(Key('piece-$square')));

int shapeLayer(WidgetTester tester, String key) => layerIndex(
  tester,
  key.substring(key.lastIndexOf('-') + 1),
  find.byKey(Key(key)),
);

void expectHidden(WidgetTester tester, String key) {
  expect(
    find.ancestor(
      of: find.byKey(Key(key)),
      matching: find.byType(ExcludeSemantics),
    ),
    findsWidgets,
    reason: 'board shapes: $key says nothing the square\'s label does not',
  );
}

const _check = '4k3/8/8/8/8/8/4r3/4K3 w - - 0 1';

void main() {
  group('pieces without colour', () {
    for (final style in PieceStyle.values) {
      testWidgets('a white and a black knight in the ${style.name} style', (
        tester,
      ) async {
        Future<TextStyle> glyph(Colour colour) async {
          await tester.pumpWidget(
            Directionality(
              textDirection: TextDirection.ltr,
              child: boardPiece(
                Piece.of(colour, PieceKind.knight),
                style,
                46,
                1,
                textKey: const Key('knight'),
              ),
            ),
          );
          return tester.widget<Text>(find.byKey(const Key('knight'))).style!;
        }

        final white = await glyph(Colour.white);
        final black = await glyph(Colour.black);
        // The edge each side is drawn with: white's dark outline, black's
        // light halo, each at its own alpha.
        final whiteEdge = white.shadows!.first.color;
        final blackEdge = black.shadows!.first.color;
        for (final theme in BoardTheme.values) {
          for (final (name, square) in [
            ('light', theme.light),
            ('dark', theme.dark),
          ]) {
            final at = '${style.name}, ${theme.name} $name square';
            final whiteInk = composite(white.color!, square);
            final blackInk = composite(black.color!, square);
            expect(
              contrastRatio(whiteInk, blackInk),
              greaterThanOrEqualTo(3),
              reason: 'board shapes: white and black ink differ 3:1 ($at)',
            );
            for (final (side, ink, edge) in [
              ('white', whiteInk, whiteEdge),
              ('black', blackInk, blackEdge),
            ]) {
              final seen = [ink, composite(edge, square)]
                  .map((c) => contrastRatio(c, square))
                  .reduce((a, b) => a > b ? a : b);
              expect(
                seen,
                greaterThanOrEqualTo(3),
                reason:
                    'board shapes: a $side piece shows 3:1 on its square '
                    'by its ink or its edge ($at)',
              );
            }
          }
        }
      });
    }
  });

  group('each state paints its shape', () {
    testWidgets('selected: a 4 dp ring over the piece, thicker than a '
        'capture\'s', (tester) async {
      await pumpPlayable(
        tester,
        fen: 'rnbqkbnr/ppp1pppp/8/3p4/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2',
      );
      expect(shapedSquares(tester), isEmpty, reason: 'board shapes: none yet');
      await tap(tester, 'e4');
      expect(drawnOn(tester, 'e4'), {BoardShape.selectedRing});
      expect(drawnOn(tester, 'd5'), {BoardShape.captureRing});
      expect(drawnOn(tester, 'e5'), {BoardShape.moveDot});
      final selected = ringWidth(tester, 'ring-selected-e4');
      final capture = ringWidth(tester, 'ring-capture-d5');
      expect(selected, selectedRingWidth);
      expect(capture, captureRingWidth);
      expect(
        selected,
        greaterThan(capture),
        reason: 'board shapes: the selected ring is the thicker',
      );
      expect(
        (tester
                    .widget<DecoratedBox>(
                      find.byKey(const Key('ring-selected-e4')),
                    )
                    .decoration
                as BoxDecoration)
            .border!
            .top
            .color,
        shapeInk(BoardShape.selectedRing, onLight: true),
        reason: 'board shapes: e4 is light, so its ring is the light ink',
      );
      expect(
        shapeLayer(tester, 'ring-selected-e4'),
        greaterThan(pieceLayer(tester, 'e4')),
        reason: 'board shapes: the selected ring is drawn over the piece',
      );
      expect(
        shapeLayer(tester, 'ring-capture-d5'),
        lessThan(pieceLayer(tester, 'd5')),
        reason: 'board shapes: a capture ring is drawn under the piece',
      );
      for (final key in ['ring-selected-e4', 'ring-capture-d5', 'dot-e5']) {
        expectHidden(tester, key);
      }
    });

    testWidgets('the selected piece still drags from under its ring', (
      tester,
    ) async {
      final c = await pumpPlayable(tester);
      await tap(tester, 'e2');
      expect(drawnOn(tester, 'e2'), {BoardShape.selectedRing});
      await dragTo(tester, 'e2', centre(tester, 'e4'));
      expect(
        c.game.moves.single.toUci(),
        'e2e4',
        reason: 'board shapes: the ring takes no touches',
      );
    });

    testWidgets('last move: a corner mark on both squares, bottom-left', (
      tester,
    ) async {
      await pumpPlayable(tester);
      await tap(tester, 'g1');
      await tap(tester, 'f3');
      await tester.pump(const Duration(milliseconds: 400));
      expect(keyed(tester, 'mark-last-'), {'g1', 'f3'});
      for (final name in ['g1', 'f3']) {
        expect(drawnOn(tester, name), {BoardShape.lastMoveMark});
        final mark = find.byKey(Key('mark-last-$name'));
        final cell = tester.getRect(find.byKey(Key('cell-$name')));
        final rect = tester.getRect(mark);
        expect(rect.bottomLeft, cell.bottomLeft);
        expect(rect.size, const Size.square(lastMoveMarkSize));
        final light = Square.parse(name).isLight;
        expect(
          (tester.widget<CustomPaint>(mark).painter! as CornerMarkPainter)
              .colour,
          shapeInk(BoardShape.lastMoveMark, onLight: light),
        );
        expect(
          shapeLayer(tester, 'mark-last-$name'),
          greaterThan(layerIndex(tester, name, find.byKey(Key('tint-$name')))),
          reason: 'board shapes: the mark is drawn over the tint',
        );
        expectHidden(tester, 'mark-last-$name');
      }
      expect(
        shapeLayer(tester, 'mark-last-f3'),
        lessThan(pieceLayer(tester, 'f3')),
      );
    });

    testWidgets('check: a "!" badge top-right, under the king', (tester) async {
      await pumpPlayable(tester, fen: _check);
      expect(drawnOn(tester, 'e1'), {BoardShape.checkBadge});
      final badge = find.byKey(const Key('badge-check-e1'));
      final cell = tester.getRect(find.byKey(const Key('cell-e1')));
      final rect = tester.getRect(badge);
      expect(rect.topRight, cell.topRight);
      expect(rect.width, closeTo(cell.width * checkBadgeDiameter, 0.01));
      final bang = tester.widget<Text>(
        find.descendant(of: badge, matching: find.byType(Text)),
      );
      expect(bang.data, '!');
      expect(bang.style!.color, Palette.checkBadgeInk);
      expect(bang.style!.fontWeight, FontWeight.w700);
      expect(bang.style!.fontSize, closeTo(cell.width * checkBadgeGlyph, 0.01));
      expect(
        ((tester.widget<DecoratedBox>(
                  find.descendant(
                    of: badge,
                    matching: find.byType(DecoratedBox),
                  ),
                )).decoration
                as BoxDecoration)
            .color,
        Palette.danger,
      );
      expect(
        shapeLayer(tester, 'badge-check-e1'),
        lessThan(pieceLayer(tester, 'e1')),
        reason: 'board shapes: the badge is drawn under the king',
      );
      expectHidden(tester, 'badge-check-e1');
    });

    testWidgets('the badge stays with the checked king selected, and whole '
        'while it is dragged', (tester) async {
      await pumpPlayable(tester, fen: _check);
      await tap(tester, 'e1');
      expect(drawnOn(tester, 'e1'), {
        BoardShape.selectedRing,
        BoardShape.checkBadge,
      }, reason: 'board shapes: selection does not hide the check');
      final gesture = await tester.startGesture(centre(tester, 'e1'));
      await tester.pump();
      await gesture.moveBy(const Offset(0, -30));
      await tester.pump();
      expect(find.byKey(const Key('drag-feedback')), findsOneWidget);
      expect(
        find.ancestor(
          of: find.byKey(const Key('badge-check-e1')),
          matching: find.byType(Opacity),
        ),
        findsNothing,
        reason: 'board shapes: the badge is not dimmed with the dragged king',
      );
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 400));
    });
  });

  group('the complement: an option off takes its shape too', () {
    testWidgets('"Last-move highlight" off: no corner marks', (tester) async {
      await pumpPlayable(
        tester,
        options: const BoardOptions(lastMoveHighlight: false),
      );
      await tap(tester, 'e2');
      await tap(tester, 'e4');
      await tester.pump(const Duration(milliseconds: 400));
      expect(keyed(tester, 'mark-last-'), isEmpty);
      expect(shapedSquares(tester), isEmpty);
    });

    testWidgets('"Flag check on the board" off: no "!"', (tester) async {
      final c = await pumpPlayable(
        tester,
        fen: _check,
        options: const BoardOptions(flagCheck: false),
      );
      expect(c.state.inCheck, isNull);
      expect(keyed(tester, 'badge-check-'), isEmpty);
      await tap(tester, 'e1');
      expect(
        keyed(tester, 'badge-check-'),
        isEmpty,
        reason: 'board shapes: nor with the king selected',
      );
    });
  });

  group('in greyscale every state differs', () {
    const states = <String, (SquareTint, SquareMark, bool)>{
      'selected': (SquareTint.selected, SquareMark.none, false),
      'dot': (SquareTint.none, SquareMark.dot, false),
      'ring': (SquareTint.none, SquareMark.ring, false),
      'last move': (SquareTint.lastMove, SquareMark.none, false),
      'check': (SquareTint.check, SquareMark.none, true),
    };

    test('shapesFor gives each state a shape set of its own', () {
      final sets = {
        for (final MapEntry(:key, value: (tint, mark, check)) in states.entries)
          key: shapesFor(tint, mark, inCheck: check),
      };
      for (final a in sets.keys) {
        expect(
          sets[a],
          isNotEmpty,
          reason: 'board shapes: $a is more than a colour',
        );
        for (final b in sets.keys) {
          if (a == b) continue;
          expect(
            sets[a],
            isNot(sets[b]),
            reason: 'board shapes: $a and $b look different without colour',
          );
        }
      }
      expect(
        shapesFor(SquareTint.none, SquareMark.none, inCheck: false),
        isEmpty,
      );
      expect(shapesFor(SquareTint.selected, SquareMark.none, inCheck: true), {
        BoardShape.selectedRing,
        BoardShape.checkBadge,
      });
    });

    // The tints each shape can be drawn over. A move's target is never the
    // moving piece's own square and never a king, so a dot or a capture
    // ring sits on no tint or on the last move's; a king in check may also
    // be the selected piece.
    const under = <BoardShape, List<SquareTint>>{
      BoardShape.selectedRing: [SquareTint.selected],
      BoardShape.lastMoveMark: [SquareTint.lastMove],
      BoardShape.moveDot: [SquareTint.none, SquareTint.lastMove],
      BoardShape.captureRing: [SquareTint.none, SquareTint.lastMove],
      BoardShape.checkBadge: [SquareTint.check, SquareTint.selected],
    };

    // Dark squares keep the design's inks; these stay below 3:1 until
    // #151 is decided. Each is "<theme> <shape> on <tint>".
    const darkGaps = {
      'navy selectedRing on selected',
      'navy moveDot on lastMove',
      'navy captureRing on none',
      'navy captureRing on lastMove',
      'teal selectedRing on selected',
      'teal moveDot on none',
      'teal moveDot on lastMove',
      'teal captureRing on none',
      'teal captureRing on lastMove',
      'violet moveDot on lastMove',
      'violet captureRing on lastMove',
      'bone selectedRing on selected',
      'bone lastMoveMark on lastMove',
      'bone moveDot on none',
      'bone moveDot on lastMove',
      'bone captureRing on none',
      'bone captureRing on lastMove',
    };

    /// [shape]'s ink over [square] under [tint], as a WCAG ratio.
    double shown(BoardShape shape, Color square, SquareTint tint, bool light) {
      final background = composite(tintColour(tint), square);
      return contrastRatio(
        composite(shapeInk(shape, onLight: light), background),
        background,
      );
    }

    test('every shape shows 3:1 against what it is drawn on', () {
      expect(under.keys.toSet(), BoardShape.values.toSet());
      for (final tint in SquareTint.values) {
        for (final shape in shapesFor(tint, SquareMark.none, inCheck: false)) {
          expect(
            under[shape],
            contains(tint),
            reason: 'board shapes: $shape is drawn over the $tint tint',
          );
        }
      }
      // The badge's "!" is white on its circle whatever the circle's
      // contrast with the square.
      final glyph = contrastRatio(
        composite(Palette.checkBadgeInk, Palette.danger),
        Palette.danger,
      );
      final low = <String>[];
      final gapsRead = <String>[];
      for (final theme in BoardTheme.values) {
        for (final light in [true, false]) {
          final square = light ? theme.light : theme.dark;
          for (final MapEntry(key: shape, value: tints) in under.entries) {
            for (final tint in tints) {
              final ratio = shown(shape, square, tint, light);
              final reads =
                  ratio >= nonTextRatio ||
                  (shape == BoardShape.checkBadge && glyph >= normalTextRatio);
              final name = '${theme.name} ${shape.name} on ${tint.name}';
              final gap = !light && darkGaps.contains(name);
              if (!reads && !gap) {
                low.add(
                  '$name, ${light ? 'light' : 'dark'} square: '
                  '${ratio.toStringAsFixed(2)}:1',
                );
              }
              if (reads && gap) gapsRead.add(name);
            }
          }
        }
      }
      expect(
        low,
        isEmpty,
        reason:
            'board shapes: a shape below 3:1 in greyscale\n  '
            '${low.join('\n  ')}',
      );
      expect(
        gapsRead,
        isEmpty,
        reason: 'board shapes: a listed dark-square gap now reads; unlist it',
      );
    });

    test('the light-square ink is the nearest passing shade of teal', () {
      final targets = <ContrastTarget>[
        for (final theme in BoardTheme.values)
          for (final MapEntry(key: shape, value: tints) in under.entries)
            if (shape != BoardShape.checkBadge)
              for (final tint in tints)
                (
                  background: composite(tintColour(tint), theme.light),
                  minRatio: nonTextRatio,
                  opacity: 1,
                ),
      ];
      expect(
        Palette.markInkOnLight,
        shiftLightness(Palette.teal, targets, lighter: false),
        reason:
            'board shapes: markInkOnLight is teal darkened just to 3:1 on '
            'every light square',
      );
    });

    testWidgets('the painted shapes on the board match, state by state', (
      tester,
    ) async {
      final painted = <String, Set<BoardShape>>{};
      // Black's queen gives check; White's king is selected on e1 in the
      // next position, so the capture and the dot come from a rook.
      await pumpPlayable(tester, fen: '4k3/8/8/8/8/8/3q4/R3K3 w - - 0 1');
      painted['check'] = drawnOn(tester, 'e1');
      await tap(tester, 'e1');
      painted['selected'] = drawnOn(tester, 'e1')
        ..remove(BoardShape.checkBadge);
      painted['ring'] = drawnOn(tester, 'd2');
      await tap(tester, 'e1');
      await tap(tester, 'e1');
      painted['dot'] = drawnOn(tester, 'f1');
      await tap(tester, 'd2');
      painted['last move'] = drawnOn(tester, 'd2');
      await tester.pump(const Duration(milliseconds: 400));
      for (final MapEntry(:key, value: (tint, mark, check)) in states.entries) {
        expect(
          painted[key],
          shapesFor(tint, mark, inCheck: check),
          reason: 'board shapes: the board paints $key\'s shapes',
        );
      }
      expect(painted.values.toSet(), hasLength(states.length));
    });
  });
}
