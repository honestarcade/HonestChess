import 'dart:math';

/// A [Random] whose [nextBool] answers come from a queue the test fills;
/// anything else it is asked, or an empty queue, fails the test.
class ScriptedRandom implements Random {
  ScriptedRandom([Iterable<bool> bools = const []]) {
    this.bools.addAll(bools);
  }

  final bools = <bool>[];

  /// How many answers have been taken.
  var taken = 0;

  @override
  bool nextBool() {
    if (bools.isEmpty) {
      throw StateError('ScriptedRandom: no nextBool answer queued');
    }
    taken++;
    return bools.removeAt(0);
  }

  @override
  double nextDouble() => throw UnsupportedError('ScriptedRandom.nextDouble');

  @override
  int nextInt(int max) => throw UnsupportedError('ScriptedRandom.nextInt');
}
