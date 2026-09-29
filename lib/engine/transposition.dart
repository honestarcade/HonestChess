/// The search's transposition table: positions already searched, by
/// Zobrist key, so a position reached by another move order is not searched
/// again.
library;

import 'dart:typed_data';

/// The kind of score an entry holds.
abstract final class Bound {
  /// The true score is at most the stored one (every move failed low).
  static const int upper = 1;

  /// The true score is at least the stored one (a move failed high).
  static const int lower = 2;

  /// The stored score is exact.
  static const int exact = 3;
}

/// Scores at or beyond this magnitude are mates, stored relative to the node
/// rather than the root so they stay right wherever the position recurs.
const int mateThreshold = 32000 - 256;

/// A fixed-size table of two-slot buckets in one [Int64List].
///
/// Each slot is two ints: the full 64-bit key, then the packed entry — bits
/// 0–14 the best move's identity (`Move.packed & 0x7fff`, 0 for none),
/// 15–16 the [Bound], 17–24 the depth, 25–32 the search generation, 33–48
/// the score + 32768. The first slot of a bucket prefers depth: it keeps a
/// deeper entry from this search. The second always takes what the first
/// refused. Comparing the full key means an index collision is never read
/// as a hit; only a 64-bit key collision could be.
///
/// Its contents depend on what was searched before, so two searches of the
/// same position agree only when both start from an empty table.
final class TranspositionTable {
  /// A table of about [megabytes] MB (rounded down to a power-of-two bucket
  /// count, at least one bucket).
  TranspositionTable({int megabytes = 16})
    : this._(_bucketsFor(megabytes * 1024 * 1024));

  TranspositionTable._(int buckets)
    : _slots = Int64List(buckets * 4),
      _mask = buckets - 1;

  static int _bucketsFor(int bytes) {
    var buckets = 1;
    while (buckets * 2 * 32 <= bytes) {
      buckets *= 2;
    }
    return buckets;
  }

  final Int64List _slots;
  final int _mask;
  int _generation = 0;

  /// Starts a new search: entries from earlier searches become the first to
  /// be replaced.
  void newSearch() => _generation = (_generation + 1) & 255;

  /// Empties the table.
  void clear() {
    _slots.fillRange(0, _slots.length, 0);
    _generation = 0;
  }

  /// The packed entry for [key], or 0 when there is none.
  int probe(int key) {
    final i = (key & _mask) * 4;
    if (_slots[i] == key && _slots[i + 1] != 0) return _slots[i + 1];
    if (_slots[i + 2] == key && _slots[i + 3] != 0) return _slots[i + 3];
    return 0;
  }

  /// Stores a result for [key]. [score] is from the node's point of view
  /// with mates counted from the root; [ply] converts them.
  void store(int key, int move, int score, int depth, int bound, int ply) {
    if (score >= mateThreshold) {
      score += ply;
    } else if (score <= -mateThreshold) {
      score -= ply;
    }
    final entry =
        (move & 0x7fff) |
        bound << 15 |
        (depth.clamp(0, 255)) << 17 |
        _generation << 25 |
        (score + 32768) << 33;
    final i = (key & _mask) * 4;
    final kept = _slots[i + 1];
    if (_slots[i] == key ||
        kept == 0 ||
        entryGeneration(kept) != _generation ||
        depth >= entryDepth(kept)) {
      _slots[i] = key;
      _slots[i + 1] = entry;
    } else {
      _slots[i + 2] = key;
      _slots[i + 3] = entry;
    }
  }

  /// The move identity in [entry], 0 for none.
  static int entryMove(int entry) => entry & 0x7fff;

  static int entryBound(int entry) => (entry >> 15) & 3;

  static int entryDepth(int entry) => (entry >> 17) & 255;

  static int entryGeneration(int entry) => (entry >> 25) & 255;

  /// The score in [entry], with mates counted from the root again.
  static int entryScore(int entry, int ply) {
    final score = ((entry >> 33) & 0xffff) - 32768;
    if (score >= mateThreshold) return score - ply;
    if (score <= -mateThreshold) return score + ply;
    return score;
  }
}
