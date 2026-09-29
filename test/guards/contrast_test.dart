@Tags(['guard'])
library;

// Every text colour and every board pair reads (#99): the contrast maths
// against published reference pairs, the brand sheet's swatches as drawn,
// each board theme's light square against its dark one at the brand
// sheet's 4:1, every Palette.textPairs row at its WCAG threshold, and every
// colour moved for contrast the nearest passing shade of its design value,
// re-derived here so a hand edit cannot drift. The screens' own text is
// held to these rows by test/ui/contrast_screens_test.dart.

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honest_chess/ui/board/board_options.dart';
import 'package:honest_chess/ui/theme/contrast.dart';
import 'package:honest_chess/ui/theme/palette.dart';

String _hex(Color c) =>
    '#${c.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';

bool _sameRgb(Color a, Color b) =>
    (a.toARGB32() & 0xFFFFFF) == (b.toARGB32() & 0xFFFFFF);

/// What [shift]'s colour must read against, from the rows and board pairs
/// it takes part in: as a text colour (at its row's opacity), as the one
/// fill a text sits on, or as a board's dark square.
List<ContrastTarget> _targets(ColourShift shift) {
  final value = shift.value;
  final targets = <ContrastTarget>[];
  for (final row in Palette.textPairs) {
    // A translucent colour is moved for the one row it names; an opaque
    // one for every row that draws it, at that row's opacity.
    final asText = shift.way == ShiftWay.alpha
        ? row.name == shift.name
        : _sameRgb(row.fg, value) && value.a == 1;
    if (asText) {
      targets.add((
        background: row.background,
        minRatio: row.size.minRatio,
        opacity: shift.way == ShiftWay.alpha ? 1 : row.fg.a,
      ));
    }
    if (row.fg.a == 1 && row.on.length == 1 && row.on.single == value) {
      targets.add((
        background: row.seen,
        minRatio: row.size.minRatio,
        opacity: 1,
      ));
    }
  }
  for (final theme in BoardTheme.values) {
    if (theme.dark == value) {
      targets.add((
        background: theme.light,
        minRatio: boardPairRatio,
        opacity: 1,
      ));
    }
  }
  return targets;
}

void main() {
  test('the maths gives the published reference ratios', () {
    const black = Color(0xFF000000), white = Color(0xFFFFFFFF);
    expect(
      contrastRatio(black, white),
      closeTo(21, 0.01),
      reason: 'contrast-maths: black on white is 21:1',
    );
    expect(
      contrastRatio(const Color(0xFF777777), white),
      closeTo(4.48, 0.01),
      reason: 'contrast-maths: #777 on white is 4.48:1',
    );
    expect(
      contrastRatio(white, const Color(0xFF777777)),
      contrastRatio(const Color(0xFF777777), white),
      reason: 'contrast-maths: the ratio does not depend on the order',
    );
    expect(
      composite(const Color(0x80FFFFFF), black),
      const Color(0xFF808080),
      reason: 'contrast-maths: half white over black is mid grey',
    );
    expect(
      surfaceOf(const [black, Color(0x80FFFFFF), Color(0xFF0076F1)]),
      const Color(0xFF0076F1),
      reason: 'contrast-maths: fills composite from the bottom up',
    );
    expect(
      TextSize.of(18, FontWeight.w400),
      TextSize.large,
      reason: 'contrast-maths: 18 dp is large',
    );
    expect(
      TextSize.of(14, FontWeight.w700),
      TextSize.large,
      reason: 'contrast-maths: bold 14 dp is large',
    );
    expect(
      TextSize.of(17.5, FontWeight.w600),
      TextSize.normal,
      reason: 'contrast-maths: semibold 17.5 dp is not',
    );
  });

  test('the palette holds the brand sheet\'s six swatches', () {
    expect(
      [for (final c in Palette.brandSheet) _hex(c)],
      [
        '#FF00D6B4',
        '#FF0076F1',
        '#FF8448FC',
        '#FF05285F',
        '#FFC6483D',
        '#FFF7F5EF',
      ],
      reason: 'contrast-brand: the swatches are the brand sheet\'s, unshifted',
    );
    expect(Palette.teal, Palette.brandSheet[0]);
    expect(Palette.brandBlue, Palette.brandSheet[1]);
    expect(Palette.violet, Palette.brandSheet[2]);
    expect(Palette.screenBg, Palette.brandSheet[3]);
    expect(Palette.barRed, Palette.brandSheet[4]);
    expect(Palette.artInkLight, Palette.brandSheet[5]);
  });

  test('each board theme\'s squares hold 4:1', () {
    final failures = [
      for (final theme in BoardTheme.values)
        if (contrastRatio(theme.light, theme.dark) < boardPairRatio)
          '${theme.name} ${_hex(theme.light)} / ${_hex(theme.dark)} is '
              '${contrastRatio(theme.light, theme.dark).toStringAsFixed(2)}:1',
    ];
    expect(
      failures,
      isEmpty,
      reason:
          'contrast-board: below the brand sheet\'s 4:1\n  '
          '${failures.join('\n  ')}',
    );
  });

  test('every text pair reaches its threshold', () {
    final failures = [
      for (final row in Palette.textPairs)
        if (row.ratio < row.size.minRatio)
          '${row.name}: ${_hex(row.fg)} on ${_hex(row.background)} is '
              '${row.ratio.toStringAsFixed(2)}:1, below '
              '${row.size.minRatio}:1',
    ];
    expect(
      failures,
      isEmpty,
      reason: 'contrast-text: below WCAG AA\n  ${failures.join('\n  ')}',
    );
  });

  test('every moved colour is the nearest passing shade of its design', () {
    final drift = <String>[];
    for (final shift in Palette.shifts) {
      final targets = _targets(shift);
      if (targets.isEmpty) {
        drift.add('${shift.name}: no text pair or board pair uses it');
        continue;
      }
      final Color want;
      try {
        want = switch (shift.way) {
          ShiftWay.alpha => raiseAlpha(shift.design, targets),
          ShiftWay.lighter => shiftLightness(
            shift.design,
            targets,
            lighter: true,
          ),
          ShiftWay.darker => shiftLightness(
            shift.design,
            targets,
            lighter: false,
          ),
        };
      } on StateError catch (e) {
        drift.add('${shift.name}: ${e.message}');
        continue;
      }
      if (want != shift.value) {
        drift.add(
          '${shift.name} is ${_hex(shift.value)}; the nearest passing shade '
          'of ${_hex(shift.design)} is ${_hex(want)}',
        );
      }
    }
    expect(
      drift,
      isEmpty,
      reason: 'contrast-shift: not the nearest pass\n  ${drift.join('\n  ')}',
    );
  });
}
