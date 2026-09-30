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

## 2026-09-30 — Strong against Stockfish 19

- **Estimate:** Strong ≈ 1610 (95% interval 1552–1669), by logistic (400-point) maximum likelihood over all levels, draws as half points; the interval is the normal approximation.
- **Target ~1600 (the owner's, #159, 2026-09-29):** met: 1600 is within the interval.
- **Hardware:** Apple M3 Max, 128 GB (`sysctl -n machdep.cpu.brand_string hw.memsize`)
- **Engine under test:** `Strength.strong` at 610000 nodes per move (depth cap 4, noise ±0 cp, blunders on 3% of moves, sees mate in one), commit 7f01731.
- **Stockfish:** `Stockfish 19`, `Threads=1`, `Hash=64`, `UCI_LimitStrength=true`, `UCI_Elo` 1320 / 1600 / 1800.
- **Games:** 60 per level from the ladder's openings (`test/fixtures/openings.dart`), each opening with both colours in turn; seeds 2026 + game index; a 200-ply cap after the opening is a draw. Took 6 min.
- **Clock:** Stockfish plays on 5 s + 0.1 s per move (`go wtime/btime/winc/binc`) and ran out of time in 5 games; a fallen flag is counted, not enforced, and it then sees one increment on its clock. Strong plays every move at its fixed node budget; its clock is recorded, not enforced: 0.04 s per move on average, and it would have lost on time in 0 games.
- **Caveat:** `UCI_Elo` is Stockfish's own calibration, made under conditions other than this match's clock; read the estimate as approximate.
- **Command:** `tools/benchmark_stockfish.sh --step strong --levels 1320,1600,1800 --games 60 --jobs 6 --out /private/tmp/claude-501/-Users-npond-StudioProjects-honest-chess/d363648b-c82f-4b6b-a389-56bb53711bc5/scratchpad/exec/bench159/rec/engine-strength.md --pgn /private/tmp/claude-501/-Users-npond-StudioProjects-honest-chess/d363648b-c82f-4b6b-a389-56bb53711bc5/scratchpad/exec/bench159/rec/pgn`

| Stockfish `UCI_Elo` | Games | Strong W / D / L | Score | Performance |
| --- | --- | --- | --- | --- |
| 1320 | 60 | 46 / 7 / 7 | 82.5% | 1589 |
| 1600 | 60 | 26 / 8 / 26 | 50.0% | 1600 |
| 1800 | 60 | 12 / 10 / 38 | 28.3% | 1639 |

## 2026-09-30 — Club against Stockfish 19

- **Estimate:** Club ≈ 1209 (95% interval 1148–1270), by logistic (400-point) maximum likelihood over all levels, draws as half points; the interval is the normal approximation.
- **Target ~1200 (the owner's, #159, 2026-09-29):** met: 1200 is within the interval.
- **Hardware:** Apple M3 Max, 128 GB (`sysctl -n machdep.cpu.brand_string hw.memsize`)
- **Engine under test:** `Strength.club` at 310000 nodes per move (depth cap 2, noise ±40 cp, blunders on 10% of moves, sees mate in one), commit 7f01731.
- **Stockfish:** `Stockfish 19`, `Threads=1`, `Hash=64`, `UCI_LimitStrength=true`, `UCI_Elo` 1320 / 1600.
- **Games:** 100 per level from the ladder's openings (`test/fixtures/openings.dart`), each opening with both colours in turn; seeds 2026 + game index; a 200-ply cap after the opening is a draw. Took 5 min.
- **Clock:** Stockfish plays on 5 s + 0.1 s per move (`go wtime/btime/winc/binc`) and ran out of time in 0 games; a fallen flag is counted, not enforced, and it then sees one increment on its clock. Club plays every move at its fixed node budget; its clock is recorded, not enforced: 0.00 s per move on average, and it would have lost on time in 0 games.
- **Caveat:** `UCI_Elo` is Stockfish's own calibration, made under conditions other than this match's clock; read the estimate as approximate.
- **Command:** `tools/benchmark_stockfish.sh --step club --levels 1320,1600 --games 100 --jobs 6 --out /private/tmp/claude-501/-Users-npond-StudioProjects-honest-chess/d363648b-c82f-4b6b-a389-56bb53711bc5/scratchpad/exec/bench159/rec/engine-strength.md --pgn /private/tmp/claude-501/-Users-npond-StudioProjects-honest-chess/d363648b-c82f-4b6b-a389-56bb53711bc5/scratchpad/exec/bench159/rec/pgn`

| Stockfish `UCI_Elo` | Games | Club W / D / L | Score | Performance |
| --- | --- | --- | --- | --- |
| 1320 | 100 | 31 / 15 / 54 | 38.5% | 1239 |
| 1600 | 100 | 4 / 3 / 93 | 5.5% | 1106 |

## 2026-09-30 — Casual against Stockfish 19

- **Estimate:** Casual ≈ 1057 (95% interval 994–1119), by logistic (400-point) maximum likelihood over all levels, draws as half points; the interval is the normal approximation.
- **Target ~900 (the owner's, #159, 2026-09-29):** missed: the estimate is 157 above 900, outside its interval.
- **Hardware:** Apple M3 Max, 128 GB (`sysctl -n machdep.cpu.brand_string hw.memsize`)
- **Engine under test:** `Strength.casual` at 180000 nodes per move (depth cap 2, noise ±80 cp, blunders on 15% of moves, sees mate in one), commit 7f01731.
- **Stockfish:** `Stockfish 19`, `Threads=1`, `Hash=64`, `UCI_LimitStrength=true`, `UCI_Elo` 1320.
- **Games:** 200 per level from the ladder's openings (`test/fixtures/openings.dart`), each opening with both colours in turn; seeds 2026 + game index; a 200-ply cap after the opening is a draw. Took 5 min.
- **Clock:** Stockfish plays on 5 s + 0.1 s per move (`go wtime/btime/winc/binc`) and ran out of time in 3 games; a fallen flag is counted, not enforced, and it then sees one increment on its clock. Casual plays every move at its fixed node budget; its clock is recorded, not enforced: 0.00 s per move on average, and it would have lost on time in 0 games.
- **Caveat:** `UCI_Elo` is Stockfish's own calibration, made under conditions other than this match's clock; read the estimate as approximate.
- **Command:** `tools/benchmark_stockfish.sh --step casual --levels 1320 --games 200 --jobs 6 --out /private/tmp/claude-501/-Users-npond-StudioProjects-honest-chess/d363648b-c82f-4b6b-a389-56bb53711bc5/scratchpad/exec/bench159/rec/engine-strength.md --pgn /private/tmp/claude-501/-Users-npond-StudioProjects-honest-chess/d363648b-c82f-4b6b-a389-56bb53711bc5/scratchpad/exec/bench159/rec/pgn`

| Stockfish `UCI_Elo` | Games | Casual W / D / L | Score | Performance |
| --- | --- | --- | --- | --- |
| 1320 | 200 | 23 / 26 / 151 | 18.0% | 1057 |

## 2026-09-30 — Beginner against Stockfish 19

- **Estimate:** Beginner ≈ 400 (95% interval 59–742), by logistic (400-point) maximum likelihood over all levels, draws as half points; the interval is the normal approximation.
- **Target ~600 (the owner's, #159, 2026-09-29):** met: 600 is within the interval.
- **Hardware:** Apple M3 Max, 128 GB (`sysctl -n machdep.cpu.brand_string hw.memsize`)
- **Engine under test:** `Strength.beginner` at 92000 nodes per move (depth cap 1, noise ±200 cp, blunders on 20% of moves, may miss mate in one), commit 7f01731.
- **Stockfish:** `Stockfish 19`, `Threads=1`, `Hash=64`, `UCI_LimitStrength=true`, `UCI_Elo` 1320.
- **Games:** 200 per level from the ladder's openings (`test/fixtures/openings.dart`), each opening with both colours in turn; seeds 2026 + game index; a 200-ply cap after the opening is a draw. Took 4 min.
- **Clock:** Stockfish plays on 5 s + 0.1 s per move (`go wtime/btime/winc/binc`) and ran out of time in 0 games; a fallen flag is counted, not enforced, and it then sees one increment on its clock. Beginner plays every move at its fixed node budget; its clock is recorded, not enforced: 0.00 s per move on average, and it would have lost on time in 0 games.
- **Caveat:** `UCI_Elo` is Stockfish's own calibration, made under conditions other than this match's clock; read the estimate as approximate.
- **Command:** `tools/benchmark_stockfish.sh --step beginner --levels 1320 --games 200 --jobs 6 --out /private/tmp/claude-501/-Users-npond-StudioProjects-honest-chess/d363648b-c82f-4b6b-a389-56bb53711bc5/scratchpad/exec/bench159/rec/engine-strength.md --pgn /private/tmp/claude-501/-Users-npond-StudioProjects-honest-chess/d363648b-c82f-4b6b-a389-56bb53711bc5/scratchpad/exec/bench159/rec/pgn`

| Stockfish `UCI_Elo` | Games | Beginner W / D / L | Score | Performance |
| --- | --- | --- | --- | --- |
| 1320 | 200 | 0 / 2 / 198 | 0.5% | 400 |

## 2026-09-30 — Casual against Club (chained)

- **Estimate:** Casual ≈ 994 (95% interval 910–1078): Club's anchor, 1209 (95% interval 1148–1270), plus the match's rating difference, -215 (95% interval -273 to -157). The difference is fitted by logistic (400-point) maximum likelihood, draws as half points. The two 95% intervals are combined in quadrature, as independent normal errors.
- **Method:** chained, because Stockfish cannot play below 1320. `UCI_Elo` stops at 1320, and its mapping to `Skill Level` puts 1320 at level 0 (Stockfish `src/search.h`, `struct Skill`, read 2026-09-30), so `Skill Level` goes no lower either. The anchor is Club's estimate from its own dated section in this file.
- **Target ~900 (the owner's, #159, 2026-09-29):** missed: the estimate is 94 above 900, outside its interval.
- **Hardware:** Apple M3 Max, 128 GB (`sysctl -n machdep.cpu.brand_string hw.memsize`)
- **Engine under test:** `Strength.casual` at 180000 nodes per move (depth cap 2, noise ±80 cp, blunders on 15% of moves, sees mate in one), against `Strength.club` at 310000 nodes per move (depth cap 2, noise ±40 cp, blunders on 10% of moves, sees mate in one), commit 7f01731.
- **Games:** 200 from the ladder's openings (`test/fixtures/openings.dart`), each opening with both colours in turn; seeds 2026 + game index, shared by both sides; a 200-ply cap after the opening is a draw. Both sides play at their fixed node budgets, with no clock. Took 0 min.
- **Caveat (self-play):** two steps of one engine share its evaluation and blind spots, so a match between them can read a wider gap than either would show against other players.
- **Command:** `tools/benchmark_stockfish.sh --step casual --vs club --anchor 1209,1148,1270 --games 200 --jobs 6 --out /private/tmp/claude-501/-Users-npond-StudioProjects-honest-chess/d363648b-c82f-4b6b-a389-56bb53711bc5/scratchpad/exec/bench159/rec/engine-strength.md --pgn /private/tmp/claude-501/-Users-npond-StudioProjects-honest-chess/d363648b-c82f-4b6b-a389-56bb53711bc5/scratchpad/exec/bench159/rec/pgn`

| Opponent | Games | Casual W / D / L | Score | Difference |
| --- | --- | --- | --- | --- |
| Club | 200 | 32 / 26 / 142 | 22.5% | -215 |

## 2026-09-30 — Beginner against Casual (chained)

- **Estimate:** Beginner ≈ 536 (95% interval 407–665): Casual's anchor, 1057 (95% interval 994–1119), plus the match's rating difference, -521 (95% interval -634 to -408). The difference is fitted by logistic (400-point) maximum likelihood, draws as half points. The two 95% intervals are combined in quadrature, as independent normal errors.
- **Method:** chained, because Stockfish cannot play below 1320. `UCI_Elo` stops at 1320, and its mapping to `Skill Level` puts 1320 at level 0 (Stockfish `src/search.h`, `struct Skill`, read 2026-09-30), so `Skill Level` goes no lower either. The anchor is Casual's estimate from its own dated section in this file.
- **Target ~600 (the owner's, #159, 2026-09-29):** met: 600 is within the interval.
- **Hardware:** Apple M3 Max, 128 GB (`sysctl -n machdep.cpu.brand_string hw.memsize`)
- **Engine under test:** `Strength.beginner` at 92000 nodes per move (depth cap 1, noise ±200 cp, blunders on 20% of moves, may miss mate in one), against `Strength.casual` at 180000 nodes per move (depth cap 2, noise ±80 cp, blunders on 15% of moves, sees mate in one), commit 7f01731.
- **Games:** 200 from the ladder's openings (`test/fixtures/openings.dart`), each opening with both colours in turn; seeds 2026 + game index, shared by both sides; a 200-ply cap after the opening is a draw. Both sides play at their fixed node budgets, with no clock. Took 0 min.
- **Caveat (self-play):** two steps of one engine share its evaluation and blind spots, so a match between them can read a wider gap than either would show against other players.
- **Command:** `tools/benchmark_stockfish.sh --step beginner --vs casual --anchor 1057,994,1119 --games 200 --jobs 6 --out /private/tmp/claude-501/-Users-npond-StudioProjects-honest-chess/d363648b-c82f-4b6b-a389-56bb53711bc5/scratchpad/exec/bench159/rec/engine-strength.md --pgn /private/tmp/claude-501/-Users-npond-StudioProjects-honest-chess/d363648b-c82f-4b6b-a389-56bb53711bc5/scratchpad/exec/bench159/rec/pgn`

| Opponent | Games | Beginner W / D / L | Score | Difference |
| --- | --- | --- | --- | --- |
| Casual | 200 | 0 / 19 / 181 | 4.8% | -521 |

## 2026-09-30 — Casual against Stockfish 19

- **Estimate:** Casual ≈ 957 (95% interval 880–1034), by logistic (400-point) maximum likelihood over all levels, draws as half points; the interval is the normal approximation.
- **Target ~900 (the owner's, #159, 2026-09-29):** met: 900 is within the interval.
- **Hardware:** Apple M3 Max, 128 GB (`sysctl -n machdep.cpu.brand_string hw.memsize`)
- **Engine under test:** `Strength.casual` at 180000 nodes per move (depth cap 2, noise ±100 cp, blunders on 20% of moves, sees mate in one), commit 2d75e03.
- **Stockfish:** `Stockfish 19`, `Threads=1`, `Hash=64`, `UCI_LimitStrength=true`, `UCI_Elo` 1320.
- **Games:** 200 per level from the ladder's openings (`test/fixtures/openings.dart`), each opening with both colours in turn; seeds 2026 + game index; a 200-ply cap after the opening is a draw. Took 5 min.
- **Clock:** Stockfish plays on 5 s + 0.1 s per move (`go wtime/btime/winc/binc`) and ran out of time in 0 games; a fallen flag is counted, not enforced, and it then sees one increment on its clock. Casual plays every move at its fixed node budget; its clock is recorded, not enforced: 0.00 s per move on average, and it would have lost on time in 0 games.
- **Caveat:** `UCI_Elo` is Stockfish's own calibration, made under conditions other than this match's clock; read the estimate as approximate.
- **Command:** `tools/benchmark_stockfish.sh --step casual --levels 1320 --games 200 --jobs 6 --out /private/tmp/claude-501/-Users-npond-StudioProjects-honest-chess/d363648b-c82f-4b6b-a389-56bb53711bc5/scratchpad/exec/bench171/rec/engine-strength.md --pgn /private/tmp/claude-501/-Users-npond-StudioProjects-honest-chess/d363648b-c82f-4b6b-a389-56bb53711bc5/scratchpad/exec/bench171/rec/pgn`

| Stockfish `UCI_Elo` | Games | Casual W / D / L | Score | Performance |
| --- | --- | --- | --- | --- |
| 1320 | 200 | 12 / 20 / 168 | 11.0% | 957 |

## 2026-09-30 — Casual against Club (chained)

- **Estimate:** Casual ≈ 827 (95% interval 726–928): Club's anchor, 1209 (95% interval 1148–1270), plus the match's rating difference, -382 (95% interval -462 to -301). The difference is fitted by logistic (400-point) maximum likelihood, draws as half points. The two 95% intervals are combined in quadrature, as independent normal errors.
- **Method:** chained, because Stockfish cannot play below 1320. `UCI_Elo` stops at 1320, and its mapping to `Skill Level` puts 1320 at level 0 (Stockfish `src/search.h`, `struct Skill`, read 2026-09-30), so `Skill Level` goes no lower either. The anchor is Club's estimate from its own dated section in this file.
- **Target ~900 (the owner's, #159, 2026-09-29):** met: 900 is within the interval.
- **Hardware:** Apple M3 Max, 128 GB (`sysctl -n machdep.cpu.brand_string hw.memsize`)
- **Engine under test:** `Strength.casual` at 180000 nodes per move (depth cap 2, noise ±100 cp, blunders on 20% of moves, sees mate in one), against `Strength.club` at 310000 nodes per move (depth cap 2, noise ±40 cp, blunders on 10% of moves, sees mate in one), commit 2d75e03.
- **Games:** 200 from the ladder's openings (`test/fixtures/openings.dart`), each opening with both colours in turn; seeds 2026 + game index, shared by both sides; a 200-ply cap after the opening is a draw. Both sides play at their fixed node budgets, with no clock. Took 0 min.
- **Caveat (self-play):** two steps of one engine share its evaluation and blind spots, so a match between them can read a wider gap than either would show against other players.
- **Command:** `tools/benchmark_stockfish.sh --step casual --vs club --anchor 1209,1148,1270 --games 200 --jobs 6 --out /private/tmp/claude-501/-Users-npond-StudioProjects-honest-chess/d363648b-c82f-4b6b-a389-56bb53711bc5/scratchpad/exec/bench171/rec/engine-strength.md --pgn /private/tmp/claude-501/-Users-npond-StudioProjects-honest-chess/d363648b-c82f-4b6b-a389-56bb53711bc5/scratchpad/exec/bench171/rec/pgn`

| Opponent | Games | Casual W / D / L | Score | Difference |
| --- | --- | --- | --- | --- |
| Club | 200 | 12 / 16 / 172 | 10.0% | -382 |

## 2026-09-30 — Beginner against Casual (chained)

- **Estimate:** Beginner ≈ 627 (95% interval 522–732): Casual's anchor, 957 (95% interval 880–1034), plus the match's rating difference, -330 (95% interval -402 to -259). The difference is fitted by logistic (400-point) maximum likelihood, draws as half points. The two 95% intervals are combined in quadrature, as independent normal errors.
- **Method:** chained, because Stockfish cannot play below 1320. `UCI_Elo` stops at 1320, and its mapping to `Skill Level` puts 1320 at level 0 (Stockfish `src/search.h`, `struct Skill`, read 2026-09-30), so `Skill Level` goes no lower either. The anchor is Casual's estimate from its own dated section in this file.
- **Target ~600 (the owner's, #159, 2026-09-29):** met: 600 is within the interval.
- **Hardware:** Apple M3 Max, 128 GB (`sysctl -n machdep.cpu.brand_string hw.memsize`)
- **Engine under test:** `Strength.beginner` at 92000 nodes per move (depth cap 1, noise ±200 cp, blunders on 20% of moves, may miss mate in one), against `Strength.casual` at 180000 nodes per move (depth cap 2, noise ±100 cp, blunders on 20% of moves, sees mate in one), commit 2d75e03.
- **Games:** 200 from the ladder's openings (`test/fixtures/openings.dart`), each opening with both colours in turn; seeds 2026 + game index, shared by both sides; a 200-ply cap after the opening is a draw. Both sides play at their fixed node budgets, with no clock. Took 0 min.
- **Caveat (self-play):** two steps of one engine share its evaluation and blind spots, so a match between them can read a wider gap than either would show against other players.
- **Command:** `tools/benchmark_stockfish.sh --step beginner --vs casual --anchor 957,880,1034 --games 200 --jobs 6 --out /private/tmp/claude-501/-Users-npond-StudioProjects-honest-chess/d363648b-c82f-4b6b-a389-56bb53711bc5/scratchpad/exec/bench171/rec/engine-strength.md --pgn /private/tmp/claude-501/-Users-npond-StudioProjects-honest-chess/d363648b-c82f-4b6b-a389-56bb53711bc5/scratchpad/exec/bench171/rec/pgn`

| Opponent | Games | Beginner W / D / L | Score | Difference |
| --- | --- | --- | --- | --- |
| Casual | 200 | 0 / 52 / 148 | 13.0% | -330 |
