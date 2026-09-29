// Contrast while a finger is down (#141): every screen and state of
// a11y_cases.dart at 390 × 844, each control held down in turn, the
// screen checked with CheckedTextGuideline against the fills its text is
// actually drawn over — a pressed fill included — then the finger lifted
// off without a tap. The complement: a held control whose pressed fill
// no longer reads fails (the last test).
@Tags(['a11y'])
library;

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:honest_chess/ui/board/board_view.dart';

import '../support/app_harness.dart';
import '../support/checked_text_guideline.dart';
import 'a11y_cases.dart';

const _phone = Size(390, 844);
const _insets = FakeViewPadding(top: 24, bottom: 48);

/// Where each control on the screen can be held: the centre of every
/// widget that reacts to a tap, the board's squares aside, when a touch
/// there reaches it (nothing covers it) and it is on the screen.
List<(String, Offset)> _controls(WidgetTester tester) {
  final screen = Offset.zero & _phone;
  final out = <(String, Offset)>[];
  final seen = <Offset>{};
  final taps = find.byWidgetPredicate(
    (w) =>
        (w is GestureDetector && (w.onTap != null || w.onTapDown != null)) ||
        (w is InkResponse && w.onTap != null),
  );
  for (final element in taps.evaluate()) {
    if (element.findAncestorWidgetOfExactType<BoardView>() != null) continue;
    final box = element.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) continue;
    final rect = MatrixUtils.transformRect(
      box.getTransformTo(null),
      Offset.zero & box.size,
    );
    final at = rect.center;
    if (!screen.contains(at) || !seen.add(at)) continue;
    final hit = HitTestResult();
    tester.binding.hitTestInView(hit, at, tester.view.viewId);
    if (!hit.path.any((entry) => entry.target == box)) continue;
    final key = element.widget.key;
    out.add(('${key ?? element.widget.runtimeType} at $at', at));
  }
  return out;
}

/// Holds each control down, checks the screen, and lifts off without a
/// tap.
Future<void> _checkHeld(WidgetTester tester, String where) async {
  for (final (name, at) in _controls(tester)) {
    final finger = await tester.startGesture(at);
    await tester.pump(kPressTimeout);
    await tester.pump(const Duration(milliseconds: 300));
    await expectLater(
      tester,
      meetsGuideline(CheckedTextGuideline(pressedAt: at)),
      reason: 'contrast held: $where, $name held down',
    );
    await finger.cancel();
    await tester.pump(const Duration(milliseconds: 300));
  }
}

/// Holds every control at the top of the screen, then again after each
/// step down every vertical scrollable until its end.
Future<void> _checkScrolled(WidgetTester tester, String where) async {
  await _checkHeld(tester, where);
  final scrollables = find.byType(Scrollable);
  for (var i = 0; i < scrollables.evaluate().length; i++) {
    final position = tester.state<ScrollableState>(scrollables.at(i)).position;
    if (position.axis != Axis.vertical) continue;
    while (position.pixels < position.maxScrollExtent) {
      position.jumpTo(
        math.min(
          position.pixels + position.viewportDimension / 2,
          position.maxScrollExtent,
        ),
      );
      await tester.pump();
      await _checkHeld(tester, '$where, scrolled to ${position.pixels}');
    }
  }
}

void _view(WidgetTester tester) {
  tester.view.physicalSize = _phone;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = _insets;
  tester.view.viewPadding = _insets;
  addTearDown(tester.view.reset);
}

void main() {
  for (final c in a11yCases) {
    testWidgets('${c.name}: every control held down still reads', (
      tester,
    ) async {
      _view(tester);
      await c.pump(tester);
      await _checkScrolled(tester, c.name);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('a held control whose pressed fill does not read fails', (
    tester,
  ) async {
    _view(tester);
    await pumpUnderScope(tester, const _PressedGrey());
    await tester.pump();
    final at = tester.getCenter(find.byKey(const Key('grey')));
    expect(
      const CheckedTextGuideline().evaluate(tester).passed,
      isTrue,
      reason: 'contrast held: white on the idle navy reads',
    );
    final finger = await tester.startGesture(at);
    await tester.pump(kPressTimeout);
    await tester.pump(const Duration(milliseconds: 300));
    final held = CheckedTextGuideline(pressedAt: at).evaluate(tester);
    expect(held.passed, isFalse);
    expect(
      held.reason,
      allOf(contains('"Held" in #FFFFFFFF'), contains('drawn on #FFAAAAAA')),
      reason: 'contrast held: the pressed grey is the background checked',
    );
    await finger.cancel();
    await tester.pump();
  });
}

/// White text on navy that turns grey while pressed, which white does not
/// read on.
class _PressedGrey extends StatefulWidget {
  const _PressedGrey();

  @override
  State<_PressedGrey> createState() => _PressedGreyState();
}

class _PressedGreyState extends State<_PressedGrey> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) => Center(
    child: GestureDetector(
      key: const Key('grey'),
      onTap: () {},
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      child: ColoredBox(
        color: _pressed ? const Color(0xFFAAAAAA) : const Color(0xFF05285F),
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Held',
            style: TextStyle(fontSize: 16, color: Color(0xFFFFFFFF)),
          ),
        ),
      ),
    ),
  );
}
