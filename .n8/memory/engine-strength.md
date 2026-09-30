---
name: engine-strength
description: Each strength step measured against Stockfish at fixed UCI_Elo levels, or chained through a match against a measured step — one dated section per run of tools/benchmark_stockfish.sh
metadata:
  type: project
---

# Engine strength

Each section below is one run of `tools/benchmark_stockfish.sh` (#69,
#159), written by the script and committed by hand; each names the commit
it measured. #69 set Master's target at 1800–2000 Elo. #159 replaced it
with the owner's targets for every step (2026-09-29): Beginner ~600,
Casual ~900, Club ~1200, Strong ~1600 and Master ~2200. The retune added
blunders and changed Club and Strong, but left Master unchanged, so the
2026-09-29 Master section still stands.

## 2026-09-29 — Master against Stockfish 19

- **Estimate:** Master ≈ 2207 (95% interval 2125–2289), by logistic (400-point) maximum likelihood over all levels, draws as half points; the interval is the normal approximation.
- **Target 1800–2000:** met: the estimate is above 2000, stronger than the target range.
- **Hardware:** Apple M3 Max, 128 GB (`sysctl -n machdep.cpu.brand_string hw.memsize`)
- **Engine under test:** `Strength.master` at 1500000 nodes per move, commit 9ed93b5.
- **Stockfish:** `Stockfish 19`, `Threads=1`, `Hash=64`, `UCI_LimitStrength=true`, `UCI_Elo` 1600 / 1800 / 2000.
- **Games:** 60 per level from the ladder's openings (`test/fixtures/openings.dart`), each opening with both colours in turn; seeds 2026 + game index; a 200-ply cap after the opening is a draw. Took 141 min.
- **Clock:** Stockfish plays on 5 s + 0.1 s per move (`go wtime/btime/winc/binc`) and lost on time in 0 games. Master plays every move at its fixed node budget; its clock is recorded, not enforced: 0.87 s per move on average, and it would have lost on time in 180 games.
- **Caveat:** `UCI_Elo` is Stockfish's own calibration, made under conditions other than this match's clock; read the estimate as approximate.
- **Caveat (clocks):** the two sides did not play under the same time. Stockfish played on its 5 s + 0.1 s clock, while Master took 0.87 s per move on average with no clock enforced. The estimate measures Master at its fixed node budget, which is what players get on any device. It does not measure play under equal time.
- **Caveat (load):** the dev Mac was also running M3's builds and test suites for much of this run (/n8-exec M3, 2026-09-29). That can only slow Stockfish, which plays on a real clock, so the estimate may be somewhat high.
- **Command:** `tools/benchmark_stockfish.sh --out <scratch>/engine-strength.md --pgn <scratch>/pgn`, run from the M2 branch at 9ed93b5; the section was then copied here by hand.

| Stockfish `UCI_Elo` | Games | Master W / D / L | Score | Performance |
| --- | --- | --- | --- | --- |
| 1600 | 60 | 57 / 2 / 1 | 96.7% | 2185 |
| 1800 | 60 | 52 / 3 / 5 | 89.2% | 2166 |
| 2000 | 60 | 44 / 7 / 9 | 79.2% | 2232 |
