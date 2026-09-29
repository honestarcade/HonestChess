// The play screen's controller over real engine positions (#72): selection,
// moves by tap and drop, the highlights each option filters, and every
// refusal a silent false.
import 'package:flutter_test/flutter_test.dart';

import 'package:honest_chess/engine/engine.dart';
import 'package:honest_chess/ui/board/board_options.dart';
import 'package:honest_chess/ui/game/game_controller.dart';

import '../../fixtures/fens.dart';
import 'fake_computer.dart';

Square sq(String name) => Square.parse(name);

/// Every square carrying [mark], by name.
Set<String> marked(GameViewState state, SquareMark mark) => {
  for (final s in Square.values)
    if (state.markAt(s) == mark) s.name,
};

/// Every square carrying [tint], by name.
Set<String> tinted(GameViewState state, SquareTint tint) => {
  for (final s in Square.values)
    if (state.tintAt(s) == tint) s.name,
};

void main() {
  group('selection', () {
    test('tap picks up, tap again puts down, another piece switches', () {
      final c = GameController();
      expect(c.tapSquare(sq('e2')), isTrue);
      expect(c.state.selection, sq('e2'), reason: 'select: e2 picked up');
      expect(c.tapSquare(sq('g1')), isTrue);
      expect(c.state.selection, sq('g1'), reason: 'select: switched to g1');
      expect(c.tapSquare(sq('g1')), isTrue);
      expect(c.state.selection, isNull, reason: 'select: g1 put down');
      expect(c.game.moves, isEmpty, reason: 'select: no move was played');
    });

    test('a non-target or an opponent piece clears and moves nothing', () {
      for (final target in ['e5', 'e7', 'd2']) {
        final c = GameController()..tapSquare(sq('e2'));
        final before = c.state.position.toFen();
        c.tapSquare(sq(target));
        // d2 is White's own piece: the tap switches rather than clears.
        final expected = target == 'd2' ? sq('d2') : null;
        expect(
          c.state.selection,
          expected,
          reason: 'select: a tap on $target after e2 leaves $expected selected',
        );
        expect(
          c.state.position.toFen(),
          before,
          reason: 'select: a tap on $target moves nothing',
        );
      }
    });

    test('with nothing selected, empty and opponent squares do nothing', () {
      final c = GameController();
      var notified = 0;
      c.addListener(() => notified++);
      expect(c.tapSquare(sq('e4')), isFalse);
      expect(c.tapSquare(sq('e7')), isFalse);
      expect(c.state.selection, isNull);
      expect(notified, 0, reason: 'select: a refused tap notifies nobody');
    });

    test('the king onto its own rook switches to the rook', () {
      final c = GameController(fen: 'r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1');
      c.tapSquare(sq('e1'));
      c.tapSquare(sq('h1'));
      expect(c.state.selection, sq('h1'), reason: 'castle: rook selected');
      expect(
        c.game.moves,
        isEmpty,
        reason: 'castle: king-takes-rook is no move',
      );
    });
  });

  group('moves', () {
    test('a tap on a target plays it, and the selection clears', () {
      final c = GameController()..tapSquare(sq('e2'));
      expect(c.tapSquare(sq('e4')), isTrue);
      expect(c.game.moves.single.toUci(), 'e2e4');
      expect(c.state.selection, isNull, reason: 'move: selection clears');
      expect(c.state.lastMove!.toUci(), 'e2e4');
    });

    test('castling: the king taps two squares along, both ways', () {
      for (final (to, rook, rookTo) in [
        ('g1', 'h1', 'f1'),
        ('c1', 'a1', 'd1'),
      ]) {
        final c = GameController(fen: 'r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1');
        c.tapSquare(sq('e1'));
        expect(c.state.markAt(sq(to)), SquareMark.dot);
        c.tapSquare(sq(to));
        final p = c.state.position;
        expect(p.pieceAt(sq(to)), Piece.whiteKing, reason: 'castle: king $to');
        expect(p.pieceAt(sq(rookTo)), Piece.whiteRook, reason: 'castle: rook');
        expect(p.pieceAt(sq(rook)), isNull, reason: 'castle: $rook emptied');
        expect(c.game.moves.single.isCastling, isTrue);
      }
    });

    test('a promotion opens pending and plays nothing yet', () {
      final c = GameController(fen: '8/P7/8/8/8/8/7p/K6k w - - 0 60');
      c.tapSquare(sq('a7'));
      expect(c.tapSquare(sq('a8')), isTrue);
      expect(c.state.pendingPromotion, (from: sq('a7'), to: sq('a8')));
      expect(c.game.moves, isEmpty, reason: 'promote: waits for a piece');
      expect(c.state.selection, sq('a7'), reason: 'promote: pawn stays lit');
      expect(c.inputLocked, isTrue, reason: 'promote: the board waits');
      expect(c.tapSquare(sq('a1')), isFalse);
      expect(c.state.position.pieceAt(sq('a7')), Piece.whitePawn);
    });

    test('an illegal move is a silent false, never an exception', () {
      final c = GameController();
      expect(c.move(sq('e2'), sq('e5')), isFalse);
      expect(c.move(sq('e7'), sq('e5')), isFalse, reason: 'move: not White');
      expect(c.move(sq('e3'), sq('e4')), isFalse, reason: 'move: empty from');
      expect(c.game.moves, isEmpty);
    });
  });

  group('drops', () {
    test('a drop on a target plays it; on its own square keeps it', () {
      final c = GameController();
      expect(c.pickUp(sq('g1')), isTrue);
      expect(c.drop(sq('g1'), sq('g1')), isFalse);
      expect(c.state.selection, sq('g1'), reason: 'drop: origin keeps it');
      expect(c.drop(sq('g1'), sq('f3')), isTrue);
      expect(c.game.moves.single.toUci(), 'g1f3');
    });

    test('an illegal drop or one off the board clears and moves nothing', () {
      for (final to in [sq('g4'), sq('g2'), null]) {
        final c = GameController()..pickUp(sq('g1'));
        expect(c.canDrop(sq('g1'), to ?? sq('a5')), isFalse);
        expect(c.drop(sq('g1'), to), isFalse);
        expect(c.state.selection, isNull, reason: 'drop: $to clears');
        expect(c.game.moves, isEmpty, reason: 'drop: $to moves nothing');
      }
    });

    test('a drag that outlived a position change cannot drop', () {
      final c = GameController()..pickUp(sq('g1'));
      c.move(sq('g1'), sq('f3'));
      c.move(sq('e7'), sq('e5'));
      expect(c.state.selection, isNull, reason: 'drop: a move clears it');
      expect(c.canDrop(sq('g1'), sq('f3')), isFalse);
      expect(c.drop(sq('b1'), sq('c3')), isFalse, reason: 'drop: b1 not held');
      expect(c.game.moves, hasLength(2));
    });
  });

  group('dots and rings', () {
    test('match legalMoves exactly for every piece in every fixture', () {
      for (final fen in allFens) {
        final c = GameController(fen: fen);
        if (c.state.over) continue;
        final legal = legalMoves(c.state.position);
        final side = c.state.position.sideToMove;
        for (final from in Square.values) {
          if (c.state.position.pieceAt(from)?.colour != side) continue;
          c.pickUp(from);
          final moves = legal.where((m) => m.from == from);
          expect(marked(c.state, SquareMark.dot), {
            for (final m in moves.where((m) => !m.isCapture)) m.to.name,
          }, reason: 'dots: exactly the quiet targets of $from in $fen');
          expect(marked(c.state, SquareMark.ring), {
            for (final m in moves.where((m) => m.isCapture)) m.to.name,
          }, reason: 'rings: exactly the capture targets of $from in $fen');
        }
      }
    });

    test('en passant rings the square the pawn lands on', () {
      final c = GameController(
        fen: 'rnbqkbnr/ppp1p1pp/8/3pPp2/8/8/PPPP1PPP/RNBQKBNR w KQkq f6 0 3',
      )..tapSquare(sq('e5'));
      expect(marked(c.state, SquareMark.ring), {'f6'});
      expect(marked(c.state, SquareMark.dot), {'e6'});
      expect(c.state.markAt(sq('f5')), SquareMark.none, reason: 'ep: not f5');
    });

    test('with dots off none show, and the moves still work', () {
      final c = GameController(
        options: const BoardOptions(legalMoveDots: false),
        fen: 'r1bqkb1r/pppp1ppp/2n2n2/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR w KQkq - 4 4',
      )..tapSquare(sq('h5'));
      expect(c.state.marks.toSet(), {SquareMark.none});
      expect(c.state.selection, sq('h5'), reason: 'dots off: still selects');
      expect(c.tapSquare(sq('f7')), isTrue, reason: 'dots off: capture works');
      expect(c.game.status, isA<Win>());
    });

    test('no marks without a selection', () {
      final c = GameController()
        ..tapSquare(sq('e2'))
        ..tapSquare(sq('e2'));
      expect(c.state.marks.toSet(), {SquareMark.none});
    });
  });

  group('tints', () {
    test('the last move tints its two squares, following its option', () {
      final c = GameController()
        ..tapSquare(sq('e2'))
        ..tapSquare(sq('e4'));
      expect(tinted(c.state, SquareTint.lastMove), {'e2', 'e4'});
      c.options = const BoardOptions(lastMoveHighlight: false);
      expect(tinted(c.state, SquareTint.lastMove), isEmpty);
      expect(c.state.lastMove!.toUci(), 'e2e4', reason: 'tint: still known');
    });

    test('a game from a FEN shows no last move until the first', () {
      final c = GameController(fen: extraFens.first);
      expect(c.state.lastMove, isNull);
      expect(c.state.tints.toSet(), {SquareTint.none});
    });

    test('the king in check is reddened, following its option', () {
      const fen = '4k3/8/8/8/8/8/4r3/4K3 w - - 0 1';
      final on = GameController(fen: fen);
      expect(tinted(on.state, SquareTint.check), {'e1'});
      final off = GameController(
        fen: fen,
        options: const BoardOptions(flagCheck: false),
      );
      expect(off.state.tints.toSet(), {SquareTint.none});
    });

    test('the check flag stays on the mated king', () {
      final c = GameController(
        fen: 'rnbqkbnr/pppp1ppp/8/4p3/6P1/5P2/PPPPP2P/RNBQKBNR b KQkq - 0 2',
      );
      c
        ..tapSquare(sq('d8'))
        ..tapSquare(sq('h4'));
      expect(c.state.over, isTrue, reason: 'mate: fool\'s mate ends it');
      expect(tinted(c.state, SquareTint.check), {'e1'});
      expect(tinted(c.state, SquareTint.lastMove), {'d8', 'h4'});
    });

    test('the selection outranks the check and the last move', () {
      final c = GameController(fen: '4k3/8/8/8/8/8/4r3/4K3 w - - 0 1')
        ..tapSquare(sq('e1'));
      expect(tinted(c.state, SquareTint.selected), {'e1'});
      expect(tinted(c.state, SquareTint.check), isEmpty);
    });
  });

  group('locked input', () {
    const vsComputer = VsComputer(
      playerColour: Colour.white,
      step: Strength.club,
      seed: 1,
    );

    test('on the computer\'s turn taps, drags and moves do nothing', () {
      final c = GameController(
        mode: vsComputer,
        fen: extraFens.first, // Black to move
      );
      var notified = 0;
      c.addListener(() => notified++);
      expect(c.inputLocked, isTrue);
      expect(c.tapSquare(sq('e7')), isFalse);
      expect(c.pickUp(sq('e7')), isFalse);
      expect(c.canDrag(sq('e7')), isFalse);
      expect(c.drop(sq('e7'), sq('e5')), isFalse);
      expect(c.move(sq('e7'), sq('e5')), isFalse);
      expect(c.state.selection, isNull);
      expect(c.game.moves, isEmpty);
      expect(notified, 0, reason: 'locked: nothing changed');
    });

    test('on the player\'s turn against the computer, input is open', () {
      final c = GameController(mode: vsComputer);
      expect(c.inputLocked, isFalse);
      expect(c.tapSquare(sq('e2')), isTrue);
      expect(c.tapSquare(sq('e4')), isTrue);
      expect(c.inputLocked, isTrue, reason: 'locked: now the computer moves');
    });

    test('a game that is over takes no input', () {
      final mated = GameController(
        fen: 'rnb1kbnr/pppp1ppp/8/4p3/6Pq/5P2/PPPPP2P/RNBQKBNR w KQkq - 1 3',
      );
      expect(mated.state.over, isTrue);
      expect(mated.inputLocked, isTrue);
      expect(mated.tapSquare(sq('a2')), isFalse);
      expect(mated.state.selection, isNull);
    });
  });

  group('promotion (#73)', () {
    const fen = '7k/4P3/8/8/8/8/8/K7 w - - 0 1';

    GameController pending({BoardOptions options = const BoardOptions()}) {
      final c = GameController(fen: fen, options: options);
      c.tapSquare(sq('e7'));
      c.tapSquare(sq('e8'));
      return c;
    }

    test('choosePromotion plays the chosen piece', () {
      for (final kind in [
        PieceKind.queen,
        PieceKind.rook,
        PieceKind.bishop,
        PieceKind.knight,
      ]) {
        final c = pending();
        expect(c.choosePromotion(kind), isTrue);
        expect(c.game.moves.single.promotion, kind);
        expect(c.state.pendingPromotion, isNull);
        expect(c.state.selection, isNull, reason: 'promote: tint cleared');
      }
    });

    test('a king or a pawn is refused and the choice stays open', () {
      final c = pending();
      expect(c.choosePromotion(PieceKind.king), isFalse);
      expect(c.choosePromotion(PieceKind.pawn), isFalse);
      expect(c.state.pendingPromotion, (from: sq('e7'), to: sq('e8')));
      expect(c.game.moves, isEmpty);
    });

    test('cancel puts the pawn down: same position, same side to move', () {
      final c = pending();
      var notified = 0;
      c.addListener(() => notified++);
      expect(c.cancelPromotion(), isTrue);
      expect(notified, 1);
      expect(c.state.pendingPromotion, isNull);
      expect(c.state.selection, isNull, reason: 'cancel: pawn deselected');
      expect(c.state.tintAt(sq('e7')), SquareTint.none);
      expect(c.state.position.toFen(), fen, reason: 'cancel: unchanged');
      expect(c.game.moves, isEmpty, reason: 'cancel: nothing played');
      expect(c.inputLocked, isFalse, reason: 'cancel: still White to move');
    });

    test('with nothing pending both are silent no-ops', () {
      final c = GameController(fen: fen);
      var notified = 0;
      c.addListener(() => notified++);
      expect(c.choosePromotion(PieceKind.queen), isFalse);
      expect(c.cancelPromotion(), isFalse);
      expect(notified, 0, reason: 'promote: a refusal changes nothing');
      expect(c.game.moves, isEmpty);
    });

    test('while it is open the origin keeps its tint; nothing else moves', () {
      final c = pending();
      expect(c.state.tintAt(sq('e7')), SquareTint.selected);
      expect(c.tapSquare(sq('a1')), isFalse);
      expect(c.pickUp(sq('a1')), isFalse);
      expect(c.canDrag(sq('e7')), isFalse);
      expect(c.move(sq('a1'), sq('a2')), isFalse);
      expect(c.drop(sq('e7'), sq('e8')), isFalse);
      expect(c.state.pendingPromotion, (from: sq('e7'), to: sq('e8')));
      expect(c.game.moves, isEmpty);
    });

    test('auto-queen plays the queen at once, read at each move', () {
      final c = pending(options: const BoardOptions(autoQueen: true));
      expect(c.state.pendingPromotion, isNull, reason: 'auto-queen: no ask');
      expect(c.game.moves.single.toUci(), 'e7e8q');

      final later = GameController(fen: fen);
      later.options = const BoardOptions(autoQueen: true);
      later.tapSquare(sq('e7'));
      later.tapSquare(sq('e8'));
      expect(later.game.moves.single.toUci(), 'e7e8q');
    });

    test("the mover's clock keeps running while the choice is open", () {
      var now = 0;
      final c = GameController(
        fen: '7k/8/8/8/8/8/4p3/K7 w - - 0 1',
        timeControl: Timed(5, 0),
        now: () => now,
      );
      expect(c.move(sq('a1'), sq('a2')), isTrue);
      now = 1000;
      expect(c.move(sq('e2'), sq('e1')), isTrue);
      expect(c.state.pendingPromotion, isNotNull);
      now = 4000;
      expect(
        c.game.remaining(Colour.black),
        300000 - 4000,
        reason: "promote: Black's clock runs while the card is open",
      );
      expect(c.game.clock.phase, ClockPhase.running);
      now = 6000;
      expect(c.choosePromotion(PieceKind.rook), isTrue);
      expect(
        c.game.remaining(Colour.black),
        300000 - 6000,
        reason: 'promote: the time spent choosing was charged to Black',
      );
    });

    test('a pick after the flag fell is refused and the game is over', () {
      var now = 0;
      final c = GameController(
        fen: '7k/8/8/8/8/8/4p3/K7 w - - 0 1',
        timeControl: Timed(1, 0),
        now: () => now,
      );
      c.move(sq('a1'), sq('a2'));
      c.move(sq('e2'), sq('e1'));
      now = 61000;
      expect(c.choosePromotion(PieceKind.queen), isFalse);
      expect(c.game.moves.length, 1, reason: 'flag: the pick was dropped');
      expect(c.state.pendingPromotion, isNull, reason: 'flag: card closes');
      expect(c.state.over, isTrue);
      // White has a lone king: Black's flag is a draw, not a loss.
      expect(c.game.status, const Draw(GameEndReason.flagNoMatingMaterial));
    });
  });

  group('leaving for the menu (#92)', () {
    testWidgets('leave() stops the computer; resuming builds a new one with '
        'the same step and seed, which is asked for its move', (tester) async {
      final fakes = FakeComputers();
      final c = GameController(
        mode: const VsComputer(
          playerColour: Colour.white,
          step: Strength.club,
          seed: 7,
        ),
        timeControl: const Untimed(),
        computer: fakes.call,
      );
      expect(c.move(sq('e2'), sq('e4')), isTrue);
      await tester.pump();
      expect(fakes.current.requests, hasLength(1));
      expect(c.pause(), isTrue);
      c.leave();
      expect(fakes.built.single.disposed, isTrue, reason: 'leave: kept');
      expect(c.state.paused, isTrue, reason: 'leave: the pause ended');
      expect(c.resume(), isTrue);
      await tester.pump();
      expect(fakes.built, hasLength(2), reason: 'resume: no new computer');
      expect((fakes.current.strength, fakes.current.seed), (Strength.club, 7));
      expect(fakes.current.requests, hasLength(1), reason: 'resume: not asked');
      c.dispose();
    });
  });
}
