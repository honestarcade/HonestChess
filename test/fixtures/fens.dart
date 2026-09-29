// FEN fixtures shared by the engine tests.

/// The six Chess Programming Wiki perft positions (and position 4's mirror),
/// exactly as https://www.chessprogramming.org/Perft_Results gives them
/// (read 2026-09-28), except that position 2 ("Kiwipete"), which the page
/// writes without move counters, has " 0 1" appended so it is a full FEN.
const cpwPerftFens = {
  'initial': 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
  'kiwipete':
      'r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1',
  'position3': '8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1',
  'position4':
      'r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1',
  'position4-mirrored':
      'r2q1rk1/pP1p2pp/Q4n2/bbp1p3/Np6/1B3NBn/pPPP1PPP/R3K2R b KQ - 0 1',
  'position5': 'rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8',
  'position6': 'r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0 10',
};

/// Further legal positions, written for these tests: en-passant targets for
/// both sides, each castling right alone, a side to move in check, promoted
/// pieces, pawns about to promote and the largest counters allowed.
const extraFens = [
  'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1',
  'rnbqkbnr/pp1ppppp/8/2p5/4P3/8/PPPP1PPP/RNBQKBNR w KQkq c6 0 2',
  'rnbqkbnr/pp1ppppp/8/2p5/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 1 2',
  'rnbqkbnr/ppp1pppp/8/8/3pP3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 3',
  'rnbqkbnr/ppp1p1pp/8/3pPp2/8/8/PPPP1PPP/RNBQKBNR w KQkq f6 0 3',
  'rnb1kbnr/pppp1ppp/8/4p3/6Pq/5P2/PPPPP2P/RNBQKBNR w KQkq - 1 3',
  'r1bqkb1r/pppp1ppp/2n2n2/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR w KQkq - 4 4',
  '8/8/8/4k3/8/8/8/4K3 w - - 0 1',
  '4k3/8/8/8/8/8/8/4K2R w K - 0 1',
  '4k3/8/8/8/8/8/8/R3K3 w Q - 0 1',
  'r3k3/8/8/8/8/8/8/4K3 b q - 0 1',
  '4k2r/8/8/8/8/8/8/4K3 b k - 0 1',
  'r3k2r/8/8/8/8/8/8/R3K2R b KQkq - 0 1',
  '4k3/8/8/8/8/8/4r3/4K3 w - - 0 1',
  '8/P7/8/8/8/8/7p/K6k w - - 0 60',
  '8/8/4k3/8/8/4K3/8/8 b - - 100000 100000',
  '3qk3/8/8/8/8/8/8/3QK3 w - - 0 1',
  '4k3/8/8/8/8/8/8/QQQQKQQQ w - - 0 1',
  '8/8/8/8/8/8/6k1/4K2R w K - 0 1',
  'n1n5/PPPk4/8/8/8/8/4Kppp/5N1N b - - 0 1',
  '8/Pk6/8/8/8/8/6Kp/8 w - - 0 1',
];

/// Every valid fixture FEN.
final allFens = [...cpwPerftFens.values, ...extraFens];
