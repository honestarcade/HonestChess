import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:honest_chess/engine/engine.dart';
import 'package:honest_chess/ui/content/rules_text.dart';

const _designPath = 'ArtSource/design/Honest Chess.dc.html';

/// The entries of the design's `const <name>=[…];` array, each a map of
/// its single-quoted fields.
List<Map<String, String>> _designArray(String html, String name) {
  final start = html.indexOf('const $name=[');
  expect(start, isNot(-1), reason: '$name not found in the design');
  final end = html.indexOf('];', start);
  final body = html.substring(start, end);
  final entries = RegExp(r'\{([^}]*)\}').allMatches(body);
  return [
    for (final entry in entries)
      {
        for (final field in RegExp(
          r"(\w+):'((?:[^'\\]|\\.)*)'",
        ).allMatches(entry.group(1)!))
          field.group(1)!: field.group(2)!.replaceAll(r"\'", "'"),
      },
  ];
}

/// The design's texts this app words differently, each with the text it
/// shows instead. A design tag mapped to a different tag is renamed.
const _ruleCorrections = {
  'DRAWS': (
    tag: 'DRAWS',
    body:
        'Stalemate — no legal move but no check — is a draw. So are the same '
        'position three times, fifty moves each without a capture or a pawn '
        'move, and positions where neither side has enough material to mate. '
        'Each of these ends the game automatically.',
  ),
  'THE CLOCK': (
    tag: 'THE CLOCK',
    body:
        'If a clock runs out, that side loses — unless the other side has no '
        'mating material, in which case it is a draw. The clocks start after '
        "White's first move, and the increment is added after each completed "
        'move from then on.',
  ),
};

const _gestureCorrections = {
  'TAP': (
    tag: 'TAP',
    body:
        'Tap a piece to pick it up, then tap one of its squares to move it — '
        'dotted when legal-move dots are on.',
  ),
  'UNDO': (
    tag: 'UNDO',
    body: 'Takes back the last move — against the computer, its reply too.',
  ),
  'HOLD PAUSE': (
    tag: 'PAUSE',
    body: 'Pause holds the clocks and hides nothing — the board stays visible.',
  ),
};

/// Gestures the design does not have, and the design tag each goes before.
const _addedGestures = {
  'UNDO': (
    tag: 'DRAG',
    body: 'Drag a piece to one of its squares; an illegal drop springs back.',
  ),
};

/// The app's list the design's [entries] become under [corrections] and
/// [added].
List<RuleText> _expected(
  List<Map<String, String>> entries,
  String tagField,
  String bodyField,
  Map<String, RuleText> corrections, [
  Map<String, RuleText> added = const {},
]) => [
  for (final e in entries) ...[
    ?added[e[tagField]],
    corrections[e[tagField]] ?? (tag: e[tagField]!, body: e[bodyField]!),
  ],
];

void main() {
  final html = File(_designPath).readAsStringSync();

  test('the pieces are the design\'s PIECE_RULES, verbatim and in order', () {
    final design = _designArray(html, 'PIECE_RULES');
    expect(design, hasLength(6));
    final byLetter = {for (final k in PieceKind.values) k.letter: k};
    expect(pieceRules.keys, [
      for (final e in design) byLetter[e['p']!.toLowerCase()],
    ]);
    for (final e in design) {
      final text = pieceRules[byLetter[e['p']!.toLowerCase()]]!;
      expect(text.name, e['name']);
      expect(text.body, e['body']);
    }
  });

  test('the rules are the design\'s RULES but for the listed corrections', () {
    final design = _designArray(html, 'RULES');
    expect(design, hasLength(5));
    expect(ruleCards, _expected(design, 'tag', 'body', _ruleCorrections));
    for (final MapEntry(key: tag, value: fixed) in _ruleCorrections.entries) {
      final original = design.firstWhere((e) => e['tag'] == tag);
      expect(fixed.body, isNot(original['body']), reason: tag);
    }
  });

  test('the gestures are the design\'s GESTURES but for the listed '
      'corrections and additions', () {
    final design = _designArray(html, 'GESTURES');
    expect(design, hasLength(5));
    expect(
      gestures,
      _expected(design, 'k', 'v', _gestureCorrections, _addedGestures),
    );
    for (final MapEntry(key: tag, value: fixed)
        in _gestureCorrections.entries) {
      final original = design.firstWhere((e) => e['k'] == tag);
      expect(
        fixed.tag != original['k'] || fixed.body != original['v'],
        isTrue,
        reason: tag,
      );
    }
    for (final added in _addedGestures.values) {
      expect(design.map((e) => e['k']), isNot(contains(added.tag)));
    }
  });
}
