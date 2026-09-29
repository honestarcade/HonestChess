// The openings the strength ladder (test/engine/strength_ladder_test.dart)
// and the Stockfish benchmark (tools/benchmark/uci_match.dart) start their
// games from, so neither measures one opening's quirks.

/// Twenty balanced four-ply lines from common openings, hand-picked (#69),
/// in UCI notation from the initial position. Every game is played from
/// each line once with each colour.
const ladderOpenings = [
  ['e2e4', 'e7e5', 'g1f3', 'b8c6'], // King's Knight
  ['e2e4', 'e7e5', 'g1f3', 'g8f6'], // Petrov
  ['e2e4', 'e7e5', 'f1c4', 'g8f6'], // Bishop's Opening
  ['e2e4', 'c7c5', 'g1f3', 'd7d6'], // Sicilian
  ['e2e4', 'c7c5', 'b1c3', 'b8c6'], // Closed Sicilian
  ['e2e4', 'e7e6', 'd2d4', 'd7d5'], // French
  ['e2e4', 'c7c6', 'd2d4', 'd7d5'], // Caro-Kann
  ['e2e4', 'd7d6', 'd2d4', 'g8f6'], // Pirc
  ['e2e4', 'g7g6', 'd2d4', 'f8g7'], // Modern
  ['e2e4', 'd7d5', 'e4d5', 'd8d5'], // Scandinavian
  ['d2d4', 'd7d5', 'c2c4', 'e7e6'], // Queen's Gambit Declined
  ['d2d4', 'd7d5', 'c2c4', 'c7c6'], // Slav
  ['d2d4', 'd7d5', 'g1f3', 'g8f6'], // Queen's Pawn
  ['d2d4', 'g8f6', 'c2c4', 'e7e6'], // Nimzo/Queen's Indian complex
  ['d2d4', 'g8f6', 'c2c4', 'g7g6'], // King's Indian / Grünfeld
  ['d2d4', 'g8f6', 'g1f3', 'e7e6'], // Indian, quiet
  ['d2d4', 'f7f5', 'g2g3', 'g8f6'], // Dutch
  ['c2c4', 'e7e5', 'b1c3', 'g8f6'], // English, reversed Sicilian
  ['c2c4', 'c7c5', 'g1f3', 'b8c6'], // Symmetrical English
  ['g1f3', 'd7d5', 'g2g3', 'g8f6'], // Réti
];
