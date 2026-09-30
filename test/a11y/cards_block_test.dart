// A card over the board shuts out what is behind it for a screen reader
// as its scrim does for a finger (#169): with the pause, declined-draw,
// promotion or result card up, no square, no tool-row button and — but
// for promotion, whose layer sits under the top bar — no pause pill is in
// the semantics tree. The complement: on the open board all of them are.
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:honest_chess/ui/game/game_screen.dart';
import 'package:honest_chess/ui/game/tool_row.dart';

import 'a11y_cases.dart';

final _square = RegExp(r'^[a-h][1-8], ');

/// Every node a screen reader can reach on screen now.
List<SemanticsNode> _nodes(WidgetTester tester) {
  final out = <SemanticsNode>[];
  void walk(SemanticsNode node) {
    out.add(node);
    node
        .debugListChildrenInOrder(DebugSemanticsDumpOrder.traversalOrder)
        .forEach(walk);
  }

  walk(
    tester.binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode!,
  );
  return out;
}

/// Whether the node [finder]'s widget draws, labelled [label], is among
/// [nodes]. A label alone could not tell the tool row's Resign from the
/// pause card's, so each is found by its widget's key; a blocked widget
/// keeps its last node, so that node must also be one the walk reached.
bool _reachable(
  WidgetTester tester,
  List<SemanticsNode> nodes,
  Finder finder,
  String label,
) {
  if (finder.evaluate().isEmpty) return false;
  final node = tester.getSemantics(finder);
  return node.label == label && nodes.contains(node);
}

/// What behind a card is still reachable: squares, tools, the pill.
({int squares, List<String> tools, bool pill}) _behind(
  WidgetTester tester,
  List<SemanticsNode> nodes,
) => (
  squares: nodes.where((n) => _square.hasMatch(n.label)).length,
  tools: [
    for (final tool in Tool.values)
      if (_reachable(tester, nodes, find.byKey(tool.key), tool.semantics))
        tool.semantics,
  ],
  pill: _reachable(
    tester,
    nodes,
    find.byKey(const Key('pause-pill')),
    pausePillLabel,
  ),
);

/// What stays reachable behind [c]'s screen once it is pumped.
Future<({int squares, List<String> tools, bool pill})> _pumpCase(
  WidgetTester tester,
  A11yCase c,
) async {
  // Tall enough that nothing is left out for want of room.
  tester.view.physicalSize = const Size(390, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final handle = tester.ensureSemantics();
  await c.pump(tester);
  final seen = _behind(tester, _nodes(tester));
  handle.dispose();
  return seen;
}

void main() {
  final covered = [
    for (final c in a11yCases)
      if (c.covered) c,
  ];

  test('the cards the board draws are all covered here', () {
    expect(
      covered.map((c) => c.name),
      containsAll([
        'the board, its promotion card',
        'the board, its pause card',
        'the board, its declined-draw card',
        'the board, its result card',
      ]),
      reason: 'cards-block: every card over the board is checked',
    );
  });

  for (final c in covered) {
    testWidgets('${c.name}: nothing behind it is reachable', (tester) async {
      final seen = await _pumpCase(tester, c);
      expect(
        seen.squares,
        0,
        reason: 'cards-block: no square behind ${c.name}',
      );
      expect(
        seen.tools,
        isEmpty,
        reason: 'cards-block: no tool-row button behind ${c.name}',
      );
      expect(
        seen.pill,
        c.name.contains('promotion'),
        reason:
            'cards-block: the pause pill is behind every card but '
            'promotion\'s, which the top bar sits over',
      );
    });
  }

  testWidgets('the open board reaches its squares, tools and pill (the '
      'complement)', (tester) async {
    final open = a11yCases.firstWhere(
      (c) => c.name == 'the board, you to move',
    );
    final seen = await _pumpCase(tester, open);
    expect(seen.squares, 64, reason: 'cards-block: the squares are there');
    expect(seen.tools, [
      for (final tool in Tool.values) tool.semantics,
    ], reason: 'cards-block: the tool row is there');
    expect(seen.pill, isTrue, reason: 'cards-block: the pause pill is there');
  });

  testWidgets('View board lets the board back in (the complement)', (
    tester,
  ) async {
    final view = a11yCases.firstWhere((c) => c.name == 'the board, View board');
    expect(view.covered, isFalse);
    final seen = await _pumpCase(tester, view);
    expect(
      seen.squares,
      64,
      reason:
          'cards-block: once the result card is put away, the squares '
          'are reachable again',
    );
  });
}
