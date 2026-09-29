import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:honest_chess/ui/brand/honest_mark.dart';
import 'package:honest_chess/ui/brand/svg_path.dart';

import '../../guards/launcher_icon_rules.dart';
import '../../guards/repo_files.dart';

String _hex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// The rook `<path>` of an inline mark: its fill, scale and path data.
({String fill, double scale, String d})? _rook(String svg) {
  final m = RegExp(
    r'<path fill="(#[0-9A-Fa-f]{6})"\s+transform="translate\(32,32\) '
    r'scale\(([\d.]+)\) translate\(-32,-32\)"\s+d="([^"]*)"',
  ).firstMatch(svg);
  if (m == null) return null;
  return (
    fill: m[1]!.toUpperCase(),
    scale: double.parse(m[2]!),
    d: m[3]!.trim().replaceAll(RegExp(r'\s+'), ' '),
  );
}

Offset _midpoint(Path path) {
  final metric = path.computeMetrics().single;
  return metric.getTangentForOffset(metric.length / 2)!.position;
}

void main() {
  group('the marks are the brand sources\' geometry', () {
    final studio = readFile('assets/brand/STUDIO-MARK.svg');
    final launcher = inlineMark(
      readFile('assets/brand/android-foreground.svg'),
    );
    final ours = [for (final c in HonestMark.corners) (_hex(c.stroke), c.d)];

    test('the arcade mark is STUDIO-MARK.svg\'s four corners', () {
      // cornerPaths only matches a group stroked 6 wide, round caps and
      // joins.
      expect(cornerPaths(studio), ours);
      expect(HonestMark.strokeWidth, 6);
      final paint = HonestMark.cornerPaint(const Color(0xFF00D6B4));
      expect(paint.strokeCap, StrokeCap.round);
      expect(paint.strokeJoin, StrokeJoin.round);
      expect(paint.strokeWidth, 6);
      expect(paint.style, PaintingStyle.stroke);
    });

    test('the chess mark is the launcher\'s corners and rook', () {
      expect(launcher, isNotNull);
      expect(cornerPaths(launcher!), ours);
      final rook = _rook(launcher);
      expect(rook, isNotNull);
      expect(rook!.d, HonestMark.rookD);
      expect(rook.fill, _hex(HonestMark.rookFill));
      expect(rook.scale, HonestMark.rookScale);
    });
  });

  group('the parser draws the geometry', () {
    test('each corner\'s middle lies on its arc', () {
      const want = [
        Offset(5.05, 5.05),
        Offset(58.95, 5.05),
        Offset(58.95, 58.95),
        Offset(5.05, 58.95),
      ];
      for (final (i, path) in HonestMark.cornerPaths.indexed) {
        final got = _midpoint(path);
        expect(got.dx, closeTo(want[i].dx, 0.05), reason: 'corner $i');
        expect(got.dy, closeTo(want[i].dy, 0.05), reason: 'corner $i');
      }
    });

    test('a flipped sweep flag bends the arc the other way', () {
      final got = _midpoint(
        parseSvgPath('M 3 21 L 3 10 A 7 7 0 0 0 10 3 L 21 3'),
      );
      expect(got.dx, closeTo(7.95, 0.05));
      expect(got.dy, closeTo(7.95, 0.05));
    });

    test('the rook, scaled 1.32 about the centre, spans its bounds', () {
      // 32 + 1.32 × (v − 32) for the path's extremes 20.9, 43.1, 15, 48.2.
      final b = HonestMark.rookPath.getBounds();
      expect(b.left, closeTo(17.348, 0.001));
      expect(b.right, closeTo(46.652, 0.001));
      expect(b.top, closeTo(9.56, 0.001));
      expect(b.bottom, closeTo(53.384, 0.001));
    });

    test('anything outside the subset is refused', () {
      for (final d in [
        'M 3 21 l 3 10',
        'M 3 21 C 1 2 3 4 5 6',
        'M 3 21 L 3 1.0.0',
        'M 3 21 L 3',
        '3 21',
      ]) {
        expect(
          () => parseSvgPath(d),
          throwsA(isA<FormatException>()),
          reason: d,
        );
      }
    });
  });

  testWidgets('a mark is drawn at the size it is given, without semantics', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      const Center(child: HonestMark.arcade(120, key: Key('mark'))),
    );
    expect(tester.getSize(find.byKey(const Key('mark'))), const Size(120, 120));
    expect(
      find.descendant(
        of: find.byKey(const Key('mark')),
        matching: find.byType(ExcludeSemantics),
      ),
      findsOneWidget,
    );
    handle.dispose();
  });
}
