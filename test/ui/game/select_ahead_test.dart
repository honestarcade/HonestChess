// Selecting a piece during the computer's turn (#182): a tap on one of
// your pieces shows its ring and its dots as if it were your move, and
// nothing is ever played until it is; the selection outlives the
// computer's reply only while the piece can still move.
import 'package:flutter_test/flutter_test.dart';

import 'package:honest_chess/engine/engine.dart' hide play;
import 'package:honest_chess/ui/board/board_options.dart';
import 'package:honest_chess/ui/game/computer_turns.dart';
import 'package:honest_chess/ui/game/game_controller.dart';

import '../board/board_interaction_test.dart' show tap, dragTo, centre;
import 'fake_computer.dart';
import 'player_panel_test.dart' show pumpGame, play, Harness;

const _asWhite = VsComputer(
  playerColour: Colour.white,
  step: Strength.club,
  seed: 1,
);

List<String> _moves(GameController c) => [
  for (final m in c.game.moves) m.toUci(),
];

/// The squares marked with a dot, and with a ring, in algebraic order and
/// joined by spaces.
({String dots, String rings}) _marks(GameController c) {
  String marked(SquareMark mark) => ([
    for (final s in Square.values)
      if (c.state.markAt(s) == mark) s.name,
  ]..sort()).join(' ');
  return (dots: marked(SquareMark.dot), rings: marked(SquareMark.ring));
}

/// You as White against the fake computer, from [fen] or after `e2e4`;
/// either way it is the computer's turn and its request is out.
Future<(Harness, FakeComputers)> _computersTurn(
  WidgetTester tester, {
  String? fen,
  BoardOptions options = const BoardOptions(),
}) async {
  final fakes = FakeComputers();
  final h = await pumpGame(
    tester,
    mode: _asWhite,
    fen: fen,
    options: options,
    computer: fakes,
  );
  if (fen == null) await play(tester, h.controller, 'e2e4');
  await tester.pump();
  expect(h.controller.state.thinking, isTrue, reason: 'test: its turn');
  expect(fakes.current.requests, hasLength(1));
  return (h, fakes);
}

/// The computer answers [uci]; its move lands.
Future<void> _reply(Harness h, FakeComputers fakes, String uci) async {
  fakes.current.last.move(uci);
  await h.clock.advance(minThinkTime);
}

void main() {
  testWidgets('a selection on its turn shows dots as if yours, and a target '
      'tap plays nothing', (tester) async {
    final (h, fakes) = await _computersTurn(tester);
    final c = h.controller;
    await tap(tester, 'f1');
    expect(
      c.state.selection,
      Square.parse('f1'),
      reason: 'select ahead: your piece is selected on its turn',
    );
    expect(c.state.tintAt(Square.parse('f1')), SquareTint.selected);
    expect(_marks(c), (
      dots: 'a6 b5 c4 d3 e2',
      rings: '',
    ), reason: 'select ahead: the bishop\'s moves with you to move');
    expect(c.inputLocked, isTrue, reason: 'select ahead: still locked');

    await tap(tester, 'c4');
    expect(_moves(c), [
      'e2e4',
    ], reason: 'select ahead: a target tap on its turn plays nothing');
    expect(
      c.state.selection,
      isNull,
      reason: 'select ahead: and puts the piece down',
    );
    expect(c.move(Square.parse('f1'), Square.parse('c4')), isFalse);
    expect(fakes.current.requests, hasLength(1), reason: 'no new request');

    await _reply(h, fakes, 'e7e5');
    expect(_moves(c), ['e2e4', 'e7e5'], reason: 'its own move still lands');
  });

  testWidgets('the piece again, an empty square or its piece put it down; '
      'its pieces are never selected', (tester) async {
    final (h, fakes) = await _computersTurn(tester);
    final c = h.controller;
    await tap(tester, 'g1');
    await tap(tester, 'g1');
    expect(c.state.selection, isNull, reason: 'select ahead: tap again');
    await tap(tester, 'g1');
    await tap(tester, 'd5');
    expect(c.state.selection, isNull, reason: 'select ahead: an empty square');
    await tap(tester, 'g1');
    await tap(tester, 'b8');
    expect(c.state.selection, isNull, reason: 'select ahead: its piece');
    await tap(tester, 'b8');
    expect(
      c.state.selection,
      isNull,
      reason: 'select ahead: the computer\'s pieces are not yours to pick',
    );
    await tap(tester, 'g1');
    await tap(tester, 'b1');
    expect(c.state.selection, Square.parse('b1'), reason: 'switch pieces');
    expect(_moves(c), ['e2e4']);
    await _reply(h, fakes, 'e7e5');
  });

  testWidgets('drags stay refused on its turn', (tester) async {
    final (h, fakes) = await _computersTurn(tester);
    final c = h.controller;
    expect(c.canDrag(Square.parse('d2')), isFalse);
    await dragTo(tester, 'd2', centre(tester, 'd4'));
    expect(_moves(c), ['e2e4'], reason: 'select ahead: no drag move');
    await _reply(h, fakes, 'e7e5');
  });

  testWidgets('kept through a quiet reply, with its dots refreshed; a dot '
      'tap then plays exactly that move', (tester) async {
    final (h, fakes) = await _computersTurn(tester);
    final c = h.controller;
    await tap(tester, 'f1');
    await _reply(h, fakes, 'b7b5');
    expect(
      c.state.selection,
      Square.parse('f1'),
      reason: 'select ahead: kept while the piece can still move',
    );
    expect(_marks(c), (
      dots: 'c4 d3 e2',
      rings: 'b5',
    ), reason: 'select ahead: the dots follow the new position');
    expect(c.inputLocked, isFalse);
    await tap(tester, 'b5');
    expect(_moves(c), [
      'e2e4',
      'b7b5',
      'f1b5',
    ], reason: 'select ahead: one tap on a target plays that move');
    await _reply(h, fakes, 'c7c6');
  });

  testWidgets('cleared when the reply captures the piece', (tester) async {
    final (h, fakes) = await _computersTurn(
      tester,
      fen: 'rnbqkbnr/pppp1ppp/8/4p3/3P4/8/PPP1PPPP/RNBQKBNR b KQkq - 0 2',
    );
    final c = h.controller;
    await tap(tester, 'd4');
    expect(_marks(c), (dots: 'd5', rings: 'e5'));
    await _reply(h, fakes, 'e5d4');
    expect(
      c.state.selection,
      isNull,
      reason: 'select ahead: cleared when the piece is captured',
    );
    expect(_marks(c), (dots: '', rings: ''));
  });

  testWidgets('cleared when the reply pins the piece', (tester) async {
    final (h, fakes) = await _computersTurn(
      tester,
      fen: '4kb2/8/8/8/8/8/3N4/4K3 b - - 0 1',
    );
    final c = h.controller;
    await tap(tester, 'd2');
    expect(_marks(c).dots, isNotEmpty);
    await _reply(h, fakes, 'f8b4');
    expect(
      c.state.selection,
      isNull,
      reason: 'select ahead: cleared when the piece is pinned',
    );
    expect(_marks(c).dots, isEmpty);
  });

  testWidgets('cleared when the piece cannot answer the check', (tester) async {
    final (h, fakes) = await _computersTurn(
      tester,
      fen: '4k2r/8/8/8/8/8/P7/4K3 b - - 0 1',
    );
    final c = h.controller;
    await tap(tester, 'a2');
    expect(_marks(c).dots, 'a3 a4');
    await _reply(h, fakes, 'h8h1');
    expect(
      c.state.selection,
      isNull,
      reason: 'select ahead: cleared when it cannot answer check',
    );
  });

  testWidgets('kept when the piece can answer the check', (tester) async {
    final (h, fakes) = await _computersTurn(
      tester,
      fen: '4k2r/8/8/8/8/8/6R1/4K3 b - - 0 1',
    );
    final c = h.controller;
    await tap(tester, 'g2');
    await _reply(h, fakes, 'h8h1');
    expect(c.state.selection, Square.parse('g2'));
    expect(_marks(c), (
      dots: 'g1',
      rings: '',
    ), reason: 'select ahead: only the move that answers check');
  });

  testWidgets('with its king in check, the dots never take the king', (
    tester,
  ) async {
    final (h, fakes) = await _computersTurn(
      tester,
      fen: '4k3/8/8/8/8/8/4Q3/4K3 b - - 0 1',
    );
    final c = h.controller;
    await tap(tester, 'e2');
    expect(c.state.selection, Square.parse('e2'));
    expect(
      c.state.markAt(Square.parse('e8')),
      SquareMark.none,
      reason: 'select ahead: a king is never a target',
    );
    expect(c.state.markAt(Square.parse('e7')), SquareMark.dot);
    await _reply(h, fakes, 'e8d8');
  });

  testWidgets('a pause or a takeback during its turn drops the selection', (
    tester,
  ) async {
    final (h, fakes) = await _computersTurn(tester);
    final c = h.controller;
    await tap(tester, 'g1');
    expect(c.pause(), isTrue);
    expect(c.state.selection, isNull, reason: 'select ahead: pause clears');
    await tap(tester, 'g1');
    expect(c.state.selection, isNull, reason: 'select ahead: not while paused');
    expect(c.resume(), isTrue);
    await tester.pump();
    await tap(tester, 'g1');
    expect(c.takeBack(), isTrue);
    expect(c.state.selection, isNull, reason: 'select ahead: takeback clears');
    expect(fakes.current.requests.length, greaterThanOrEqualTo(1));
  });

  testWidgets('two players: a tap on the side not to move selects nothing', (
    tester,
  ) async {
    final h = await pumpGame(tester);
    final c = h.controller;
    await tap(tester, 'e7');
    expect(c.state.selection, isNull, reason: 'two players unchanged');
  });
}
