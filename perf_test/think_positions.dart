/// The positions `think_time_test.dart` times the computer on (#112): the
/// same 40 at every strength step, none of them over or with a single legal
/// move — `test/tools/think_time_report_test.dart` holds the list to that.
library;

/// Which part of a game a position stands for.
enum ThinkCategory { opening, middlegame, endgame }

/// One timed position: its [category], a [name] to find it by, and its
/// [fen]. Its index in [thinkPositions] is the seed it is played with.
final class ThinkPosition {
  const ThinkPosition(this.category, this.name, this.fen);

  final ThinkCategory category;
  final String name;
  final String fen;
}

/// The timed positions: 15 openings, 15 middlegames, 10 endgames. The
/// middlegames and two endgames are the Bratko–Kopec test set's and the
/// published perft positions' (Kiwipete, positions 3 and 6), chosen because
/// they are busy, real positions; the rest are standard opening lines and
/// textbook endings.
const List<ThinkPosition> thinkPositions = [
  ThinkPosition(
    ThinkCategory.opening,
    'start',
    'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
  ),
  ThinkPosition(
    ThinkCategory.opening,
    'Ruy Lopez',
    'r1bqkbnr/pppp1ppp/2n5/1B2p3/4P3/5N2/PPPP1PPP/RNBQK2R b KQkq - 3 3',
  ),
  ThinkPosition(
    ThinkCategory.opening,
    'Sicilian',
    'rnbqkbnr/pp1ppppp/8/2p5/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2',
  ),
  ThinkPosition(
    ThinkCategory.opening,
    'French',
    'rnbqkbnr/ppp2ppp/4p3/3p4/3PP3/8/PPP2PPP/RNBQKBNR w KQkq - 0 3',
  ),
  ThinkPosition(
    ThinkCategory.opening,
    'Caro-Kann',
    'rnbqkbnr/pp2pppp/2p5/3p4/3PP3/8/PPP2PPP/RNBQKBNR w KQkq - 0 3',
  ),
  ThinkPosition(
    ThinkCategory.opening,
    "Queen's Gambit Declined",
    'rnbqkb1r/ppp2ppp/4pn2/3p4/2PP4/2N5/PP2PPPP/R1BQKBNR w KQkq - 2 4',
  ),
  ThinkPosition(
    ThinkCategory.opening,
    "King's Indian",
    'rnbqk2r/ppp1ppbp/3p1np1/8/2PPP3/2N5/PP3PPP/R1BQKBNR w KQkq - 0 5',
  ),
  ThinkPosition(
    ThinkCategory.opening,
    'Italian',
    'r1bqk1nr/pppp1ppp/2n5/2b1p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4',
  ),
  ThinkPosition(
    ThinkCategory.opening,
    'Scandinavian',
    'rnb1kbnr/ppp1pppp/8/3q4/8/2N5/PPPP1PPP/R1BQKBNR b KQkq - 1 3',
  ),
  ThinkPosition(
    ThinkCategory.opening,
    'English',
    'rnbqkbnr/pppp1ppp/8/4p3/2P5/8/PP1PPPPP/RNBQKBNR w KQkq - 0 2',
  ),
  ThinkPosition(
    ThinkCategory.opening,
    'London',
    'rnbqkb1r/ppp1pppp/5n2/3p4/3P1B2/5N2/PPP1PPPP/RN1QKB1R b KQkq - 3 3',
  ),
  ThinkPosition(
    ThinkCategory.opening,
    'Slav',
    'rnbqkbnr/pp2pppp/2p5/3p4/2PP4/8/PP2PPPP/RNBQKBNR w KQkq - 0 3',
  ),
  ThinkPosition(
    ThinkCategory.opening,
    'Nimzo-Indian',
    'rnbqk2r/pppp1ppp/4pn2/8/1bPP4/2N5/PP2PPPP/R1BQKBNR w KQkq - 2 4',
  ),
  ThinkPosition(
    ThinkCategory.opening,
    'Petrov',
    'rnbqkb1r/pppp1ppp/5n2/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3',
  ),
  ThinkPosition(
    ThinkCategory.opening,
    'Dutch',
    'rnbqkbnr/ppppp1pp/8/5p2/3P4/8/PPP1PPPP/RNBQKBNR w KQkq - 0 2',
  ),
  ThinkPosition(
    ThinkCategory.middlegame,
    'Kiwipete',
    'r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1',
  ),
  ThinkPosition(
    ThinkCategory.middlegame,
    'perft 6',
    'r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0 10',
  ),
  ThinkPosition(
    ThinkCategory.middlegame,
    'BK.01',
    '1k1r4/pp1b1R2/3q2pp/4p3/2B5/4Q3/PPP2B2/2K5 b - - 0 1',
  ),
  ThinkPosition(
    ThinkCategory.middlegame,
    'BK.02',
    '3r1k2/4npp1/1ppr3p/p6P/P2PPPP1/1NR5/5K2/2R5 w - - 0 1',
  ),
  ThinkPosition(
    ThinkCategory.middlegame,
    'BK.03',
    '2q1rr1k/3bbnnp/p2p1pp1/2pPp3/PpP1P1P1/1P2BNNP/2BQ1PRK/7R b - - 0 1',
  ),
  ThinkPosition(
    ThinkCategory.middlegame,
    'BK.04',
    'rnbqkb1r/p3pppp/1p6/2ppP3/3N4/2P5/PPP1QPPP/R1B1KB1R w KQkq - 0 1',
  ),
  ThinkPosition(
    ThinkCategory.middlegame,
    'BK.05',
    'r1b2rk1/2q1b1pp/p2ppn2/1p6/3QP3/1BN1B3/PPP3PP/R4RK1 w - - 0 1',
  ),
  ThinkPosition(
    ThinkCategory.middlegame,
    'BK.07',
    '1nk1r1r1/pp2n1pp/4p3/q2pPp1N/b1pP1P2/B1P2R2/2P1B1PP/R2Q2K1 w - - 0 1',
  ),
  ThinkPosition(
    ThinkCategory.middlegame,
    'BK.09',
    '2kr1bnr/pbpq4/2n1pp2/3p3p/3P1P1B/2N2N1Q/PPP3PP/2KR1B1R w - - 0 1',
  ),
  ThinkPosition(
    ThinkCategory.middlegame,
    'BK.10',
    '3rr1k1/pp3pp1/1qn2np1/8/3p4/PP1R1P2/2P1NQPP/R1B3K1 b - - 0 1',
  ),
  ThinkPosition(
    ThinkCategory.middlegame,
    'BK.11',
    '2r1nrk1/p2q1ppp/bp1p4/n1pPp3/P1P1P3/2PBB1N1/4QPPP/R4RK1 w - - 0 1',
  ),
  ThinkPosition(
    ThinkCategory.middlegame,
    'BK.12',
    'r3r1k1/ppqb1ppp/8/4p1NQ/8/2P5/PP3PPP/R3R1K1 b - - 0 1',
  ),
  ThinkPosition(
    ThinkCategory.middlegame,
    'BK.13',
    'r2q1rk1/4bppp/p2p4/2pP4/3pP3/3Q4/PP1B1PPP/R3R1K1 w - - 0 1',
  ),
  ThinkPosition(
    ThinkCategory.middlegame,
    'BK.14',
    'rnb2r1k/pp2p2p/2pp2p1/q2P1p2/8/1Pb2NP1/PB2PPBP/R2Q1RK1 w - - 0 1',
  ),
  ThinkPosition(
    ThinkCategory.middlegame,
    'BK.15',
    '2r3k1/1p2q1pp/2b1pr2/p1pp4/6Q1/1P1PP1R1/P1PN2PP/5RK1 w - - 0 1',
  ),
  ThinkPosition(
    ThinkCategory.endgame,
    'BK.06',
    '2r3k1/pppR1pp1/4p3/4P1P1/5P2/1P4K1/P1P5/8 w - - 0 1',
  ),
  ThinkPosition(
    ThinkCategory.endgame,
    'BK.08',
    '4b3/p3kp2/6p1/3pP2p/2pP1P2/4K1P1/P3N2P/8 w - - 0 1',
  ),
  ThinkPosition(
    ThinkCategory.endgame,
    'perft 3',
    '8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1',
  ),
  ThinkPosition(
    ThinkCategory.endgame,
    'Lucena',
    '1K1k4/1P6/8/8/8/8/r7/2R5 w - - 0 1',
  ),
  ThinkPosition(
    ThinkCategory.endgame,
    'Fine 70',
    '8/k7/3p4/p2P1p2/P2P1P2/8/8/K7 w - - 0 1',
  ),
  ThinkPosition(
    ThinkCategory.endgame,
    'queen against rook',
    '8/8/4k3/8/2r5/8/3K4/6Q1 w - - 0 1',
  ),
  ThinkPosition(
    ThinkCategory.endgame,
    'rook and pawn against rook',
    '8/8/8/4k3/8/8/1r2P3/4K2R w K - 0 1',
  ),
  ThinkPosition(
    ThinkCategory.endgame,
    'knight against bishop',
    '8/5k2/8/3b4/8/2N5/5PK1/8 w - - 0 1',
  ),
  ThinkPosition(
    ThinkCategory.endgame,
    'pawn race',
    '8/pp3k2/8/8/8/8/5PPK/8 w - - 0 1',
  ),
  ThinkPosition(
    ThinkCategory.endgame,
    'queen ending',
    '6k1/5ppp/8/3q4/8/8/5PPP/3Q2K1 w - - 0 1',
  ),
];
