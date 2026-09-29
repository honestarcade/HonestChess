// A scripted stand-in for #68's ComputerPlayer (#75): every request is a
// completer the test resolves, so a late answer after a cancel can be
// written down.
import 'dart:async';

import 'package:honest_chess/engine/engine.dart';
import 'package:honest_chess/ui/game/computer_turns.dart';

/// One chooseMove call: the game it was asked about and its answer.
class FakeRequest {
  FakeRequest(this.game);

  final Game game;
  final completer = Completer<MoveResult>();

  int get ply => game.history.length - 1;

  /// Answers with [uci] (default: the first legal move) for this request's
  /// position.
  void move([String? uci]) {
    final move = uci == null
        ? legalMoves(game.position).first
        : Move.fromUci(game.position, uci);
    completer.complete(Moved(move, ply: ply, depth: 1, nodes: 1));
  }

  void cancelled() => completer.complete(const MoveCancelled());

  void fail() => completer.completeError(const ComputerError('fake'));
}

/// The fake computer. With [instant] set, each request is answered at once
/// with the first legal move; otherwise the test answers [requests].
class FakeComputer implements ComputerOpponent {
  FakeComputer(this.strength, this.seed, {this.instant = false});

  final Strength strength;
  final int seed;
  final bool instant;

  final requests = <FakeRequest>[];
  var cancels = 0;
  var disposed = false;

  FakeRequest get last => requests.last;

  @override
  Future<MoveResult> chooseMove(Game game) {
    final request = FakeRequest(game);
    requests.add(request);
    if (instant) request.move();
    return request.completer.future;
  }

  @override
  Future<bool> acceptsDraw(Game game) async => false;

  @override
  Future<void> cancel() async {
    cancels++;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

/// A factory that keeps every computer it builds, newest last.
class FakeComputers {
  FakeComputers({this.instant = false});

  final bool instant;
  final built = <FakeComputer>[];

  FakeComputer get current => built.last;

  ComputerOpponent call(Strength strength, int seed) {
    final computer = FakeComputer(strength, seed, instant: instant);
    built.add(computer);
    return computer;
  }
}
