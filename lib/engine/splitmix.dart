/// SplitMix64, the engine's one pseudo-random generator: it makes the
/// committed Zobrist keys (`tools/gen_zobrist.dart`) and the strength dial's
/// seeded noise. It is written out here rather than taken from `dart:math`
/// so its output never depends on the SDK version.
library;

/// The golden-ratio increment SplitMix64 adds to its state for each output.
const int splitMixIncrement = 0x9e3779b97f4a7c15;

/// SplitMix64's output function: a bijective mix of all 64 bits of [z].
int splitMixFinalise(int z) {
  z = (z ^ (z >>> 30)) * 0xbf58476d1ce4e5b9;
  z = (z ^ (z >>> 27)) * 0x94d049bb133111eb;
  return z ^ (z >>> 31);
}

/// A SplitMix64 stream from [seed]: the same seed always gives the same
/// outputs, on every device.
final class SplitMix64 {
  SplitMix64(int seed) : _state = seed;

  int _state;

  /// The next 64-bit output.
  int next() {
    _state += splitMixIncrement;
    return splitMixFinalise(_state);
  }

  /// A uniform integer in `[0, bound)`, `1 <= bound <= 2^32`, with no modulo
  /// bias: 32-bit draws that would bias the result are rejected and drawn
  /// again.
  int nextBelow(int bound) {
    if (bound < 1 || bound > 1 << 32) {
      throw RangeError.range(bound, 1, 1 << 32, 'bound');
    }
    final limit = (1 << 32) - (1 << 32) % bound;
    while (true) {
      final draw = next() >>> 32;
      if (draw < limit) return draw % bound;
    }
  }
}
