import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:honest_chess/engine/engine.dart';
import 'package:honest_chess/ui/board/board_options.dart';
import 'package:honest_chess/ui/board/board_view.dart';
import 'package:honest_chess/ui/content/rules_text.dart';
import 'package:honest_chess/ui/screens/how_to_play_screen.dart';
import 'package:honest_chess/ui/theme/palette.dart';

import '../support/app_harness.dart';

const _order = [
  PieceKind.king,
  PieceKind.queen,
  PieceKind.rook,
  PieceKind.bishop,
  PieceKind.knight,
  PieceKind.pawn,
];

Future<AppHarness> _pump(
  WidgetTester tester, {
  HowToTab? initialTab,
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  return pumpUnderScope(
    tester,
    initialTab == null
        ? const HowToPlayScreen()
        : HowToPlayScreen(initialTab: initialTab),
  );
}

Finder _key(String key) => find.byKey(Key(key));

String _textIn(WidgetTester tester, String key) => tester
    .widgetList<Text>(
      find.descendant(of: _key(key), matching: find.byType(Text)),
    )
    .where((t) => !'${t.key}'.contains('howto-piece-glyph-'))
    .map((t) => t.data)
    .join('\n');

Text _glyph(WidgetTester tester, PieceKind kind) =>
    tester.widget<Text>(_key('howto-piece-glyph-${kind.name}'));

Color _square(WidgetTester tester, PieceKind kind) =>
    (tester
                .widget<Container>(_key('howto-piece-square-${kind.name}'))
                .decoration!
            as BoxDecoration)
        .color!;

bool _selected(WidgetTester tester, HowToTab tab) =>
    isSemantics(isSelected: true)
        .matches(tester.getSemantics(_key('howto-tab-${tab.name}')), {});

double _offset(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.descendant(
        of: _key('howto-scroll'),
        matching: find.byType(Scrollable),
      ),
    )
    .position
    .pixels;

void main() {
  group('initial tab', () {
    testWidgets('opens on The pieces by default, and only there', (
      tester,
    ) async {
      await _pump(tester);
      expect(_key('howto-piece-king'), findsOneWidget);
      expect(_key('howto-rule-the-goal'), findsNothing);
      expect(_key('howto-gestures'), findsNothing);
      expect(_selected(tester, HowToTab.pieces), isTrue);
      expect(_selected(tester, HowToTab.rules), isFalse);
      expect(find.text('How to play'), findsOneWidget);
    });

    testWidgets('opens on The rules when asked, and only there', (
      tester,
    ) async {
      await _pump(tester, initialTab: HowToTab.rules);
      expect(_key('howto-rule-the-goal'), findsOneWidget);
      expect(_key('howto-gestures'), findsOneWidget);
      expect(_key('howto-piece-king'), findsNothing);
      expect(_selected(tester, HowToTab.rules), isTrue);
      expect(_selected(tester, HowToTab.pieces), isFalse);
    });
  });

  group('The pieces', () {
    testWidgets('six cards, in order, each with its name and text', (
      tester,
    ) async {
      await _pump(tester);
      var lastTop = double.negativeInfinity;
      for (final kind in _order) {
        final card = 'howto-piece-${kind.name}';
        final text = pieceRules[kind]!;
        expect(_textIn(tester, card), contains(text.name));
        expect(_textIn(tester, card), contains(text.body));
        final top = tester.getTopLeft(_key(card)).dy;
        expect(top, greaterThan(lastTop), reason: '$kind out of order');
        lastTop = top;
      }
      expect(pieceRules.keys, _order);
      expect(pieceRules.values.map((p) => p.name), [
        'King',
        'Queen',
        'Rook',
        'Bishop',
        'Knight',
        'Pawn',
      ]);
    });

    testWidgets('each piece style changes the glyphs and not the text', (
      tester,
    ) async {
      final harness = await _pump(tester);
      final texts = {
        for (final kind in _order)
          kind: _textIn(tester, 'howto-piece-${kind.name}'),
      };
      for (final style in PieceStyle.values) {
        harness.settings.updateBoard((o) => o.copyWith(pieceStyle: style));
        await tester.pump();
        for (final kind in _order) {
          final glyph = _glyph(tester, kind);
          expect(glyph.data, pieceGlyph(Piece.of(Colour.black, kind), style));
          // Black ink, no board shadows, whatever the style.
          expect(glyph.style!.color, Palette.pieceBlack);
          expect(glyph.style!.shadows, isEmpty);
          expect(glyph.style!.fontSize, 21);
          // The glyph is the card's only text that changes.
          expect(_textIn(tester, 'howto-piece-${kind.name}'), texts[kind]);
        }
      }
      expect(_glyph(tester, PieceKind.king).data, 'K');
    });

    testWidgets('squares alternate the fixed light square and the '
        "theme's light colour", (tester) async {
      final harness = await _pump(tester);
      for (final theme in BoardTheme.values) {
        harness.settings.updateBoard((o) => o.copyWith(theme: theme));
        await tester.pump();
        for (final (i, kind) in _order.indexed) {
          expect(
            _square(tester, kind),
            i.isOdd ? theme.light : const Color(0xFFF1EFE7),
            reason: '$kind on ${theme.name}',
          );
        }
      }
    });

    testWidgets('a piece card reads as one node, name first, glyph silent', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _pump(tester);
      final text = pieceRules[PieceKind.king]!;
      final node = tester.getSemantics(_key('howto-piece-king'));
      expect(node, isSemantics(label: '${text.name}\n${text.body}'));
      expect(node, isSemantics(isHeader: false));
      semantics.dispose();
    });
  });

  group('The rules', () {
    testWidgets('five cards in order, THE GOAL teal-tinted and ringed', (
      tester,
    ) async {
      await _pump(tester, initialTab: HowToTab.rules);
      const slugs = ['the-goal', 'check', 'draws', 'the-clock', 'takeback'];
      var lastTop = double.negativeInfinity;
      for (final (i, slug) in slugs.indexed) {
        final card = tester.widget<Container>(_key('howto-rule-$slug'));
        final fill = (card.decoration! as BoxDecoration).color;
        expect(fill, i == 0 ? Palette.tealTint : Palette.cardFill);
        expect(card.foregroundDecoration != null, i == 0, reason: slug);
        expect(
          _textIn(tester, 'howto-rule-$slug'),
          contains(ruleCards[i].body),
        );
        final top = tester.getTopLeft(_key('howto-rule-$slug')).dy;
        expect(top, greaterThan(lastTop));
        lastTop = top;
      }
    });

    testWidgets('DRAWS and THE CLOCK say what the app does', (tester) async {
      await _pump(tester, initialTab: HowToTab.rules);
      final draws = _textIn(tester, 'howto-rule-draws');
      expect(draws, contains('three times'));
      expect(draws, contains('automatically'));
      expect(draws.toLowerCase(), isNot(contains('claim')));
      expect(
        _textIn(tester, 'howto-rule-the-clock'),
        contains("White's first move"),
      );
    });

    testWidgets('GESTURES lists what was built, and no HOLD PAUSE', (
      tester,
    ) async {
      await _pump(tester, initialTab: HowToTab.rules);
      final block = _textIn(tester, 'howto-gestures');
      expect(block, contains('DRAG'));
      expect(block, contains('PAUSE'));
      expect(block, isNot(contains('HOLD PAUSE')));
      const slugs = ['tap', 'tap-again', 'tap-king', 'drag', 'undo', 'pause'];
      var lastTop = double.negativeInfinity;
      for (final slug in slugs) {
        final top = tester.getTopLeft(_key('howto-gesture-$slug')).dy;
        expect(top, greaterThan(lastTop), reason: '$slug out of order');
        lastTop = top;
      }
      expect(gestures.map((g) => g.tag), [
        'TAP',
        'TAP AGAIN',
        'TAP KING',
        'DRAG',
        'UNDO',
        'PAUSE',
      ]);
    });

    testWidgets('tags and the kicker are headers; bodies and rows are not', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _pump(tester, initialTab: HowToTab.rules);
      final tag = tester.getSemantics(find.text('THE GOAL'));
      expect(tag, isSemantics(label: 'THE GOAL', isHeader: true));
      final body = tester.getSemantics(find.text(ruleCards.first.body));
      expect(body, isSemantics(label: ruleCards.first.body, isHeader: false));
      expect(
        tester.getSemantics(find.text(gesturesKicker)),
        isSemantics(label: gesturesKicker, isHeader: true),
      );
      final row = tester.getSemantics(_key('howto-gesture-tap'));
      expect(
        row,
        isSemantics(label: 'TAP\n${gestures.first.body}', isHeader: false),
      );
      semantics.dispose();
    });
  });

  group('tabs', () {
    testWidgets('switching tabs shows the other and scrolls to the top', (
      tester,
    ) async {
      await _pump(tester, size: const Size(390, 500));
      await tester.drag(_key('howto-scroll'), const Offset(0, -30));
      await tester.pump();
      expect(_offset(tester), greaterThan(0));
      await tester.tap(_key('howto-tab-rules'));
      await tester.pump();
      expect(_offset(tester), 0);
      expect(_key('howto-rule-draws'), findsOneWidget);
      expect(_key('howto-piece-king'), findsNothing);

      await tester.drag(_key('howto-scroll'), const Offset(0, -30));
      await tester.pump();
      expect(_offset(tester), greaterThan(0));
      await tester.tap(_key('howto-tab-pieces'));
      await tester.pump();
      expect(_offset(tester), 0);
      expect(_key('howto-piece-king'), findsOneWidget);
    });

    testWidgets('tapping the selected tab does nothing', (tester) async {
      await _pump(tester, size: const Size(390, 500));
      await tester.drag(_key('howto-scroll'), const Offset(0, -30));
      await tester.pump();
      final before = _offset(tester);
      await tester.tap(_key('howto-tab-pieces'));
      await tester.pump();
      expect(_offset(tester), before);
      expect(_selected(tester, HowToTab.pieces), isTrue);
    });

    testWidgets('each tab is a 48 dp hit region, beyond the drawn pill', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _pump(tester);
      for (final tab in HowToTab.values) {
        expect(
          tester.getSize(_key('howto-tab-${tab.name}')).height,
          greaterThanOrEqualTo(48),
        );
        expect(
          tester.getSemantics(_key('howto-tab-${tab.name}')),
          isSemantics(isButton: true, isInMutuallyExclusiveGroup: true),
        );
      }
      // Just inside the slot's top edge, above the drawn pill.
      final rules = tester.getRect(_key('howto-tab-rules'));
      await tester.tapAt(Offset(rules.center.dx, rules.top + 1));
      await tester.pump();
      expect(_selected(tester, HowToTab.rules), isTrue);
      expect(
        tester.getSemantics(_key('howto-tab-rules')),
        isSemantics(label: 'The rules', isSelected: true),
      );
      semantics.dispose();
    });
  });

  testWidgets('back returns to where the screen was opened from', (
    tester,
  ) async {
    await pumpUnderScope(
      tester,
      Builder(
        builder: (context) => TextButton(
          key: const Key('open'),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const HowToPlayScreen()),
          ),
          child: const Text('open'),
        ),
      ),
    );
    await tester.tap(_key('open'));
    await tester.pumpAndSettle();
    expect(_key('howto-piece-king'), findsOneWidget);
    await tester.tap(_key('howto-back'));
    await tester.pumpAndSettle();
    expect(_key('howto-piece-king'), findsNothing);
    expect(_key('open'), findsOneWidget);
  });
}
