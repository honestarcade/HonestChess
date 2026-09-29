import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:honest_chess/data/app_store.dart';
import 'package:honest_chess/data/settings_store.dart';
import 'package:honest_chess/engine/engine.dart';
import 'package:honest_chess/main.dart';
import 'package:honest_chess/ui/board/board_options.dart';
import 'package:honest_chess/ui/board/board_view.dart';
import 'package:honest_chess/ui/screens/settings_screen.dart';
import 'package:honest_chess/ui/theme/palette.dart';
import 'package:honest_chess/ui/widgets/option_button.dart';

import '../support/app_harness.dart';
import 'game/fake_computer.dart';

/// A live board above the Settings screen, both over the harness's
/// settings, as the app root wires them.
Future<AppHarness> _pumpBoardAndSettings(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 1500);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  late final AppHarness harness;
  final settings = SettingsStore();
  addTearDown(settings.dispose);
  harness = await pumpUnderScope(
    tester,
    Column(
      children: [
        SizedBox(
          height: 400,
          child: ValueListenableBuilder<BoardOptions>(
            valueListenable: settings.board,
            builder: (_, options, _) => BoardView(
              position: Position.initial(),
              bottom: Colour.white,
              options: options,
            ),
          ),
        ),
        const Expanded(child: SettingsScreen()),
      ],
    ),
    settings: settings,
  );
  return harness;
}

Color _squareColour(WidgetTester tester, String square) => tester
    .widget<ColoredBox>(
      find.descendant(
        of: find.byKey(Key('sq-$square')),
        matching: find.byType(ColoredBox),
      ),
    )
    .color;

Text _piece(WidgetTester tester, String square) =>
    tester.widget<Text>(find.byKey(Key('piece-$square')));

StripePattern? _surface(WidgetTester tester) {
  final layer = find.byKey(const Key('surface'));
  if (layer.evaluate().isEmpty) return null;
  return (tester.widget<CustomPaint>(layer).painter! as SurfacePainter).pattern;
}

/// The board as the three looks see it.
({Color a1, String knight, String? font, StripePattern? surface}) _look(
  WidgetTester tester,
) {
  final knight = _piece(tester, 'g1');
  return (
    a1: _squareColour(tester, 'a1'),
    knight: knight.data!,
    font: knight.style!.fontFamily,
    surface: _surface(tester),
  );
}

/// The colour [label] is painted in, after its button's DefaultTextStyle.
Color? _labelColour(WidgetTester tester, String label) =>
    tester.renderObject<RenderParagraph>(find.text(label)).text.style?.color;

Future<void> _choose(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.tap(find.byKey(Key(key)));
  await tester.pump();
}

void _expectChosen(
  WidgetTester tester,
  String group,
  List<({String name, String label})> options,
  String chosen,
) {
  for (final o in options) {
    final isChosen = o.name == chosen;
    final button = find.byKey(Key('settings-$group-${o.name}'));
    expect(
      tester.widget<OptionButton>(button).selected,
      isChosen,
      reason: 'settings-look: ${o.name} is ${isChosen ? '' : 'not '}chosen',
    );
    expect(
      _labelColour(tester, o.label),
      isChosen ? Palette.teal : Palette.textMuted,
      reason: 'settings-look: ${o.label} label follows the choice',
    );
    final border =
        (tester
                    .widget<DecoratedBox>(
                      find
                          .descendant(
                            of: button,
                            matching: find.byType(DecoratedBox),
                          )
                          .first,
                    )
                    .decoration
                as BoxDecoration)
            .border!
            .top
            .color;
    expect(
      border,
      isChosen ? Palette.teal : Palette.borderSoft,
      reason: 'settings-look: ${o.name} border follows the choice',
    );
    expect(
      tester.getSemantics(button),
      isSemantics(
        isSelected: isChosen,
        isInMutuallyExclusiveGroup: true,
        isButton: true,
      ),
      reason: 'settings-look: ${o.name} semantics follow the choice',
    );
  }
}

List<({String name, String label})> _options(List<Enum> values) => [
  for (final v in values) (name: v.name, label: v.name.toUpperCase()),
];

void main() {
  testWidgets('Settings opens with the header and the three look sections', (
    tester,
  ) async {
    await _pumpBoardAndSettings(tester);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('‹'), findsOneWidget, reason: 'settings: back ‹');
    for (final title in ['Board colour', 'Piece style', 'Board surface']) {
      expect(find.text(title), findsOneWidget, reason: 'settings: $title');
    }
    expect(
      find.text('Four pairs from the Honest Arcade palette.'),
      findsOneWidget,
      reason: 'settings: the design\'s caption',
    );
    for (final label in [
      'NAVY',
      'TEAL',
      'VIOLET',
      'BONE',
      'CLASSIC',
      'OUTLINE',
      'FLAT',
      'PLAIN',
      'FELT',
      'WOOD',
    ]) {
      expect(find.text(label), findsOneWidget, reason: 'settings: $label');
    }
    _expectChosen(tester, 'theme', _options(BoardTheme.values), 'navy');
    _expectChosen(tester, 'style', _options(PieceStyle.values), 'classic');
    _expectChosen(tester, 'surface', _options(BoardSurface.values), 'felt');

    final samples = {
      for (final style in PieceStyle.values)
        style: tester.widget<Text>(
          find.byKey(Key('settings-style-sample-${style.name}')),
        ),
    };
    expect(samples[PieceStyle.classic]!.data, '♞\u{FE0E}');
    expect(samples[PieceStyle.outline]!.data, '♘\u{FE0E}');
    expect(samples[PieceStyle.flat]!.data, 'N');
    expect(samples[PieceStyle.classic]!.style!.fontFamily, Fonts.pieces);
    expect(samples[PieceStyle.flat]!.style!.fontFamily, Fonts.plexMono);
    expect(samples[PieceStyle.flat]!.style!.fontWeight, FontWeight.w600);
    for (final sample in samples.values) {
      expect(sample.style!.color, styleSampleInk);
      expect(sample.style!.fontSize, 22);
      expect(sample.style!.shadows, styleSampleShadow);
    }
  });

  testWidgets('each board colour applies at once and changes nothing else', (
    tester,
  ) async {
    final harness = await _pumpBoardAndSettings(tester);
    for (final theme in [...BoardTheme.values.reversed]) {
      final before = _look(tester);
      await _choose(tester, 'settings-theme-${theme.name}');
      final after = _look(tester);
      expect(
        after.a1,
        theme.dark,
        reason: 'settings-look: a1 takes ${theme.name}\'s dark square',
      );
      expect(
        _squareColour(tester, 'h1'),
        theme.light,
        reason: 'settings-look: h1 takes ${theme.name}\'s light square',
      );
      expect(
        (after.knight, after.font, after.surface),
        (before.knight, before.font, before.surface),
        reason: 'settings-look: a colour leaves pieces and surface alone',
      );
      _expectChosen(tester, 'theme', _options(BoardTheme.values), theme.name);
      expect(
        tester
            .widget<ColoredBox>(
              find.descendant(
                of: find.byKey(const Key('settings-surface-strip-wood')),
                matching: find.byType(ColoredBox),
              ),
            )
            .color,
        theme.dark,
        reason: 'settings-look: the surface strips show the theme\'s dark',
      );
      expect(harness.settings.board.value.theme, theme);
    }
  });

  testWidgets('each piece style applies at once and changes nothing else', (
    tester,
  ) async {
    await _pumpBoardAndSettings(tester);
    const expected = {
      PieceStyle.flat: ('N', Fonts.plexMono),
      PieceStyle.outline: ('♘\u{FE0E}', Fonts.pieces),
      PieceStyle.classic: ('♞\u{FE0E}', Fonts.pieces),
    };
    for (final MapEntry(key: style, value: (glyph, font)) in expected.entries) {
      final before = _look(tester);
      await _choose(tester, 'settings-style-${style.name}');
      final after = _look(tester);
      expect(
        (after.knight, after.font),
        (glyph, font),
        reason: 'settings-look: the g1 knight is drawn in ${style.name}',
      );
      expect(
        (after.a1, after.surface),
        (before.a1, before.surface),
        reason: 'settings-look: a style leaves colour and surface alone',
      );
      _expectChosen(tester, 'style', _options(PieceStyle.values), style.name);
    }
  });

  testWidgets('each surface applies at once and changes nothing else', (
    tester,
  ) async {
    await _pumpBoardAndSettings(tester);
    for (final surface in [
      BoardSurface.plain,
      BoardSurface.wood,
      BoardSurface.felt,
    ]) {
      final before = _look(tester);
      await _choose(tester, 'settings-surface-${surface.name}');
      final after = _look(tester);
      expect(
        after.surface,
        surface.pattern,
        reason: 'settings-look: the board\'s surface layer is ${surface.name}',
      );
      expect(
        (after.a1, after.knight, after.font),
        (before.a1, before.knight, before.font),
        reason: 'settings-look: a surface leaves colour and pieces alone',
      );
      _expectChosen(
        tester,
        'surface',
        _options(BoardSurface.values),
        surface.name,
      );
    }
  });

  testWidgets('a game started from the menu is in the saved look; a change '
      'reaches the board behind the pause card and is saved', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = AppStore.memory(
      documents: {
        StoreDoc.settings: {
          'board': {
            'theme': 'teal',
            'pieceStyle': 'outline',
            'surface': 'wood',
            'takebackAllowed': false,
          },
        },
      },
    );
    await tester.pumpWidget(
      HonestChessApp(
        computerFactory: FakeComputers().call,
        store: store,
        platform: FakePlatformChannel(),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('menu-vs-computer')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.scrollUntilVisible(
      find.byKey(const Key('csetup-start')),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byKey(const Key('csetup-start')));
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
    // A running clock never lets the transition settle.
    await tester.pump(const Duration(milliseconds: 500));
    expect(_look(tester), (
      a1: BoardTheme.teal.dark,
      knight: '♘\u{FE0E}',
      font: Fonts.pieces,
      surface: BoardSurface.wood.pattern,
    ), reason: 'settings-look: the first board is in the saved look');
    final root = tester.state<HonestChessAppState>(find.byType(HonestChessApp));
    expect(
      root.controller.game.options.takebackAllowed,
      isFalse,
      reason: 'settings-look: the first game takes the saved takeback rule',
    );

    await tester.tap(find.byKey(const Key('pause-pill')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    Navigator.of(tester.element(find.byKey(const Key('board'))))
        .push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
    await tester.pumpAndSettle();
    await _choose(tester, 'settings-theme-violet');
    expect(
      tester
          .widget<ColoredBox>(
            find.descendant(
              of: find.byKey(const Key('sq-a1'), skipOffstage: false),
              matching: find.byType(ColoredBox, skipOffstage: false),
            ),
          )
          .color,
      BoardTheme.violet.dark,
      reason: 'settings-look: the board behind Settings changes at once',
    );
    expect(root.controller.options.theme, BoardTheme.violet);
    await store.flush();
    expect(
      decodeBoard(
        (await store.read(StoreDoc.settings) as Loaded).data['board'],
      ),
      const BoardOptions(
        theme: BoardTheme.violet,
        pieceStyle: PieceStyle.outline,
        surface: BoardSurface.wood,
        takebackAllowed: false,
      ),
      reason: 'settings-look: the change is saved with the rest',
    );

    // Settings is taller than the phone now: back is at the top.
    await tester.drag(
      find.byKey(const Key('settings-list')),
      const Offset(0, 2000),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-back')));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsNothing);
    expect(
      find.byKey(const Key('pause-card')),
      findsOneWidget,
      reason: 'settings-look: back returns to the paused game',
    );
    expect(_look(tester).a1, BoardTheme.violet.dark);
  });
}
