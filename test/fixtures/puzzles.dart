// Search fixtures from the Lichess puzzle database, which Lichess
// publishes under CC0 at https://database.lichess.org/#puzzles (file
// lichess_db_puzzle.csv.zst, read 2026-09-28). Each puzzle is
// https://lichess.org/training/<id>.
//
// A database row gives the position before the opponent's last move and
// then the moves; `fen` here is the position after that first move, and
// `move` is the solution's first move — the one the search must find.
//
// Selection, in database order: rating at most 1500;
// for the mates, the puzzles tagged mateIn1 / mateIn2; for the tactics,
// puzzles tagged `short` and fork, pin or skewer (and not a mate). The
// first matches were taken in that order, less the ones .n8/decisions.md
// lists under #66 (2026-09-28) with the reason each was dropped.

typedef Puzzle = ({String id, String fen, String move});
typedef TacticPuzzle = ({String id, String theme, String fen, String move});

/// Mate in one: the listed move is the only mate.
const List<Puzzle> mateInOne = [
  (
    id: '000rZ',
    fen: '2kr1b1r/p1p2pp1/2pqN3/7p/6n1/2NPB3/PPP2PPP/R2Q1RK1 b - - 0 13',
    move: 'd6h2',
  ),
  (
    id: '001gi',
    fen: 'N6r/1p1k1ppp/2np4/b3p3/4P1b1/N1Q5/P4PPP/R3KB1R b KQ - 0 18',
    move: 'a5c3',
  ),
  (
    id: '001pC',
    fen: 'r4rk1/pp3ppp/3b4/2p1pPB1/7N/2PP3n/PP4PP/R2Q2RK b - - 0 18',
    move: 'h3f2',
  ),
  (
    id: '001wb',
    fen: 'r3k2r/pb1p1ppp/1b4q1/1Q2P3/8/2NP1PP1/PP4P1/R1B2R1K b kq - 0 17',
    move: 'g6h5',
  ),
  (
    id: '002CP',
    fen: 'r5k1/pp4pp/4p1q1/4p3/3n4/P3Q1P1/1PP4P/2KR1R2 b - - 5 24',
    move: 'g6c2',
  ),
  (
    id: '002HE',
    fen: '1qr2rk1/1p1p1ppp/pB2p1n1/7n/2P1P3/1Q2NP1P/PP2BKPb/3R1R2 b - - 2 20',
    move: 'b8g3',
  ),
  (
    id: '002Q2',
    fen: '7k/p4R1p/3p3B/2pN1n2/2PbB1b1/3P2P1/P3r3/5R1K b - - 0 28',
    move: 'f5g3',
  ),
];

/// Mate in two: the listed move starts the mate.
const List<Puzzle> mateInTwo = [
  (
    id: '000Zo',
    fen: '4r3/1k6/pp3P2/1b5p/3R1p2/P1R2P2/1P4PP/6K1 b - - 0 35',
    move: 'e8e1',
  ),
  (
    id: '000hf',
    fen: 'r1bq3r/pp1nbkp1/2p1p2p/8/2BP4/1PN3P1/P3QP1P/3R1RK1 w - - 0 20',
    move: 'e2e6',
  ),
  (
    id: '001Wz',
    fen: '6k1/5ppp/r1p5/p1n1rP2/8/2P2N1P/2P3P1/3R2K1 w - - 0 22',
    move: 'd1d8',
  ),
  (
    id: '001om',
    fen: '5r1k/pp4pp/5p2/1BbQp1r1/7K/7P/1PP3P1/3R3R b - - 3 26',
    move: 'c5f2',
  ),
  (
    id: '001w5',
    fen: '1rb3k1/q4rP1/4p2p/3p3p/3P1P2/2P5/2QK3P/3R2R1 w - - 1 30',
    move: 'c2h7',
  ),
  (
    id: '002Mm',
    fen: 'rn1qrk2/ppp3pQ/3p1pP1/3Pp3/2P1P3/8/PP3PP1/R1B1K3 w Q - 3 17',
    move: 'h7h8',
  ),
  (
    id: '002X3',
    fen: '6k1/2q2p1p/4pPp1/4P3/p1pP1P2/r1P5/6QP/4B1K1 w - - 0 34',
    move: 'g2a8',
  ),
  (
    id: '002p5',
    fen: 'r1bqr1k1/pp1nbpp1/2p5/3n2P1/2BP4/P7/1PQNNPP1/R3K2R w KQ - 1 14',
    move: 'c2h7',
  ),
];

/// Forks, pins and skewers that win material.
const List<TacticPuzzle> tactics = [
  (
    id: '000rO',
    theme: 'fork',
    fen: '3R4/8/8/KB2b3/1p6/1P2k3/3p4/8 b - - 0 58',
    move: 'e5c7',
  ),
  (
    id: '001wr',
    theme: 'fork',
    fen: 'r4rk1/p3ppbp/Pp1q1np1/3PpbB1/2B5/2N2P2/1PPQ2PP/3RR1K1 b - - 0 18',
    move: 'd6c5',
  ),
  (
    id: '002GQ',
    theme: 'fork',
    fen: '5rk1/5ppp/4p3/4N3/8/1Pn5/5PPP/2R3K1 b - - 1 28',
    move: 'c3e2',
  ),
  (
    id: '002IE',
    theme: 'fork',
    fen: 'r3brk1/5pp1/p2qpn1p/P2pn3/2pP4/2P1PN2/5PPP/RB1QK2R w KQ - 0 17',
    move: 'd4e5',
  ),
  (
    id: '003Jb',
    theme: 'fork',
    fen: '6k1/Q2bqr1p/2rpp1pR/p7/Pp2P3/1B3P2/1PP3P1/2KR4 b - - 7 22',
    move: 'e7g5',
  ),
  (
    id: '003jb',
    theme: 'fork',
    fen: 'r3kb1r/p4ppp/b3p3/2pq4/3Q4/4BN2/PPP2PPP/R3K2R w KQkq - 0 12',
    move: 'd4a4',
  ),
  (
    id: '003jv',
    theme: 'fork',
    fen: '7R/1p2k2p/p2n2p1/4K3/8/6P1/P6P/8 b - - 11 37',
    move: 'd6f7',
  ),
  (
    id: '003o0',
    theme: 'fork',
    fen: 'r1bqk2r/pp1nbppp/3p4/1B1p4/3P1B2/5N2/PPP2PPP/R2QK2R b KQkq - 3 9',
    move: 'd8a5',
  ),
  (
    id: '003r5',
    theme: 'fork',
    fen: 'r2qr1k1/ppp2ppp/4P3/8/1nP2Q2/2N2N1P/PP3KP1/R4R2 b - - 0 15',
    move: 'b4d3',
  ),
  (
    id: '004nd',
    theme: 'fork',
    fen: '3q2k1/3r4/pp3p1Q/2b1n3/P3N3/2P5/1P4PP/R6K w - - 1 25',
    move: 'e4f6',
  ),
  (
    id: '003S3',
    theme: 'pin',
    fen: '1r3k1r/pNqnppb1/6pn/2p3Np/7P/2P2Q2/PP3PP1/R1B1K2R w KQ - 3 16',
    move: 'g5e6',
  ),
  (
    id: '003nQ',
    theme: 'pin',
    fen: '6rk/pp6/2n5/3ppn1p/3p4/2P2P1q/PP3QNB/R5RK b - - 3 29',
    move: 'f5g3',
  ),
  (
    id: '00Dt6',
    theme: 'pin',
    fen: '5rk1/p4p1p/4p1p1/5nq1/8/5QPP/5PK1/1R1R4 b - - 7 35',
    move: 'f5h4',
  ),
  (
    id: '00LNH',
    theme: 'pin',
    fen: '1k2r3/pp2r2p/2pqbpp1/3n4/3P1p2/1B3N1P/PPQB1PP1/1K1RR3 b - - 3 22',
    move: 'e6f5',
  ),
  (
    id: '00Tdk',
    theme: 'pin',
    fen: 'r6r/4kppp/2pNpnq1/p1P1n3/8/B3P3/PP1Q1PPP/3R1RK1 b - - 8 20',
    move: 'e5f3',
  ),
  (
    id: '00XL2',
    theme: 'pin',
    fen: '2kr3r/ppp3pp/6q1/3Pnp2/1PPQp3/7P/P3NPP1/R4RK1 b - - 2 17',
    move: 'e5f3',
  ),
  (
    id: '00ZeT',
    theme: 'pin',
    fen: '1Q6/3kr3/2q4p/2p1pp1P/2Bb4/1P6/P6K/4R3 w - - 5 44',
    move: 'c4b5',
  ),
  (
    id: '00bns',
    theme: 'pin',
    fen: '6k1/1pp2ppp/p3n1q1/4PN2/2P2Q2/1P1rBP1P/r4P1K/4R3 w - - 6 31',
    move: 'f5e7',
  ),
  (
    id: '00cy1',
    theme: 'pin',
    fen: '2rknb2/3q1pp1/p1pP3r/1pQ1P3/5P1p/1P4P1/PB4K1/3R4 w - - 0 28',
    move: 'c5b6',
  ),
  (
    id: '00n3G',
    theme: 'pin',
    fen: '1k4r1/7p/1p4r1/pPp1qp2/P1Pp1R2/3Q1RNP/2P4K/8 b - - 5 32',
    move: 'g6g3',
  ),
  (
    id: '001m3',
    theme: 'skewer',
    fen: '7r/6k1/2b1Rp2/8/P1N3p1/5nP1/5P2/Q4K2 b - - 0 38',
    move: 'h8h1',
  ),
  (
    id: '001xl',
    theme: 'skewer',
    fen: '8/4R3/p4kpp/3B4/5q2/8/5P1P/6K1 w - - 6 41',
    move: 'e7f7',
  ),
  (
    id: '004mT',
    theme: 'skewer',
    fen: '5Q2/8/1bk1p1p1/5p2/3p4/5qPK/7P/8 w - - 2 52',
    move: 'f8a8',
  ),
  (
    id: '006OI',
    theme: 'skewer',
    fen: '6R1/p7/5k2/P7/6KP/8/8/5r2 b - - 6 53',
    move: 'f1g1',
  ),
  (
    id: '006yP',
    theme: 'skewer',
    fen: '6R1/8/Kpk1p3/1p1pP3/6P1/PPr5/8/8 w - - 0 41',
    move: 'g8c8',
  ),
  (
    id: '00AB1',
    theme: 'skewer',
    fen: '8/7Q/3p1kp1/1p6/2b5/2q4P/5PPK/8 w - - 0 37',
    move: 'h7h8',
  ),
  (
    id: '00EoE',
    theme: 'skewer',
    fen: 'r1b5/ppr2k1p/5p2/5p2/8/2P3P1/P4PP1/4RK1R w - - 2 24',
    move: 'h1h7',
  ),
  (
    id: '00KMV',
    theme: 'skewer',
    fen: '1r3k2/1p1q1p2/p2p2p1/2pP2bp/2P1n1n1/1PQ3P1/P3N1K1/3N1R1R w - - 0 29',
    move: 'c3h8',
  ),
  (
    id: '00KOz',
    theme: 'skewer',
    fen: '8/r4k2/7R/3n1PK1/8/8/8/8 w - - 4 57',
    move: 'h6h7',
  ),
];
