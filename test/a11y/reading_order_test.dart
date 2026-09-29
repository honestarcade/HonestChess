// A heading is read before the text it introduces (#147): a screen reader
// jumping by headings lands on the heading, then reads its section. Text
// left to merge into an enclosing node is spoken with that node, before any
// heading inside it, so no heading may sit under a node that speaks.
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:honest_chess/ui/screens/computer_setup_screen.dart';
import 'package:honest_chess/ui/screens/two_player_setup_screen.dart';

import 'a11y_cases.dart';

SemanticsNode _root(WidgetTester tester) =>
    tester.binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode!;

/// Every node with its enclosing nodes, in the order a screen reader moves
/// through them: a node's own label is read before its children's.
List<(SemanticsNode, List<SemanticsNode>)> _walk(WidgetTester tester) {
  final out = <(SemanticsNode, List<SemanticsNode>)>[];
  void walk(SemanticsNode node, List<SemanticsNode> above) {
    out.add((node, above));
    for (final child in node.debugListChildrenInOrder(
      DebugSemanticsDumpOrder.traversalOrder,
    )) {
      walk(child, [...above, node]);
    }
  }

  walk(_root(tester), const []);
  return out;
}

/// Where the first node whose label starts with [text] is read.
int _readAt(WidgetTester tester, String text) {
  final walk = _walk(tester);
  final at = walk.indexWhere((e) => e.$1.label.startsWith(text));
  expect(at, isNot(-1), reason: 'reading order: "$text" is on screen');
  return at;
}

void _setView(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

A11yCase _case(String name) => a11yCases.firstWhere((c) => c.name == name);

void main() {
  group('the setup screens read top to bottom', () {
    final orders = <String, List<String>>{
      'the vs-computer setup, Custom, Keep playing and the loss warning': [
        'Back',
        'New game vs computer',
        'Runs on device, no network',
        'Strength',
        strengthIntro,
      ],
      'the two-player setup, Custom': [
        'Back',
        'Two players',
        'One phone, pass and play',
        'Time control',
        twoPlayerTimeNote,
        'House rules',
        'Takeback is',
        'Start game',
      ],
    };
    for (final MapEntry(key: name, value: texts) in orders.entries) {
      testWidgets(name, (tester) async {
        final handle = tester.ensureSemantics();
        _setView(tester);
        await _case(name).pump(tester);
        final at = [for (final t in texts) _readAt(tester, t)];
        for (var i = 1; i < texts.length; i++) {
          expect(
            at[i],
            greaterThan(at[i - 1]),
            reason:
                'reading order: "${texts[i - 1]}" is read before '
                '"${texts[i]}"',
          );
        }
        handle.dispose();
      });
    }
  });

  group('no heading sits under a node that speaks', () {
    for (final c in a11yCases) {
      testWidgets(c.name, (tester) async {
        final handle = tester.ensureSemantics();
        _setView(tester);
        await c.pump(tester);
        final problems = [
          for (final (node, above) in _walk(tester))
            if (node.flagsCollection.isHeader)
              for (final outer in above)
                if (outer.label.isNotEmpty)
                  '"${outer.label}" is read before the heading '
                      '"${node.label}"',
        ];
        expect(
          problems,
          isEmpty,
          reason: 'reading order: ${c.name}\n  ${problems.join('\n  ')}',
        );
        handle.dispose();
      });
    }
  });
}
