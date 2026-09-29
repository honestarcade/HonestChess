import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:honest_chess/a11y/announcer.dart';
import 'package:honest_chess/engine/engine.dart';
import 'package:honest_chess/feedback/game_feedback.dart';
import 'package:honest_chess/ui/board/board_options.dart';
import 'package:honest_chess/ui/board/move_animation.dart';
import 'package:honest_chess/ui/board/promotion_sheet.dart';
import 'package:honest_chess/ui/game/computer_turns.dart';
import 'package:honest_chess/ui/game/game_controller.dart';
import 'package:honest_chess/ui/game/game_screen.dart';
import 'package:honest_chess/ui/game/result_overlay.dart';
import 'package:honest_chess/ui/game/tool_row.dart';

import '../support/app_harness.dart';
import '../ui/game/fake_computer.dart';

/// The play screen over a game, with the feedback hub speaking into the
/// same recording announcer the board speaks into, as the app root wires
/// them.
class _Rig {
  _Rig(this.controller, this.announcer, this.computers);

  final GameController controller;
  final RecordingAnnouncer announcer;
  final FakeComputers computers;

  List<String> get spoken => announcer.spoken;
}

Future<_Rig> _pump(
  WidgetTester tester, {
  GameMode mode = const TwoPlayer(),
  String? fen,
  BoardOptions options = const BoardOptions(),
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final computers = FakeComputers();
  final controller = GameController(
    mode: mode,
    fen: fen,
    options: options,
    computer: computers.call,
  );
  final announcer = RecordingAnnouncer();
  final board = ValueNotifier(options);
  final foreground = ValueNotifier(true);
  final feedback = GameFeedback(
    events: controller.events,
    refusals: controller.refusals,
    board: board,
    foreground: foreground,
    player: FakeSoundPlayer(),
    haptics: FakeHaptics(),
    announcer: announcer,
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    feedback.dispose();
    controller.dispose();
    board.dispose();
    foreground.dispose();
  });
  await pumpUnderScope(
    tester,
    GameScreen(options: options, controller: controller),
    controller: controller,
    announcer: announcer,
  );
  return _Rig(controller, announcer, computers);
}

Finder _cell(String square) => find.byKey(Key('cell-$square'));

SemanticsNode _node(WidgetTester tester, String square) =>
    tester.getSemantics(_cell(square));

String _label(WidgetTester tester, String square) =>
    _node(tester, square).label;

/// A screen reader's double-tap on [square], then the move's slide.
Future<void> _doubleTap(WidgetTester tester, String square) async {
  tester.semantics.tap(find.semantics.byLabel(RegExp('^$square, ')));
  await tester.pump();
  await tester.pump(moveSlideDuration);
  await tester.pump(const Duration(milliseconds: 16));
}

String _fen(GameController c) => c.game.position.toFen();

const _vsWhite = VsComputer(
  playerColour: Colour.white,
  step: Strength.club,
  seed: 1,
);

void main() {
  group('square nodes', () {
    testWidgets('each square is one node: name, piece, colour and a tap', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester);
      expect(_label(tester, 'e2'), 'e2, white pawn');
      expect(_label(tester, 'e4'), 'e4, empty');
      expect(_label(tester, 'g8'), 'g8, black knight');
      for (final square in Square.values) {
        final node = _node(tester, square.name);
        expect(
          node.getSemanticsData().hasAction(SemanticsAction.tap),
          isTrue,
          reason: '${square.name} has no double-tap',
        );
        // The Draggable, the tap detector and the coordinates add no node
        // of their own inside the square.
        expect(
          node.childrenCount,
          0,
          reason: '${square.name} has nodes inside',
        );
      }
      expect(
        tester.getSemantics(_cell('e2')),
        isSemantics(onTapHint: 'select'),
      );
      handle.dispose();
    });

    testWidgets('the board is labelled, and read top rank first as seen', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final rig = await _pump(tester, mode: _vsWhite);
      final board = find.semantics.byLabel('Chess board, you play White');
      expect(board, findsOne);
      List<String> order() {
        final node = board.evaluate().single;
        return [
          for (final child in node.debugListChildrenInOrder(
            DebugSemanticsDumpOrder.traversalOrder,
          ))
            child.label.split(',').first,
        ];
      }

      expect(order().take(3), ['a8', 'b8', 'c8']);
      expect(order().last, 'h1');
      expect(rig.controller.game.mode, _vsWhite);
      handle.dispose();
    });

    testWidgets('a board turned round reads from h1', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        fen: 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1',
        options: const BoardOptions(rotateEachTurn: true),
      );
      final board = find.semantics.byLabel(
        'Chess board, two players, Black at the bottom',
      );
      expect(board, findsOne);
      final labels = [
        for (final child in board.evaluate().single.debugListChildrenInOrder(
          DebugSemanticsDumpOrder.traversalOrder,
        ))
          child.label.split(',').first,
      ];
      expect(labels.take(2), ['h1', 'g1']);
      expect(labels.last, 'a8');
      handle.dispose();
    });

    testWidgets('states are spoken whatever the visual switches say', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      const off = BoardOptions(
        legalMoveDots: false,
        lastMoveHighlight: false,
        flagCheck: false,
      );
      // White to move, in check from the bishop on b4.
      final rig = await _pump(
        tester,
        fen: 'rnbqk1nr/pppp1ppp/8/4p3/1b6/3P4/PPP1PPPP/RNBQKBNR w KQkq - 0 1',
        options: off,
      );
      await _doubleTap(tester, 'c2');
      expect(_label(tester, 'c2'), 'c2, white pawn, selected');
      expect(_label(tester, 'c3'), 'c3, empty, legal move');
      expect(
        tester.getSemantics(_cell('c3')),
        isSemantics(onTapHint: 'move here'),
      );
      expect(
        tester.getSemantics(_cell('c2')),
        isSemantics(onTapHint: 'put down'),
      );
      await _doubleTap(tester, 'c3');
      await _doubleTap(tester, 'b4');
      expect(_label(tester, 'b4'), 'b4, black bishop, selected');
      expect(_label(tester, 'c3'), 'c3, white pawn, capture, last move');
      expect(_label(tester, 'c2'), 'c2, empty, last move');
      await _doubleTap(tester, 'c3');
      expect(_label(tester, 'e1'), 'e1, white king, in check');
      // Nothing of it is drawn: the switches are off.
      expect(rig.controller.state.inCheck, isNull);
      expect(rig.controller.state.tints.toSet(), {SquareTint.none});
      handle.dispose();
    });

    testWidgets('en passant: the target reads capture, the pawn it passes '
        'can be captured', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, fen: '4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1');
      await _doubleTap(tester, 'e5');
      expect(_label(tester, 'd6'), 'd6, empty, capture');
      expect(
        _label(tester, 'd5'),
        'd5, black pawn, can be captured en passant',
      );
      handle.dispose();
    });
  });

  group('double-tap', () {
    testWidgets('selects, then moves, and the move is spoken', (tester) async {
      final handle = tester.ensureSemantics();
      final rig = await _pump(tester);
      await _doubleTap(tester, 'e2');
      expect(rig.controller.state.selection, Square.parse('e2'));
      expect(rig.spoken, ['White pawn selected']);
      await _doubleTap(tester, 'e4');
      expect(rig.controller.game.moves.single.toUci(), 'e2e4');
      expect(rig.spoken, ['White pawn selected', 'White pawn to e4']);
      handle.dispose();
    });

    testWidgets('on the selected piece puts it down', (tester) async {
      final handle = tester.ensureSemantics();
      final rig = await _pump(tester);
      await _doubleTap(tester, 'g1');
      await _doubleTap(tester, 'g1');
      expect(rig.controller.state.selection, isNull);
      expect(rig.spoken, ['White knight selected', 'put down']);
      handle.dispose();
    });

    testWidgets('on another own piece switches to it', (tester) async {
      final handle = tester.ensureSemantics();
      final rig = await _pump(tester);
      await _doubleTap(tester, 'g1');
      await _doubleTap(tester, 'b1');
      expect(rig.controller.state.selection, Square.parse('b1'));
      expect(rig.spoken, ['White knight selected', 'White knight selected']);
      handle.dispose();
    });

    testWidgets('an illegal target is announced and nothing moves', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final rig = await _pump(tester);
      final before = _fen(rig.controller);
      await _doubleTap(tester, 'g1');
      await _doubleTap(tester, 'g4');
      expect(_fen(rig.controller), before);
      expect(rig.controller.game.moves, isEmpty);
      // #72's rule: a tap that is not a target clears the selection.
      expect(rig.controller.state.selection, isNull);
      expect(rig.spoken, [
        'White knight selected',
        "Knight can't move there, put down",
      ]);
      handle.dispose();
    });

    testWidgets('a refusal with nothing selected says nothing', (tester) async {
      final handle = tester.ensureSemantics();
      final rig = await _pump(tester);
      await _doubleTap(tester, 'e4');
      await _doubleTap(tester, 'e7');
      expect(rig.spoken, isEmpty);
      expect(rig.controller.state.selection, isNull);
      handle.dispose();
    });

    testWidgets('a locked board says why and keeps the tap action', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final rig = await _pump(tester, mode: _vsWhite);
      await _doubleTap(tester, 'e2');
      await _doubleTap(tester, 'e4');
      rig.spoken.clear();
      final before = _fen(rig.controller);
      await _doubleTap(tester, 'e7');
      expect(rig.spoken, ['Club is thinking']);
      expect(_fen(rig.controller), before);
      expect(
        _node(tester, 'e7').getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
      );
      rig.computers.current.last.move('e7e5');
      await tester.pump(minThinkTime);
      await tester.pump();
      rig.controller.pause();
      await tester.pump();
      rig.spoken.clear();
      await _doubleTap(tester, 'd2');
      expect(rig.spoken, ['Paused']);
      expect(rig.controller.state.selection, isNull);
      handle.dispose();
    });

    testWidgets('the computer\'s move is announced once', (tester) async {
      final handle = tester.ensureSemantics();
      final rig = await _pump(tester, mode: _vsWhite);
      await _doubleTap(tester, 'e2');
      await _doubleTap(tester, 'e4');
      rig.computers.current.last.move('g8f6');
      await tester.pump(minThinkTime);
      await tester.pump();
      await tester.pump(moveSlideDuration);
      await tester.pump(const Duration(milliseconds: 16));
      expect(rig.spoken, [
        'White pawn selected',
        'White pawn to e4',
        'Black knight to f6',
      ]);
      expect(_label(tester, 'f6'), 'f6, black knight, last move');
      handle.dispose();
    });
  });

  group('the game\'s end', () {
    testWidgets('fool\'s mate: the mate, then the result, once', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final rig = await _pump(tester);
      for (final uci in ['f2f3', 'e7e5', 'g2g4', 'd8h4']) {
        await _doubleTap(tester, uci.substring(0, 2));
        await _doubleTap(tester, uci.substring(2));
      }
      expect(_label(tester, 'e1'), 'e1, white king, in check');
      await tester.pump(resultDelay);
      await tester.pump(resultRiseDuration + const Duration(milliseconds: 16));
      final moves = rig.spoken.where((s) => !s.endsWith('selected')).toList();
      expect(moves, [
        'White pawn to f3',
        'Black pawn to e5',
        'White pawn to g4',
        'Black queen to h4, checkmate',
        'Black wins. Black delivers checkmate.',
      ]);
      // The card is not a live region, so it is not read a second time.
      expect(
        tester.getSemantics(find.byKey(const Key('result-tag'))),
        isNot(isSemantics(isLiveRegion: true)),
      );
      // Re-showing the card from the bar is silent too.
      rig.controller.viewBoard();
      await tester.pump();
      rig.controller.showResult();
      await tester.pump();
      await tester.pump(resultRiseDuration + const Duration(milliseconds: 16));
      expect(rig.spoken.last, 'Black wins. Black delivers checkmate.');
      expect(rig.spoken.where((s) => s.endsWith('checkmate.')), hasLength(1));
      // A finished board still takes the double-tap, and says so.
      rig.spoken.clear();
      rig.controller.viewBoard();
      await tester.pump();
      await _doubleTap(tester, 'a2');
      expect(rig.spoken, ['Game over']);
      handle.dispose();
    });
  });

  group('labelled controls', () {
    testWidgets('the pause pill, the tools and the clocks', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester);
      expect(
        tester.getSemantics(find.byKey(const Key('pause-pill'))),
        isSemantics(label: pausePillLabel, isButton: true),
      );
      for (final tool in Tool.values) {
        expect(
          tester.getSemantics(find.byKey(tool.key)).label,
          contains(tool.semantics),
          reason: '${tool.name} is not labelled',
        );
      }
      for (final side in Colour.values) {
        expect(
          tester
              .getSemantics(find.byKey(Key('clock-semantics-${side.name}')))
              .label,
          isNotEmpty,
          reason: '${side.name} clock is not labelled',
        );
      }
      handle.dispose();
    });

    testWidgets('the promotion card\'s choices', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, fen: '4k3/P7/8/8/8/8/8/4K3 w - - 0 1');
      await _doubleTap(tester, 'a7');
      await _doubleTap(tester, 'a8');
      await tester.pump(promotionEnterDuration);
      for (final kind in promotionChoices) {
        expect(
          find.semantics.byLabel('Promote to ${kind.name}'),
          findsOne,
          reason: '${kind.name} choice is not labelled',
        );
      }
      handle.dispose();
    });
  });
}
