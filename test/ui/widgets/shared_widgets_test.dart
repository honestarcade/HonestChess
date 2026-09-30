import 'dart:io';
import 'dart:ui' as ui;

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

/// Image pixels per logical pixel for [_backInk].
const _inkRatio = 4.0;

/// The ink ‹ paints, in logical pixels from the back box's top left: the
/// near-white pixels inside the box's border, over a black page.
Future<Rect> _backInk(WidgetTester tester, GlobalKey boundary) async {
  final render =
      boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final origin = render.localToGlobal(Offset.zero);
  final box = tester
      .getRect(find.byKey(const Key('test-back-box')))
      .shift(-origin);
  final (width, pixels) = (await tester.runAsync(() async {
    final image = await render.toImage(pixelRatio: _inkRatio);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return (image.width, bytes!);
  }))!;
  // Inside the 1 dp border, so only the glyph can be near white.
  final inner = box.deflate(1.5);
  var (left, top, right, bottom) = (1 << 30, 1 << 30, -1, -1);
  for (
    var y = (inner.top * _inkRatio).ceil();
    y < inner.bottom * _inkRatio;
    y++
  ) {
    for (
      var x = (inner.left * _inkRatio).ceil();
      x < inner.right * _inkRatio;
      x++
    ) {
      final i = (y * width + x) * 4;
      final lit = [0, 1, 2].every((c) => pixels.getUint8(i + c) >= 160);
      if (!lit) continue;
      if (x < left) left = x;
      if (x > right) right = x;
      if (y < top) top = y;
      if (y > bottom) bottom = y;
    }
  }
  expect(right, greaterThanOrEqualTo(0), reason: 'screen-header: ‹ has ink');
  return Rect.fromLTRB(
    left / _inkRatio - box.left,
    top / _inkRatio - box.top,
    (right + 1) / _inkRatio - box.left,
    (bottom + 1) / _inkRatio - box.top,
  );
}

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
                    keyPrefix: 'psetup',
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
      tester.getSize(find.byKey(const Key('psetup-back'))),
      const Size(48, 48),
      reason: 'screen-header: back has a 48 dp touch area',
    );
    expect(
      tester.getSemantics(find.byKey(const Key('psetup-back'))),
      isSemantics(isButton: true, label: 'Back', hasTapAction: true),
    );
    await tester.tap(find.byKey(const Key('psetup-back')));
    await tester.pumpAndSettle();
    expect(find.text('Two players'), findsNothing, reason: 'back pops');
    expect(find.text('open'), findsOneWidget);
  });

  // #165: the ‹ was 16 dp in a 34 dp box, its ink about 5 dp tall. The
  // box is drawn to an image and the white pixels ‹ paints are measured.
  for (final scale in [1.0, 1.3]) {
    testWidgets('‹ fills a third of its box, centred, at $scale× text', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      final boundary = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: ColoredBox(
            color: const Color(0xFF000000),
            child: Center(
              child: RepaintBoundary(
                key: boundary,
                child: const SizedBox(
                  width: 300,
                  child: ScreenHeader(title: 'Settings', keyPrefix: 'test'),
                ),
              ),
            ),
          ),
        ),
      );
      final ink = await _backInk(tester, boundary);
      final box = tester.getSize(find.byKey(const Key('test-back-box')));
      expect(
        box,
        const Size.square(ScreenHeader.backSize),
        reason: 'screen-header: the back box stays 34 dp',
      );
      expect(
        tester.getSize(find.byKey(const Key('test-back'))),
        const Size(48, 48),
        reason: 'screen-header: back keeps its 48 dp touch area',
      );
      expect(
        ink.height / box.height,
        greaterThanOrEqualTo(1 / 3),
        reason: 'screen-header: ‹ is at least a third of its box tall ($ink)',
      );
      expect(
        ink.height / box.height,
        lessThanOrEqualTo(.5),
        reason: 'screen-header: ‹ stays under half its box tall ($ink)',
      );
      final off = ink.center - box.center(Offset.zero);
      expect(
        off.dx.abs() <= 1 && off.dy.abs() <= 1,
        isTrue,
        reason: 'screen-header: ‹ is centred in its box ($ink)',
      );
    });
  }

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
