// Flutter's own accessibility guidelines on every screen and state of
// a11y_cases.dart (#104): every control is at least 48 × 48 dp and
// labelled, and every text colour is one #99 proves and reads on what it
// is drawn over (#141). Three phone sizes at
// text scale 1.0 and 1.3, each screen at its top and then scrolled to its
// end. The board's squares are the one tap-target exception — eight must
// fit across the phone — so the tap-target check skips nodes tagged
// `a11yExemptSquare`, requires every node it skipped to be a square, and
// the squares' size is checked on its own. The complement: an undersized
// or unlabelled control fails, and so does a tag on something that is not
// a square (the "the checks can fail" group).
@Tags(['a11y'])
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:honest_chess/ui/board/board_view.dart';

import '../support/app_harness.dart';
import '../support/checked_text_guideline.dart';
import 'a11y_cases.dart';

/// The phone sizes checked, in dp, with a status bar and a gesture bar.
const _sizes = [Size(320, 568), Size(360, 640), Size(390, 844)];
const _scales = [1.0, 1.3];
const _insets = FakeViewPadding(top: 24, bottom: 48);

/// The least a square may measure at text scale 1.0 on a screen this
/// size with no system bars, by width (owner, #104's approval gate,
/// 2026-09-28): a board as wide as the screen allows.
final _squareFloor = {const Size(320, 568): 38.0, const Size(360, 640): 43.0};

/// The least a square may measure with the status and gesture bars in
/// ([_insets]), by screen size and text scale; there the board is limited
/// by the screen's height. At 1.0 these are the owner's floors for short
/// phones (#104, 2026-09-29: "1) Accept 39/30"); at 1.3 they are the
/// smallest squares this suite measured on 2026-09-29, kept so the board
/// cannot shrink further unnoticed (planner, #104).
final _squareFloorWithBars = {
  (const Size(320, 568), 1.0): 30.0,
  (const Size(360, 640), 1.0): 39.0,
  (const Size(320, 568), 1.3): 24.0,
  (const Size(360, 640), 1.3): 36.0,
};

/// A board square's node, as #102 labels it: "e4, empty".
final _squareLabel = RegExp(r'^[a-h][1-8], ');

final _stock = androidTapTargetGuideline as MinimumTapTargetGuideline;

/// A tappable node the tap-target check left out because it carries
/// [a11yExemptSquare].
typedef Exempt = ({String label, Size size});

/// The stock `androidTapTargetGuideline` (48 × 48 dp), except that a node
/// tagged [a11yExemptSquare] is left out and written to [exempt] with its
/// size, so the test can prove each one is a square; and that a node
/// touching the edge of a scrolling view it is in is left out as the stock
/// check means to (it may be part-way scrolled out of view), with both
/// rects compared on screen. The stock check compares a rect already
/// moved into the scrolling view's parent's space with the view's own
/// rect; on this suite's first runs (2026-09-29) that failed How to play's
/// tabs, half scrolled out of view at 320 × 568.
class RecordingTapTargetGuideline extends MinimumTapTargetGuideline {
  RecordingTapTargetGuideline(this.exempt, {this.view})
    : super(size: _stock.size, link: _stock.link);

  final List<Exempt> exempt;

  /// The view the nodes are measured in (the test's only one).
  final ui.FlutterView? view;

  @override
  bool shouldSkipNode(SemanticsNode node) {
    if (super.shouldSkipNode(node)) return true;
    final bounds = _onScreen(node);
    for (var a = node.parent; a != null; a = a.parent) {
      if (a.flagsCollection.hasImplicitScrolling &&
          _atEdge(bounds, _onScreen(a))) {
        return true;
      }
    }
    if (!(node.tags?.contains(a11yExemptSquare) ?? false)) return false;
    exempt.add((
      label: node.getSemanticsData().label,
      size: bounds.size / (view?.devicePixelRatio ?? 1),
    ));
    return true;
  }

  static Rect _onScreen(SemanticsNode node) {
    var bounds = node.rect;
    for (SemanticsNode? n = node; n != null; n = n.parent) {
      final transform = n.transform;
      if (transform != null) {
        bounds = MatrixUtils.transformRect(transform, bounds);
      }
    }
    return bounds;
  }

  /// The stock check's own test: within 0.001 of any edge.
  static bool _atEdge(Rect child, Rect parent) =>
      !(child.left - parent.left > .001 &&
          parent.right - child.right > .001 &&
          child.top - parent.top > .001 &&
          parent.bottom - child.bottom > .001);
}

SemanticsNode _root(WidgetTester tester) =>
    tester.binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode!;

/// The labels of the tappable nodes on screen, the squares aside.
Set<String> _controls(WidgetTester tester) {
  final out = <String>{};
  void visit(SemanticsNode node) {
    final data = node.getSemanticsData();
    if (!node.isMergedIntoParent &&
        !data.flagsCollection.isHidden &&
        (data.hasAction(SemanticsAction.tap) ||
            data.hasAction(SemanticsAction.longPress) ||
            data.hasAction(SemanticsAction.increase) ||
            data.hasAction(SemanticsAction.decrease)) &&
        !_squareLabel.hasMatch(data.label)) {
      out.add('${data.label}|${data.hint}');
    }
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(_root(tester));
  return out;
}

/// The three guidelines, where the screen is now; returns the nodes the
/// tap-target check left out.
Future<List<Exempt>> _check(WidgetTester tester, String where) async {
  final exempt = <Exempt>[];
  await expectLater(
    tester,
    meetsGuideline(RecordingTapTargetGuideline(exempt, view: tester.view)),
    reason: 'guidelines: $where has a tap target under 48 × 48 dp',
  );
  await expectLater(
    tester,
    meetsGuideline(labeledTapTargetGuideline),
    reason: 'guidelines: $where has a tap target with no label',
  );
  await expectLater(
    tester,
    meetsGuideline(const CheckedTextGuideline()),
    reason: 'guidelines: $where draws a text colour no contrast pair proves',
  );
  for (final e in exempt) {
    expect(
      e.label,
      matches(_squareLabel),
      reason: 'guidelines: $where exempts "${e.label}", which is no square',
    );
  }
  return exempt;
}

/// Checks the screen at its top, then after each step down every vertical
/// scrollable until its end, so a control a short screen builds only once
/// scrolled to is checked too. Returns every control seen and every square
/// left out.
Future<({Set<String> controls, List<Exempt> exempt})> _checkScrolled(
  WidgetTester tester,
  String name,
) async {
  final controls = _controls(tester);
  final exempt = await _check(tester, name);
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
      controls.addAll(_controls(tester));
      exempt.addAll(
        await _check(tester, '$name, scrolled to ${position.pixels}'),
      );
    }
  }
  return (controls: controls, exempt: exempt);
}

void _view(
  WidgetTester tester,
  Size size,
  double scale, {
  FakeViewPadding insets = _insets,
}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = insets;
  tester.view.viewPadding = insets;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

/// A square's side: the board's width over eight.
double _square(WidgetTester tester) =>
    tester.getSize(find.byKey(const Key('board'))).width / 8;

String _at(Size size, double scale) =>
    '${size.width.toInt()} × ${size.height.toInt()} at $scale';

void main() {
  var boardsChecked = 0, squaresUnder48 = 0;

  group('every screen', () {
    for (final c in a11yCases) {
      for (final size in _sizes) {
        for (final scale in _scales) {
          final where = '${c.name}, ${_at(size, scale)}';
          testWidgets(where, (tester) async {
            _view(tester, size, scale);
            final handle = tester.ensureSemantics();
            await c.pump(tester);
            final board = c.name.startsWith('the board');
            final seen = await _checkScrolled(tester, where);
            expect(
              seen.controls.length,
              greaterThanOrEqualTo(c.controls),
              reason:
                  'guidelines: the walk reached each of ${c.name}\'s '
                  '${c.controls} controls',
            );
            expect(
              seen.exempt.length,
              board && !c.covered ? greaterThanOrEqualTo(64) : 0,
              reason:
                  'guidelines: only the board\'s squares are exempt, and '
                  'none are reachable under a card',
            );
            if (board) {
              boardsChecked++;
              squaresUnder48 += seen.exempt
                  .where((e) => e.size.width < 48 || e.size.height < 48)
                  .length;
              final floor = _squareFloorWithBars[(size, scale)];
              if (floor != null) {
                final whose = scale == 1.0
                    ? 'the owner\'s floor for short phones'
                    : 'the current layout\'s floor at this text scale';
                expect(
                  _square(tester),
                  greaterThanOrEqualTo(floor),
                  reason:
                      'guidelines: with the system bars in, a square is at '
                      'least $floor dp at ${_at(size, scale)} ($whose)',
                );
              }
            }
            handle.dispose();
          });
        }
      }
    }
  });

  group('the squares, the one tap-target exception', () {
    for (final c in a11yCases.where((c) => c.name.startsWith('the board'))) {
      for (final MapEntry(key: size, value: floor) in _squareFloor.entries) {
        testWidgets('${c.name}: at least $floor dp at ${_at(size, 1.0)}', (
          tester,
        ) async {
          _view(tester, size, 1.0, insets: FakeViewPadding.zero);
          await c.pump(tester);
          expect(
            _square(tester),
            greaterThanOrEqualTo(floor),
            reason:
                'guidelines: with no system bars, a square is at least '
                '$floor dp at ${size.width.toInt()} wide (the owner\'s floor '
                'with the whole screen the app\'s)',
          );
        });
      }
    }
  });

  group('the checks can fail', () {
    Future<void> pumpBare(WidgetTester tester, Widget child) async {
      _view(tester, const Size(360, 640), 1);
      await pumpUnderScope(tester, Center(child: child));
    }

    testWidgets('a 40 dp button fails the tap-target check', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpBare(
        tester,
        SizedBox.square(
          dimension: 40,
          child: Semantics(
            button: true,
            label: 'Small',
            onTap: () {},
            child: const SizedBox.expand(),
          ),
        ),
      );
      final result = await RecordingTapTargetGuideline(
        [],
        view: tester.view,
      ).evaluate(tester);
      expect(
        result.passed,
        isFalse,
        reason: 'guidelines: an undersized control passed',
      );
      handle.dispose();
    });

    testWidgets('an unlabelled tappable fails the label check', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpBare(
        tester,
        GestureDetector(
          onTap: () {},
          child: const SizedBox.square(dimension: 60),
        ),
      );
      final result = await labeledTapTargetGuideline.evaluate(tester);
      expect(result.passed, isFalse);
      handle.dispose();
    });

    testWidgets('a tagged node is left out and recorded, and a tag on '
        'something that is not a square is caught', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpBare(
        tester,
        Semantics(
          container: true,
          explicitChildNodes: true,
          tagForChildren: a11yExemptSquare,
          child: Semantics(
            button: true,
            label: 'Small',
            onTap: () {},
            child: const SizedBox.square(dimension: 40),
          ),
        ),
      );
      final exempt = <Exempt>[];
      final result = await RecordingTapTargetGuideline(
        exempt,
        view: tester.view,
      ).evaluate(tester);
      expect(result.passed, isTrue);
      expect(exempt.single.label, 'Small');
      expect(exempt.single.size, const Size(40, 40));
      await expectLater(
        _check(tester, 'a tagged button'),
        throwsA(
          isA<TestFailure>().having(
            (f) => f.message,
            'message',
            contains('which is no square'),
          ),
        ),
      );
      handle.dispose();
    });
  });

  tearDownAll(() {
    if (boardsChecked == 0) return;
    // The exemption is needed: somewhere above, a square it left out was
    // under 48 dp.
    expect(
      squaresUnder48,
      greaterThan(0),
      reason: 'guidelines: the square exemption was never needed',
    );
  });
}
