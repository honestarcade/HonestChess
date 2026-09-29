import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:honest_chess/ui/theme/palette.dart';
import 'package:honest_chess/ui/widgets/option_button.dart';
import 'package:honest_chess/ui/widgets/screen_header.dart';

import '../../flutter_test_config.dart';
import '../piece_font_test.dart' show cmapCodePoints;

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(body: Center(child: child)),
  ),
);

BoxDecoration _box(WidgetTester tester, Key key) =>
    tester
            .widget<DecoratedBox>(
              find
                  .descendant(
                    of: find.byKey(key),
                    matching: find.byType(DecoratedBox),
                  )
                  .first,
            )
            .decoration
        as BoxDecoration;

Color? _textColour(WidgetTester tester, String text) =>
    tester.renderObject<RenderParagraph>(find.text(text)).text.style?.color;

void main() {
  test('every bundled Outfit face draws the back button\'s ‹', () {
    for (final file in testFonts['Outfit']!) {
      expect(
        cmapCodePoints(File(file).readAsBytesSync()),
        contains(backGlyph.runes.single),
        reason: 'screen-header: $file has U+2039, so ‹ needs no fallback',
      );
    }
  });

  testWidgets('the header shows ‹, the title and a kicker; back pops', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const Scaffold(
                  body: ScreenHeader(
                    title: 'Two players',
                    kicker: 'ONE PHONE',
                    kickerColor: Palette.violet,
                  ),
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text(backGlyph), findsOneWidget);
    expect(
      tester.widget<Text>(find.text(backGlyph)).style!.fontFamily,
      Fonts.outfit,
      reason: 'screen-header: ‹ is drawn in Outfit',
    );
    expect(find.text('Two players'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('ONE PHONE')).style!.color,
      Palette.violet,
      reason: 'screen-header: the kicker takes the caller\'s colour',
    );
    expect(
      tester.getSize(find.byKey(const Key('header-back'))),
      const Size(48, 48),
      reason: 'screen-header: back has a 48 dp touch area',
    );
    expect(
      tester.getSemantics(find.byKey(const Key('header-back'))),
      isSemantics(isButton: true, label: 'Back', hasTapAction: true),
    );
    await tester.tap(find.byKey(const Key('header-back')));
    await tester.pumpAndSettle();
    expect(find.text('Two players'), findsNothing, reason: 'back pops');
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('OptionButton draws each look and accent', (tester) async {
    const key = Key('option');
    Future<void> show(OptionLook look, Accent accent, bool selected) => _pump(
      tester,
      OptionButton(
        key: key,
        selected: selected,
        onPressed: () {},
        padding: const EdgeInsets.all(9),
        look: look,
        accent: accent,
        child: const Text('LABEL'),
      ),
    );

    const cases = [
      // look, accent, selected, border, fill, label
      (
        OptionLook.settings,
        Accent.teal,
        false,
        Palette.borderSoft,
        Palette.optionFill,
        Palette.textMuted,
      ),
      (
        OptionLook.settings,
        Accent.teal,
        true,
        Palette.teal,
        Palette.optionFill,
        Palette.teal,
      ),
      (
        OptionLook.settingsFilled,
        Accent.teal,
        true,
        Palette.teal,
        Palette.accentFill,
        Palette.teal,
      ),
      (
        OptionLook.setup,
        Accent.teal,
        false,
        Palette.borderIdle,
        Palette.optionFill,
        Palette.textChoice,
      ),
      (
        OptionLook.setup,
        Accent.teal,
        true,
        Palette.teal,
        Palette.tealFillSelected,
        Palette.teal,
      ),
      (
        OptionLook.setup,
        Accent.violet,
        true,
        Palette.violet,
        Palette.violetFillSelected,
        Palette.violetText,
      ),
    ];
    for (final (look, accent, selected, border, fill, label) in cases) {
      await show(look, accent, selected);
      final box = _box(tester, key);
      final what = '${look.name}/${accent.name}/selected=$selected';
      expect(box.border!.top.color, border, reason: 'option: $what border');
      expect(box.border!.top.width, OptionButton.borderWidth);
      expect(box.color, fill, reason: 'option: $what fill');
      expect(_textColour(tester, 'LABEL'), label, reason: 'option: $what');
    }

    await show(OptionLook.setup, Accent.violet, false);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(key)),
    );
    await tester.pump();
    expect(
      _box(tester, key).border!.top.color,
      Palette.violet,
      reason: 'option: a pressed option shows the accent border',
    );
    await gesture.up();
    await tester.pump();
    expect(_box(tester, key).border!.top.color, Palette.borderIdle);
    expect(
      tester.getSize(find.byKey(key)).height,
      greaterThanOrEqualTo(OptionButton.minTouch),
      reason: 'option: at least a 48 dp touch target',
    );
  });
}
