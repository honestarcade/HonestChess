# Honest Chess — test plan

Written against commit 57b9190 on `milestone/m6-testing` (2026-09-30), the
branch after the pre-release-candidate fixes #159–#167, #170 and #171.

What to check on a device, and how to record that it was checked. Every
screen, both modes, every strength step, every clock, every Settings row,
every gesture, persistence across a restart, and the sound, music, haptics,
motion and TalkBack feedback each have numbered checks below, in the order
you reach them from the menu. `test/guards/test_plan_test.dart` fails the
gate when a screen route, Settings row, strength step, clock, colour choice
or board look exists in the code but not here, or the other way round.

## How to use this plan

- **Runs.** A run is one pass through the plan on one device with the
  options of one row of the sampling table below (R1–R7). Set the row's
  Settings first, then its setup screen's options, then run every
  `Core: yes` check for that mode plus the checks the row's Notes name.
  Every option value is in at least one row; not every combination is
  (owner, round one of `/n8-plan M6`, 2026-09-28: every option once, not
  every combination).
- **Records.** Each run gets one record in `qa/runs/`, copied from
  `qa/runs/TEMPLATE.md` and named `YYYY-MM-DD-<device>-<who>[-n].md`, with
  `<device>` one of `s26ultra`, `emu-api24`, `emu-api34` and `<who>` one of
  `owner`, `agent`; `-2`, `-3` for a second or third run the same day. The
  owner reports phone results in chat; the agent transcribes them into the
  record and files the bugs.
- **Check fields.** Each check is `### T<nnn> — title` followed by `Steps:`
  (one action per line), `Expected:`, `Core:` (`yes` for the checks the
  scripted end-to-end game (#107) covers, plus one install and one launch
  check), `Where:` (`phone`, `emulator` or `both`) and `Automated:` (the
  tests that cover the same ground on the development machine, separated by
  `; `, or `none`).
- **Numbering.** Hundreds by screen family: T0xx install, T1xx splash and
  menu, T2xx setup screens, T3xx the board against the computer and the
  gestures, T4xx the two-player board, T5xx the cards (promotion, pause,
  declined draw, result, View board), T6xx Statistics, T7xx Settings, T8xx
  How to play and About, T9xx persistence and feedback. IDs are never
  renumbered; a check that no longer applies keeps its number and its
  heading reads `### T123 — ~~title~~ (retired YYYY-MM-DD)`.
- **Routes.** Each screen's section has a `route: <name>` line naming its
  route in `lib/ui/navigation.dart`. The menu has no route name: it is the
  first route, under the splash.
- **Emulator runs are not hardware.** The reference device is the owner's
  Samsung Galaxy S26 Ultra, and there is no second device. Android 7.0
  (API 24) and the smallest supported screen are covered only by emulators
  (`emu-api24`, and `emu-api34` with a 320×568 dp profile), and an emulator
  result is reported as an emulator result, never as a device result.
  Sound, music, haptics and the feel of play are judged on the phone.
- **History.** The owner's first play-through (2026-09-29, v0.2.0 build
  1021 from the internal track, recorded on PR #153) ran 17 journey checks
  before this plan existed; every one passed and its nine findings became
  #159–#167. The table below maps those journeys to the checks here, so a
  run can say which ground is re-walked. The checks that cover a finding
  expect the fixed behaviour.

| UAT check (v0.2.0) | Checks here | Findings |
|---|---|---|
| 1 first launch, splash, menu | T101, T110 | |
| 2 menu navigation and back | T111, T114, T801 | #165, #166 |
| 3 vs-computer setup | T201–T206 | #167 |
| 4 Strong, Black, 15+10 start | T301–T304 | |
| 5 tap and drag moves | T310–T314 | #163, #164 |
| 6 captures, castling, check | T315–T318 | #159 |
| 7 pause card | T520–T524 | |
| 8.1–8.2 draw offers | T525, T530–T531 | #160 |
| 8.3 result card and View board | T540–T544, T546, T550–T552 | #161 |
| 9 resume after closing | T901–T905 | |
| 10 two-player game | T401–T407, T501–T503 | #161, #162 |
| 11 Settings | T701–T722 | |
| 12 music | T952–T954 | |
| 13 Statistics and How to play | T601–T606, T801 | |
| 14 About screens | T810–T822 | |
| 15 greyscale | T962 | |
| 16 largest font | T961 | |
| 17 TalkBack | T960 | |

A "live game" below means a game with at least one move that is not over.
Moves are written from-square to-square: `e2e4`. "Force stop" means the
phone's Settings → Apps → Honest Chess → Force stop; "swipe away" means
closing the app from the recent-apps view. The move sequences the checks
use, each replayed through the engine by `test/qa/plan_sequences_test.dart`:

- **Fool's mate** (Black mates): `f2f3 e7e5 g2g4 d8h4`
- **Scholar's mate** (White mates): `e2e4 e7e5 f1c4 b8c6 d1h5 g8f6 h5f7`
- **Check** (Black's king in check along h5–e8): `e2e4 f7f6 d1h5`
- **Stalemate in ten** (Black to move, no legal move, not in check): `e2e3 a7a5 d1h5 a8a6 h5a5 h7h5 h2h4 a6h6 a5c7 f7f6 c7d7 e8f7 d7b7 d8d3 b7b8 d3h7 b8c8 f7g6 c8e6`
- **Repetition** (the start position for the third time): `g1f3 g8f6 f3g1 f6g8 g1f3 g8f6 f3g1 f6g8`
- **Promotion** (White's pawn on b7 can push to b8 or take on a8): `a2a4 b7b5 a4b5 a7a6 b5a6 c8b7 a6b7 b8c6`
- **En passant** (the pawn on e5 takes d5 by moving to d6): `e2e4 a7a6 e4e5 d7d5`, then `e5d6`
- **Castling** (the king's side): `e2e4 e7e5 g1f3 b8c6 f1c4 f8c5`, then `e1g1`

## Sampling

Every row is a phone run on the S26 Ultra; an emulator run names the row it
reuses. `n/a` marks an option the row's mode does not have. Play as
`random` records the colour drawn in the run record. The custom clock is
sampled at both ends of its steppers: 1+0 and 90+60. The Settings columns
are the Settings screen's rows by id, `on` or `off`:

| id | Settings row |
|---|---|
| dots | Legal-move dots |
| last-move | Last-move highlight |
| takeback | Takeback allowed |
| auto-queen | Auto-promote to queen |
| rotate | Rotate board each turn |
| anim | Piece animations |
| check-flag | Flag check on the board |
| sfx | Sound effects |
| music | Background music |
| haptics | Haptics |

| Run | Mode | Step | Play as | Clock | Board colour | Pieces | Surface | dots | last-move | takeback | auto-queen | rotate | anim | check-flag | sfx | music | haptics | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| R1 | vs computer | beginner | white | untimed | navy | classic | felt | on | on | on | off | off | on | on | on | off | on | first-run defaults for every switch |
| R2 | vs computer | casual | black | blitz | teal | outline | plain | off | off | off | on | off | off | off | off | off | off | every switch away from its default; T951, T956 |
| R3 | vs computer | club | random | rapid | violet | flat | wood | on | on | on | off | off | on | on | on | on | on | T952–T954 |
| R4 | vs computer | strong | white | classical | bone | classic | felt | on | off | on | off | off | on | on | on | off | on | the owner's UAT journey 4, now Classical |
| R5 | vs computer | master | black | custom 1+0 | navy | outline | wood | on | on | off | off | off | on | off | on | off | off | the flag falls: T546 |
| R6 | two players | n/a | n/a | custom 90+60 | bone | flat | plain | on | on | on | off | on | on | on | on | on | on | T402, T404 |
| R7 | two players | n/a | n/a | untimed | teal | classic | felt | off | on | off | off | off | off | on | on | off | on | T405, T406 |

## Install

### T001 — Install from the internal test link
Steps:
- On the S26 Ultra, open the internal testing link from the release's Play Console page and install the build.
- Open Settings in the app and read the version line at the bottom.
Expected: The build installs from Google Play with no permission prompt, and the version line reads `v<name> · BUILD <code>` matching the release being tested.
Core: yes
Where: phone
Automated: test/ui/settings_options_test.dart; integration_test/platform_channel_test.dart — appVersion answers a name and a positive code

### T002 — The app asks for nothing
Steps:
- Open the phone's Settings → Apps → Honest Chess → Permissions.
Expected: No permissions are listed, not even network access (CLAUDE.md invariant 1).
Core: no
Where: phone
Automated: test/guards/manifest_permission_example_test.dart; test/guards/bundle_scan_test.dart

### T003 — The oldest and smallest supported Android
Steps:
- Install the same build on the `emu-api24` emulator (Android 7.0) and on `emu-api34` with a 320×568 dp device profile.
- Launch it on each and open every screen from the menu once.
Expected: The app launches and every screen draws without a cut-off control; the board fits the smallest screen with no scrolling of the game screen.
Core: no
Where: emulator
Automated: test/ui/large_text_test.dart; test/a11y/guidelines_test.dart

## Splash

### T101 — The splash counts its loads, then opens the menu
Steps:
- Force stop the app.
- Launch it from its icon.
Expected: The splash shows the Honest mark, "Honest" in white and "Chess" in teal, BY HONEST ARCADE, and a teal-to-blue bar whose label moves through SETTING UP, SORTING PIECES and READY; it fades to the menu. It shows for at least 600 ms, however fast the loads finish.
Core: yes
Where: both
Automated: test/ui/splash_test.dart — the label follows the design's thresholds

### T102 — Back and leaving during the splash
Steps:
- Force stop and launch the app, and press back while the splash shows.
- Force stop and launch again, and press Home while READY shows; return to the app.
Expected: Back is ignored and the menu still follows. After Home, READY holds again on the return and the menu follows; the app never shows half a fade.
Core: no
Where: both
Automated: test/ui/splash_test.dart — back during the splash keeps it and never leaves the app

### T103 — The splash follows the phone's Remove animations
Steps:
- Turn on the phone's Remove animations (Settings → Accessibility → Visibility enhancements on One UI).
- Force stop the app and launch it.
Expected: The splash reaches READY and the menu appears with no fade.
Core: no
Where: both
Automated: test/ui/motion_test.dart — either off-switch turns motion off

## Menu

The menu is the first route and has no route name.

### T110 — The menu shows every entry
Steps:
- Clear the app's data (Settings → Apps → Honest Chess → Storage → Clear data) and launch it.
Expected: The menu shows the Honest mark, the wordmark "HonestChess", BY HONEST ARCADE · NO ADS, a "vs Computer" card ("Five strength steps · pick your colour"), a "Two players" card ("One phone, pass it across"), Statistics, How to play, Settings and About the app in a 2×2 grid, and an "About Honest Arcade" row reading "No ads, no tracking, open source." There is no Continue and no banner.
Core: no
Where: both
Automated: test/ui/menu_navigation_test.dart — the app opens on the menu: the header, every entry, no Continue

### T111 — Every menu entry opens its screen and back returns
Steps:
- Tap each of vs Computer, Two players, Statistics, How to play, Settings, About the app and About Honest Arcade in turn.
- After each, tap the screen's ‹ button, then repeat with the phone's back gesture.
Expected: Each opens its screen (New game vs computer, Two players, Statistics, How to play, Settings, About the App, About Honest Arcade), and both kinds of back return to the menu. The ‹ glyph fills its button (#165).
Core: yes
Where: both
Automated: test/ui/menu_navigation_test.dart

### T112 — Continue offers the last game played
Steps:
- Start a vs-computer game, make two moves, open the pause card and tap Main menu.
- Read the Continue button, then tap it.
Expected: Continue reads "Continue vs <step>" with the meta line "MOVE <n> · WHITE" (or BLACK, the side to move); tapping it opens the same game, paused on the pause card.
Core: yes
Where: both
Automated: test/ui/menu_navigation_test.dart; test/ui/resume_test.dart; integration_test/e2e_game_test.dart

### T113 — Continue prefers the mode played last
Steps:
- With a vs-computer game saved, start a two-player game, make one move and return to the menu with Main menu.
- Finish or resign the two-player game later and return to the menu.
Expected: Continue first reads "Continue two-player"; once that game is over it reads "Continue vs <step>" again, for the computer game that was kept.
Core: no
Where: both
Automated: test/data/game_saves_test.dart

### T114 — Back on the menu leaves the app
Steps:
- On the menu, press the phone's back.
- Launch the app again.
Expected: The app closes; on relaunch the splash and menu show and any saved game is still offered by Continue.
Core: no
Where: both
Automated: test/ui/menu_navigation_test.dart — back on the menu leaves the app, and the saved game survives

## vs Computer setup

route: csetup

### T201 — First-run defaults and copy
Steps:
- With fresh data, tap vs Computer on the menu.
Expected: The title reads "New game vs computer" with the kicker RUNS ON DEVICE · NO NETWORK; the Strength section is set to Club, Play as to White and Time control to Rapid 10+5. The step names and descriptions are easy to read (#167).
Core: no
Where: both
Automated: test/ui/computer_setup_test.dart — opens on the design text and first-time choices

### T202 — Every strength step says what it does
Steps:
- Tap each of the five steps in turn and read its description.
Expected: Each step shows its pips (one for Beginner up to five for Master) and exactly this description:
- Beginner: "Looks one move ahead and chooses loosely. On 20% of moves it blunders, giving away two pawns' worth or more, and it can miss mate in one."
- Casual: "Looks two moves ahead, a little loosely. On 20% of moves it blunders, giving away two pawns' worth or more."
- Club: "Looks two moves ahead and chooses carefully. On 10% of moves it blunders, giving away two pawns' worth or more."
- Strong: "Looks four moves ahead with no looseness. On 3% of moves it blunders, giving away two pawns' worth or more."
- Master: "Thinks deeply — up to about five seconds — with nothing held back."
Core: no
Where: both
Automated: test/ui/computer_setup_test.dart; test/guards/strength_honesty_test.dart

### T203 — Play as White, Black or Random
Steps:
- Choose White, Start game, return to the menu; repeat with Black, then with Random twice.
Expected: White puts your pieces at the bottom and you move first; Black puts Black at the bottom and the computer opens; Random picks a colour when Start is tapped (record which), and the board shows it.
Core: no
Where: both
Automated: test/ui/computer_setup_test.dart — Random draws White, then Black, and a rematch keeps it

### T204 — Every time control, and the custom steppers
Steps:
- Tap Untimed, Blitz 5+0, Rapid 10+5, Classical 30+0 and Custom in turn.
- With Custom chosen, hold − on Minutes per side until it stops, then + on Increment per move until it stops; then hold + on Minutes until it stops.
Expected: Custom shows two steppers and scrolls them into view. A held button steps after about 400 ms, then quickly, and stops at 1 min, 60 sec and 90 min; a button at its limit is dimmed and does nothing.
Core: no
Where: both
Automated: test/ui/computer_setup_test.dart — the steppers stop at 90 min and 60 sec

### T205 — Choices are kept
Steps:
- Pick Strong, Black and Custom 15+10; go back to the menu, force stop the app and relaunch.
- Open vs Computer.
Expected: Strong, Black and Custom 15+10 are still chosen.
Core: no
Where: both
Automated: test/data/settings_store_test.dart — every board field and setup choice survives a relaunch

### T206 — Starting over a live game warns, and Keep playing resumes
Steps:
- Start a vs-computer game and make one move; open the pause card, tap Main menu, then vs Computer.
- Read the text under Start game; tap Keep playing the current game.
- Return to the setup screen and tap Start game.
Expected: "Your current game will count as a loss." shows under Start game, with "Keep playing the current game". Keep playing opens the saved game on the board. Start game starts a new game and Statistics records one loss for the old one.
Core: no
Where: both
Automated: test/ui/computer_setup_test.dart — an unstarted computer game offers Keep playing, no warning; test/data/stats_listener_test.dart

## Two-player setup

route: psetup

### T210 — First-run defaults and copy
Steps:
- With fresh data, tap Two players on the menu.
Expected: The title reads "Two players" with the kicker ONE PHONE · PASS AND PLAY in violet, Time control is Rapid 10+5 with the note "Both clocks sit on the board, the running one lit.", Rotate board each turn is off, and the HOUSE RULES card reads "Takeback is shared — either player can undo the last move. Either player can agree a draw from the pause card with one tap. Everything else is tournament legal."
Core: no
Where: both
Automated: test/ui/two_player_setup_test.dart — opens on the design text and Rapid 10+5

### T211 — The rotate row and house rules follow Settings
Steps:
- Turn Rotate board each turn on here; open Settings from the menu and look at the same row.
- In Settings, turn Takeback allowed off and return to Two players.
Expected: The Settings row is on too (it is the same switch). The house rules now start "Takeback is off in Settings."
Core: no
Where: both
Automated: test/ui/two_player_setup_test.dart — the rotate switch is the Settings switch, both ways

### T212 — Every time control starts its clocks
Steps:
- Start a two-player game with each of Untimed, Blitz 5+0, Rapid 10+5, Classical 30+0 and Custom 90+60, returning to the menu between them.
Expected: Both panels show the chosen time (∞ untimed; 5:00, 10:00, 30:00, 90:00) and neither clock runs before White's first move.
Core: no
Where: both
Automated: test/ui/game/player_panel_test.dart; test/engine/clock_test.dart — each preset starts both sides on its minutes

## Board vs the computer

route: board

### T301 — The board at the start
Steps:
- Start a vs-computer game as White (R1's options).
Expected: The pause pill reads "❚❚ vs <step>", the status chip WHITE TO MOVE; your panel ("You", sub-line YOU · WHITE · <clock>) sits under the board and the computer's ("<step>", COMPUTER · BLACK · <clock>) above it; the tool row reads TAKEBACK, RESTART, RESIGN, NEW with Takeback dimmed. The pieces sit centred in their squares (#163) and the black pieces stand out on the dark squares (#164).
Core: yes
Where: both
Automated: test/ui/game/player_panel_test.dart — vs the computer as White: you below, Club above; test/ui/board/piece_centring_test.dart

### T302 — The computer answers, and says it is thinking
Steps:
- Play `e2e4`.
Expected: Your clock stops and the computer's runs; the chip reads THINKING… and the computer's name "<step> is thinking" until it moves; its move slides in, and the chip returns to WHITE TO MOVE. The screen stays responsive while it thinks.
Core: yes
Where: both
Automated: test/ui/game/computer_turns_test.dart; integration_test/app_smoke_test.dart — five moves against Beginner, frames flowing while it thinks

### T303 — Playing Black, the computer opens
Steps:
- Start a vs-computer game as Black (R2's options).
Expected: Black is at the bottom; the computer plays White's first move by itself and the clocks start only after that move.
Core: no
Where: both
Automated: test/ui/game/computer_turns_test.dart

### T304 — Each step's thinking time on the phone
Steps:
- In R1–R5, time three of the computer's middlegame replies with a stopwatch.
Expected: Replies take roughly the step's think time or less: about 0.3 s at Beginner, 0.6 s at Casual, 1 s at Club, 2 s at Strong and up to about 5 s at Master; in a timed game with little time left they are shorter, never longer. The measured figures are #112's to record.
Core: no
Where: phone
Automated: test/engine/computer_player_test.dart

### T305 — The clocks count down and warn
Steps:
- In R2 (Blitz 5+0), play until your clock is under 30 s, then under 10 s.
Expected: Your clock turns red below 30 s and shows tenths (0:09.4) below 10 s; the side to move's panel is lit and the other clock dimmed.
Core: no
Where: both
Automated: test/ui/game/player_panel_test.dart — red at 29.9 s and not at 30.0 s; test/ui/game/labels_test.dart — clock text rounds up, tenths under 10 s, ∞ untimed

### T306 — Takeback undoes your move and the reply
Steps:
- With Takeback allowed on, make three moves against the computer, then tap TAKEBACK.
- Turn Takeback allowed off in Settings (from the pause card) and start a new game.
Expected: TAKEBACK undoes the computer's reply and your last move together, and it is your turn. With the setting off, the next game's TAKEBACK stays dimmed and does nothing.
Core: yes
Where: both
Automated: test/ui/game/tool_row_test.dart — disabled with nothing to undo: tapping changes nothing; test/ui/settings_options_test.dart — takeback off applies from the next game, and back on too; integration_test/e2e_game_test.dart

### T307 — Restart and New
Steps:
- With a live game after one move of yours, tap RESTART.
- Make one move, then tap NEW.
Expected: Restart starts the same kind of game again, and "Your previous game counted as a loss." shows for about 3 s. New pauses the game and opens the vs Computer setup screen; back returns to the board, still paused.
Core: no
Where: both
Automated: test/ui/game_cards_navigation_test.dart — after your move: counted as a loss, and it says so for 3 s

### T308 — Resign ends the game at once
Steps:
- In a live game, tap RESIGN.
Expected: There is no confirmation: the result card shows YOU LOSE with "<your colour> resigned" (e.g. "White resigned").
Core: yes
Where: both
Automated: test/ui/game/result_overlay_test.dart — resignation vs the computer: YOU LOSE in red, at once; integration_test/e2e_game_test.dart

## Gestures

### T310 — Tap a piece, tap a square
Steps:
- Tap a knight, then tap one of its dotted squares.
- Tap a piece, then tap it again; tap a piece, then tap an empty square it cannot reach.
Expected: The selected piece gets a ring and every reachable square a dot (captures a ring); the move slides the knight there and marks both squares with a corner triangle. Tapping the piece again, or a square it cannot reach, puts it down with no move.
Core: yes
Where: both
Automated: test/ui/board/board_interaction_test.dart — dots on quiet targets and rings on captures, and only; integration_test/e2e_game_test.dart

### T311 — Drag a piece
Steps:
- Drag a pawn two squares forward and let go.
- Drag a piece to a square it cannot reach, and another off the board.
Expected: The piece lifts above your finger, larger, and lands where dropped. An illegal or off-board drop springs back to its square and nothing moves.
Core: yes
Where: both
Automated: test/ui/board/board_interaction_test.dart — a drop off the board springs back and changes nothing; integration_test/e2e_game_test.dart

### T312 — An illegal tap is refused with a tick
Steps:
- With Haptics on, tap your bishop behind its own pawns, then tap a square it cannot reach.
Expected: Nothing moves, and the phone gives one short tick.
Core: no
Where: phone
Automated: test/feedback/haptics_test.dart — a tap on a square the piece cannot reach ticks once

### T313 — Castling by tapping the king
Steps:
- Play the castling sequence as two players (`e2e4 e7e5 g1f3 b8c6 f1c4 f8c5`), tap the king, then tap g1.
Expected: The king lands on g1 and the rook on f1 in one move; the castle sound plays.
Core: no
Where: both
Automated: test/ui/board/board_interaction_test.dart

### T314 — En passant
Steps:
- As two players, play `e2e4 a7a6 e4e5 d7d5`, then move the e5 pawn to d6.
Expected: The d5 pawn is taken and leaves the board; the capture sound plays.
Core: no
Where: both
Automated: test/a11y/move_speech_test.dart

### T315 — Captures, by you and by the computer
Steps:
- In R3, capture a piece, and let the computer capture one.
Expected: The captured piece fades as the capturer slides in; the capture sound plays and the phone ticks once for each capture, yours and the computer's.
Core: no
Where: phone
Automated: test/feedback/game_feedback_test.dart — each move plays its one clip; mate plays one end

### T316 — Check is shown on the king
Steps:
- With Flag check on the board on, as two players, play the check sequence.
- Turn Flag check on the board off and repeat.
Expected: The checked king's square gets a red "!" badge in its top-right corner and the chip reads "<colour> IN CHECK"; the check sound plays. With the setting off there is no badge (the chip still says it).
Core: no
Where: both
Automated: test/ui/board_shapes_test.dart; test/ui/game/labels_test.dart — status chip priority: ending > thinking > check > to move

### T317 — Beginner is beatable
Steps:
- In R1, play a whole game against Beginner as a decent club player would.
Expected: The computer blunders material now and then and can be beaten; the owner no longer "keeps getting destroyed on easy" (the finding behind #159).
Core: no
Where: phone
Automated: test/guards/strength_honesty_test.dart

### T318 — Every step plays a full game to its end
Steps:
- In each of R1–R5, play the game to its end (mate, resignation, a draw or a fallen flag).
Expected: The computer only ever plays legal moves, never resigns, and each game reaches a result card.
Core: no
Where: phone
Automated: test/engine/search_test.dart

## Two-player board

route: board

### T401 — The two-player board at the start
Steps:
- Start a two-player game (R7's options).
Expected: The pause pill reads "❚❚ Two players"; the panels read White (PLAYER ONE · WHITE · <clock>) at the bottom and Black (PLAYER TWO · BLACK · <clock>) at the top; the chip reads WHITE TO MOVE.
Core: yes
Where: both
Automated: test/ui/game/player_panel_test.dart

### T402 — Rotate board each turn
Steps:
- In R6 (rotate on), play `e2e4`, then `e7e5`.
- In R7 (rotate off), play the same two moves.
Expected: With rotate on the board turns so the side to move is at the bottom after each move; with it off White stays at the bottom throughout.
Core: no
Where: both
Automated: test/ui/board_view_test.dart; test/ui/settings_options_test.dart

### T403 — Fool's mate by drag
Steps:
- Play fool's mate (`f2f3 e7e5 g2g4 d8h4`) by dragging every piece.
Expected: After `d8h4` the result card shows BLACK WINS with "Black delivers checkmate"; the end sound plays and not the check sound.
Core: yes
Where: both
Automated: integration_test/talkback_game_test.dart; test/feedback/sound_priority_test.dart — a mate plays only the end, not the check; integration_test/e2e_game_test.dart

### T404 — Clocks for two
Steps:
- In R6 (custom 90+60), make four moves each, noting the clocks.
Expected: Each side's clock runs only on its turn, and each move adds 60 s to the mover's clock.
Core: no
Where: both
Automated: test/engine/clock_test.dart

### T405 — Takeback, resign and the draw between two
Steps:
- In R7 with Takeback allowed on, play two moves and tap TAKEBACK.
- Tap RESIGN.
Expected: TAKEBACK undoes only the last move. RESIGN ends the game at once for the side to move, and the card names the other side as winner.
Core: no
Where: both
Automated: test/ui/game/tool_row_test.dart — two players: the side to move resigns at once

### T406 — Stalemate and repetition
Steps:
- Play the stalemate-in-ten sequence; then start a new two-player game and play the repetition sequence.
Expected: The first ends with DRAWN, "Stalemate — no legal move"; the second with DRAWN, "Draw by repetition". Insufficient material and the fifty-move rule take too long to reach by hand; their wording is checked by test only.
Core: no
Where: both
Automated: test/ui/game/result_text_test.dart — every ending is worded

### T407 — Rematch keeps the setup
Steps:
- After T403's mate, tap Rematch.
Expected: A fresh two-player game starts with the same clock and the same rotate behaviour.
Core: yes
Where: both
Automated: test/ui/game/result_overlay_test.dart; integration_test/e2e_game_test.dart

## Promotion card

### T501 — The promotion card, 2×2
Steps:
- As two players, play the promotion sequence, then move the b7 pawn to b8.
Expected: A card reads "Promote to" with PAWN TO B8, and the choices sit two by two: QUEEN and ROOK on top, BISHOP and KNIGHT below, each a large piece in the pawn's colour and the chosen piece style with its name under it (#162).
Core: no
Where: both
Automated: test/ui/promotion_sheet_test.dart

### T502 — Each choice promotes to that piece
Steps:
- Repeat T501 four times, choosing a different piece each time, once by taking on a8 (`b7a8`) instead of pushing.
Expected: The pawn becomes the chosen piece on its square; the capturing promotion takes the rook too.
Core: no
Where: both
Automated: test/ui/promotion_sheet_test.dart

### T503 — Cancelling a promotion
Steps:
- Bring up the promotion card and tap outside it; bring it up again and press back.
Expected: Each time the card closes and the pawn is still on b7, with nothing moved.
Core: no
Where: both
Automated: test/ui/promotion_sheet_test.dart — a tap on the scrim cancels

### T504 — Auto-promote to queen
Steps:
- Turn Auto-promote to queen on and play the promotion sequence to b8 again.
Expected: No card appears: the pawn becomes a queen at once.
Core: no
Where: both
Automated: test/ui/game/game_controller_test.dart

## Pause card

### T520 — The pause card
Steps:
- In a live vs-computer game at move 5 or later, tap the pause pill.
Expected: A card reads "Paused" with the meta line "VS <STEP> · <CLOCK> · MOVE <n>" and the buttons Resume, Claim a draw, Resign, Rules and Settings side by side, and Main menu. Both clocks stop.
Core: yes
Where: both
Automated: test/ui/game/pause_overlay_test.dart — Resume, the draw, Resign, Rules, Settings and Main menu

### T521 — Resume, the scrim and back
Steps:
- Tap Resume. Pause again and tap the dimmed board around the card. Pause again and press back.
- On a live board with no card, press back.
Expected: Each of Resume, the scrim tap and back resumes play with the clocks running from where they stopped. Back on a live board with no card pauses it; it never leaves the board.
Core: no
Where: both
Automated: test/ui/game_cards_navigation_test.dart — a live game: the pause card, then back resumes; never a pop

### T522 — Leaving the app pauses
Steps:
- In a timed live game, press Home, wait 10 s and return.
Expected: The pause card shows and the clocks lost no time while the app was away.
Core: no
Where: both
Automated: test/ui/game/pause_overlay_test.dart

### T523 — Rules and Settings from the pause card
Steps:
- Tap Rules; press back. Tap Settings; change the board colour; press back.
Expected: Rules opens How to play on The rules; Settings opens Settings; back returns to the board, still paused, with the new board colour applied.
Core: no
Where: both
Automated: test/ui/game_cards_navigation_test.dart

### T524 — Main menu keeps the game
Steps:
- Tap Main menu on the pause card.
Expected: The menu shows Continue for the game; nothing is counted in Statistics.
Core: yes
Where: both
Automated: test/ui/game_cards_navigation_test.dart

### T525 — A draw between two players
Steps:
- In a two-player game after one move each, pause and tap Agree a draw.
- In a fresh two-player game, pause before any move.
Expected: One tap ends the game DRAWN, "Draw agreed". Before each side has moved, the button is unavailable with the hint "After both sides have moved".
Core: no
Where: both
Automated: test/ui/game/pause_overlay_test.dart — Agree a draw is unavailable until each side has moved

## Declined-draw card

### T530 — The computer declines a draw
Steps:
- Against Strong or Master, play until you are clearly behind (a piece down), pause and tap Claim a draw.
Expected: The draw button shows a spinner while the computer answers, and nothing else on the card can be tapped. Then the pause card is replaced by a card that says only "<step> declined the draw" and a Resume button (#160). Tapping outside it and pressing back do nothing; Resume returns to play with the clocks running.
Core: no
Where: both
Automated: test/ui/game/pause_overlay_test.dart — declined: a card saying so, and play waits for its Resume; test/ui/game_cards_navigation_test.dart — the declined-draw card leads nowhere but back to play

### T531 — One offer per move, and an accepted draw
Steps:
- After T530, pause again before moving.
- Move, then pause and claim a draw from a level position against Beginner.
Expected: Before your next move the draw button is unavailable with "After your next move". From a level position the computer accepts and the game ends DRAWN, "Draw agreed".
Core: no
Where: both
Automated: test/ui/game/pause_overlay_test.dart; test/engine/strength_test.dart

## Result card

### T540 — Winning against the computer
Steps:
- Checkmate the computer (easiest in R1 against Beginner).
Expected: About half a second after the mating move the card rises with a large, bold YOU WIN centred at its top (#161), "You deliver checkmate" (or the colour's name), the body sentence, and the stats MOVES, CAPTURES, LEVEL and TIME LEFT; the end sound plays.
Core: yes
Where: both
Automated: test/ui/game/result_overlay_test.dart

### T541 — Losing, and the loss tag
Steps:
- Resign a game against the computer (or be mated).
Expected: The card shows YOU LOSE in red, large and centred; the body explains the ending.
Core: yes
Where: both
Automated: test/ui/game/result_overlay_test.dart — resignation vs the computer: YOU LOSE in red, at once; integration_test/e2e_game_test.dart

### T542 — The result card's buttons
Steps:
- On a result card, tap each of Rematch, View board, See statistics and Main menu (returning to a result card between them).
Expected: Rematch starts the same game again; View board shows the final position under the result bar; See statistics opens Statistics on this game's tab; Main menu returns to the menu with no Continue for the finished game.
Core: yes
Where: both
Automated: test/ui/game_cards_navigation_test.dart; integration_test/e2e_game_test.dart

### T543 — Two players' result tags
Steps:
- Finish a two-player game with each side winning once and one draw.
Expected: The tags read WHITE WINS, BLACK WINS and DRAWN, each large and centred; the stats show CLOCK instead of LEVEL.
Core: no
Where: both
Automated: test/ui/game/result_overlay_test.dart

### T544 — Back on the result card
Steps:
- On a result card, press back.
Expected: Back does what View board does.
Core: no
Where: both
Automated: test/ui/game/result_overlay_test.dart — Android back does what View board does

### T546 — The flag falls
Steps:
- In R5 (Master, custom 1+0), let your clock run out.
Expected: When your clock reaches 0:00.0 the game ends at once: YOU LOSE, "You ran out of time" (or the colour's name), and TIME LEFT reads 0:00. If the computer had no mating material the game is drawn instead.
Core: no
Where: both
Automated: test/ui/game/result_text_test.dart

## View board

### T550 — View board and the result bar
Steps:
- On a result card, tap View board.
Expected: The card closes; the final position stays, frozen, with the result bar (tag and title, and a Rematch button) in place of the top bar; the tool row still works.
Core: no
Where: both
Automated: test/ui/game/result_overlay_test.dart — View board leaves the bar over the frozen final board

### T551 — The bar brings the card back, and Rematch
Steps:
- Tap the bar's tag or title; tap View board again; tap the bar's Rematch.
Expected: The tag brings the result card back; Rematch starts the same game again.
Core: no
Where: both
Automated: test/ui/game/result_overlay_test.dart — Rematch from the bar starts the same game again

### T552 — Back from View board, and Takeback reopens
Steps:
- In View board, press back.
- Finish another game, tap View board, then TAKEBACK.
Expected: Back goes to the menu, and the game is counted once. TAKEBACK reopens the game one move earlier and play continues.
Core: no
Where: both
Automated: test/ui/game_cards_navigation_test.dart — a finished game: View board, then the menu, counted once

## Statistics

route: stats

### T601 — Empty statistics
Steps:
- With fresh data, open Statistics from the menu.
Expected: The title is "Statistics" with the tabs vs Computer and Two players; every value is "—", GAMES PLAYED reads "Since install", and the BY STRENGTH rows read "0 / 0 · —" with empty bars.
Core: no
Where: both
Automated: test/ui/stats_screen_test.dart

### T602 — Records after play
Steps:
- Win one game and lose one against the computer at different steps; finish one two-player game; open Statistics.
Expected: vs Computer shows GAMES PLAYED 2, WIN RATE 50% "1 won", a CURRENT STREAK and USUAL LEVEL, and BY STRENGTH rows for the two steps; Two players shows GAMES PLAYED 1 with the winner's card at 100% and the game's row BY TIME CONTROL.
Core: yes
Where: both
Automated: test/ui/content/stats_view_test.dart; test/data/stats_test.dart; integration_test/e2e_game_test.dart

### T603 — What counts as a game
Steps:
- Start a vs-computer game and go back to the menu without moving; then start another, move once and tap RESTART.
- Start a two-player game, move once and start a new one.
Expected: The computer game with no move of yours counts nothing; the one with a move counts one loss. The unfinished two-player game counts nothing.
Core: no
Where: both
Automated: test/data/stats_listener_test.dart — one move, then Restart: played 1, lost 1, streak 0

### T604 — Reset statistics
Steps:
- Tap Reset statistics; tap Cancel. Tap it again; tap Reset.
Expected: The confirmation reads "Reset statistics?" with its body and Cancel and Reset; Cancel keeps every number; Reset clears both tabs, and GAMES PLAYED then reads "Since reset".
Core: no
Where: both
Automated: test/ui/stats_screen_test.dart — a failed reset keeps the numbers; the retry clears them

### T605 — Statistics opens on the game's tab
Steps:
- Finish a two-player game and tap See statistics.
Expected: Statistics opens on the Two players tab.
Core: no
Where: both
Automated: test/ui/game_cards_navigation_test.dart

### T606 — A custom clock that matches a preset
Steps:
- Finish a two-player game on Custom 5+0; open Statistics → Two players.
Expected: The game is counted under Blitz 5+0, not Custom.
Core: no
Where: both
Automated: test/ui/content/stats_view_test.dart

## Settings

route: settings

### T701 — The Settings screen
Steps:
- Open Settings from the menu and scroll to the end.
Expected: Board colour (NAVY, TEAL, VIOLET, BONE), Piece style (CLASSIC, OUTLINE, FLAT) and Board surface (PLAIN, FELT, WOOD), then the PLAY switches and the Computer's minimum turn slider, the DISPLAY and SOUND switches, the note STORED ON THIS PHONE, and the version line `v<name> · BUILD <code>`.
Core: no
Where: both
Automated: test/ui/settings_look_test.dart; test/ui/settings_options_test.dart

### T702 — Board colour, piece style and surface apply at once
Steps:
- With a game saved, change each of the three in turn and open the board after each.
Expected: The board shows each change at once; the game itself is unchanged.
Core: no
Where: both
Automated: test/ui/settings_look_test.dart — each board colour applies at once and changes nothing else

### T703 — Back from Settings returns where it was opened
Steps:
- Open Settings from the menu and go back; open it from the pause card and go back.
Expected: Back returns to the menu the first time and to the paused board the second.
Core: no
Where: both
Automated: test/ui/game_cards_navigation_test.dart

### T710 — Legal-move dots
Steps:
- Turn Legal-move dots off; select a piece on the board. Turn it on again.
Expected: Off, no dots appear (capture rings still do); on, the dots return.
Core: no
Where: both
Automated: test/ui/settings_options_test.dart

### T711 — Last-move highlight
Steps:
- Turn Last-move highlight off and make a move; turn it on and make another.
Expected: Off, no corner marks after a move; on, both squares of the last move are marked.
Core: no
Where: both
Automated: test/ui/settings_options_test.dart

### T712 — Takeback allowed, and the next-game note
Steps:
- In a live game, open Settings from the pause card and turn Takeback allowed off.
Expected: Its description changes to "Applies from your next game."; the current game keeps its TAKEBACK, and the next game's is dimmed.
Core: no
Where: both
Automated: test/ui/settings_options_test.dart — takeback off applies from the next game, and back on too

### T713 — Auto-promote to queen
Steps:
- Run T504.
Expected: As T504.
Core: no
Where: both
Automated: test/ui/settings_options_test.dart

### T714 — Rotate board each turn
Steps:
- Run T402 with the Settings row switched rather than the setup screen's.
Expected: As T402; against the computer the board never rotates.
Core: no
Where: both
Automated: test/ui/settings_options_test.dart

### T715 — Piece animations
Steps:
- Turn Piece animations off and make moves, including a drop that springs back.
Expected: Pieces jump to their squares with no slide and no spring-back flight; turning it on restores both.
Core: no
Where: both
Automated: test/ui/move_animation_test.dart; test/ui/motion_test.dart

### T716 — Flag check on the board
Steps:
- Run T316 with the setting on, then off.
Expected: As T316.
Core: no
Where: both
Automated: test/ui/board_shapes_test.dart

### T717 — Computer's minimum turn
Steps:
- In Settings, read the Computer's minimum turn slider under PLAY; slide it to 3 s.
- Start an untimed game against Beginner and play a few moves.
- Set it to 5 s; start a Custom 1+0 game and play quickly until the computer's clock is under 5 s.
- With TalkBack on, swipe to the slider and swipe up and down on it.
Expected: It reads Off by default, steps Off, 1 s … 5 s, and keeps its value after Force stop. At 3 s every reply shows THINKING… for at least 3 s; the moves are no weaker or different in kind. In a timed game the wait runs on the computer's clock, and once its clock is too low for the wait it replies within the usual moment rather than lose on time. TalkBack reads "Computer's minimum turn", its description and "Off" or "3 seconds", and changes it a step at a time.
Core: no
Where: both
Automated: test/ui/settings_options_test.dart; test/ui/game/computer_turns_test.dart — at 3 s no move appears before 3 s, thinking all the while; test/data/settings_store_test.dart

### T720 — Sound effects
Steps:
- Turn Sound effects off, then on.
Expected: Turning it on plays a sample; with it off no move makes a sound.
Core: no
Where: phone
Automated: test/ui/settings_options_test.dart; test/feedback/game_feedback_test.dart

### T721 — Background music
Steps:
- Turn Background music on and open a live game; turn it off.
Expected: A quiet loop plays on the board; turning it off stops it.
Core: no
Where: phone
Automated: test/feedback/game_feedback_test.dart — never starts with Background music off

### T722 — Haptics
Steps:
- Turn Haptics off, then on.
Expected: Turning it on gives a sample tick; with it off, captures and refused taps give no tick.
Core: no
Where: phone
Automated: test/feedback/haptics_test.dart

## How to play

route: howto

### T801 — Both tabs and the gestures
Steps:
- Open How to play from the menu; read The pieces, then tap The rules and scroll to the end.
Expected: The pieces shows cards for King, Queen, Rook, Bishop, Knight and Pawn; The rules shows THE GOAL, CHECK, DRAWS, THE CLOCK and TAKEBACK, then GESTURES (TAP, TAP AGAIN, TAP KING, DRAG, UNDO, PAUSE).
Core: no
Where: both
Automated: test/ui/how_to_play_test.dart — opens on The pieces by default, and only there

### T802 — The rules state what the game plays
Steps:
- Read THE CLOCK and DRAWS against T404, T406 and T546.
Expected: The text matches the play: the clocks start after White's first move, and a flag against a side with no mating material is a draw.
Core: no
Where: both
Automated: test/ui/content/rules_text_test.dart

## About the App

route: aboutapp

### T810 — The About the App screen
Steps:
- Open About the app from the menu and scroll to the end.
Expected: Honest Chess with "v<name> · OFFLINE", the description, WHAT'S IN IT (six features), THE HONEST PROMISES chips (NO ADS, NO TRACKING, NO ACCOUNTS, NO PURCHASES, NO PERMISSIONS, OPEN SOURCE, WORKS OFFLINE), and MADE BY with its two links side by side (#166).
Core: no
Where: both
Automated: test/ui/about_app_test.dart — the version line reads v<name> · OFFLINE

### T811 — About the App's links
Steps:
- Tap HONEST ARCADE ↗, return; tap SOURCE ON GITHUB ↗, return; tap Honest Arcade Promises.
Expected: The browser opens https://honestarcade.app and then https://github.com/honestarcade/HonestChess; the promises button opens About Honest Arcade.
Core: no
Where: both
Automated: test/ui/about_app_test.dart

## About Honest Arcade

route: aboutstudio

### T820 — The About Honest Arcade screen
Steps:
- Open About Honest Arcade from the menu and scroll to the end.
Expected: The mark, the two paragraphs, the SUPPORT HONEST ARCADE card, OUR PROMISES (seven entries) with NO ADS, NO TRACKING, OPEN SOURCE chips, and two links.
Core: no
Where: both
Automated: test/ui/about_arcade_test.dart — the header, the mark and the two paragraphs

### T821 — Support and site links
Steps:
- Tap honestarcade.app/contribute →, return; tap HONESTARCADE.APP ↗, return; tap SOURCE ON GITHUB ↗.
Expected: The browser opens https://honestarcade.app/contribute, https://honestarcade.app and https://github.com/honestarcade; returning keeps the screen's scroll position.
Core: no
Where: both
Automated: test/ui/about_arcade_test.dart

### T822 — No browser
Steps:
- On the `emu-api34` emulator, disable every browser (adb `pm disable-user` on each) and tap a link.
Expected: A snackbar reads "No browser found" and nothing else happens.
Core: no
Where: emulator
Automated: test/ui/widgets/external_link_test.dart — a refused open shows "No browser found" and nothing else

## Persistence

### T901 — A computer game survives a swipe-away
Steps:
- Make five moves in a timed vs-computer game, then swipe the app away.
- Launch it and tap Continue.
Expected: The same position, clocks and step come back, paused on the pause card; the computer moves only after Resume.
Core: yes
Where: both
Automated: test/ui/resume_test.dart — a restored game waits, paused, for Resume; then the computer moves; integration_test/e2e_game_test.dart

### T902 — A two-player game survives a force stop
Steps:
- Make four moves in a two-player game, force stop the app, launch it and tap Continue.
Expected: The same position and clocks come back, paused.
Core: no
Where: both
Automated: test/data/game_saves_test.dart

### T903 — Both saved games are kept
Steps:
- Leave a vs-computer game and a two-player game unfinished (Main menu on each); force stop and relaunch.
Expected: Continue offers the one played last; after finishing it, Continue offers the other.
Core: no
Where: both
Automated: test/data/game_saves_test.dart

### T904 — Settings and setup choices survive
Steps:
- Change the board colour, piece style, surface and three switches; force stop and relaunch.
Expected: Every change is still in place.
Core: no
Where: both
Automated: test/data/settings_store_test.dart — every board field and setup choice survives a relaunch

### T905 — Statistics survive, and a restart counts nothing twice
Steps:
- Note the Statistics, force stop and relaunch, and read them again.
Expected: The same numbers; a game finished before the stop is counted once.
Core: yes
Where: both
Automated: test/data/stats_test.dart; integration_test/e2e_game_test.dart

### T906 — A finished game is not offered
Steps:
- Finish a game, force stop and relaunch.
Expected: The menu offers no Continue for it.
Core: no
Where: both
Automated: test/data/game_saves_test.dart

### T910 — A damaged file raises the banner
Steps:
- On a debug build on `emu-api34`, save a game, then run `adb shell run-as com.honestarcade.chess sh -c 'echo "{" > files/data/stats.json'` and force stop.
- Launch the app; tap Dismiss; force stop and launch again.
Expected: The menu shows "Some saved data couldn't be read. The app started fresh for it." with Dismiss; Statistics starts from zero and the damaged copy is kept beside it as `stats.bad-<time>.json`; the saved game is still offered. After Dismiss the banner does not return.
Core: no
Where: emulator
Automated: test/data/app_store_test.dart; test/ui/menu_navigation_test.dart — the banner shows for a damaged document, announced, and stays dismissed

## Feedback

### T950 — Each sound
Steps:
- With Sound effects on and the phone's media volume up, play a quiet move, a capture, castling, a check and a mate.
Expected: Each plays its own sound (move, capture, castle, check, end); a mate plays only the end sound; the check sound is as audible as the others.
Core: no
Where: phone
Automated: test/feedback/sound_priority_test.dart; integration_test/sound_bridge_test.dart

### T951 — Sound effects off is silent
Steps:
- In R2 (Sound effects off), play ten moves including a capture.
Expected: No sound at all.
Core: no
Where: phone
Automated: test/feedback/game_feedback_test.dart

### T952 — Background music follows the board
Steps:
- In R3 (music on), start a game; pause; resume; open the menu; return with Continue; press Home and return.
Expected: The loop plays only on a live, unpaused board with the app in front; it pauses on the pause card, the menu and Home, and resumes where it left off.
Core: no
Where: phone
Automated: test/feedback/game_feedback_test.dart

### T953 — Music never plays over another app's audio
Steps:
- Start a podcast or music app, then open a live game with Background music on.
Expected: The game's music does not start over the other audio; the game's sound effects still play.
Core: no
Where: phone
Automated: integration_test/sound_bridge_test.dart

### T954 — The loop does not stall
Steps:
- Leave the music playing on a live, untimed board for three minutes.
Expected: The loop repeats with no gap or click.
Core: no
Where: phone
Automated: none

### T955 — Haptics
Steps:
- With Haptics on, capture, let the computer capture, and tap an illegal square.
Expected: One short tick for each; a quiet move or a selection gives none.
Core: no
Where: phone
Automated: test/feedback/haptics_test.dart

### T956 — Haptics off
Steps:
- In R2 (Haptics off), repeat T955.
Expected: No ticks.
Core: no
Where: phone
Automated: test/feedback/haptics_test.dart

### T957 — Piece animations and the phone's Remove animations
Steps:
- With Piece animations on, turn on the phone's Remove animations and play moves; open and close the pause and result cards.
Expected: Pieces jump with no slide, and the cards appear with no rise or fade; the result card still waits about half a second after a mating move.
Core: no
Where: both
Automated: test/ui/motion_test.dart — either off-switch turns motion off

### T960 — TalkBack play
Steps:
- Turn on TalkBack. From the splash, reach the menu, start a two-player game and play fool's mate by double-tapping squares.
Expected: Every control is read with a label and role; each square reads like "e4, empty" or "e2, white pawn"; each move, the check and "Black wins. Black delivers checkmate." are spoken; the controls behind an open card cannot be reached.
Core: no
Where: phone
Automated: integration_test/talkback_game_test.dart — fool's mate through semantics actions, spoken to the end; test/a11y/labels_test.dart

### T961 — The largest font
Steps:
- Set the phone's font size to its largest and open every screen and card.
Expected: Text scales and nothing is cut off; the board, clocks and pieces keep their size; the game screen does not scroll.
Core: no
Where: both
Automated: test/ui/large_text_test.dart

### T962 — Greyscale
Steps:
- Turn on the phone's greyscale (colour correction) and play a few moves on the plain and wood surfaces.
Expected: Rings, dots, capture rings, corner marks, the check badge and both piece colours stay distinguishable.
Core: no
Where: phone
Automated: test/ui/contrast_screens_test.dart; test/guards/contrast_test.dart

## Filing a bug

A failed check is filed as a GitHub issue in the M6 milestone with the
label `bug`, exactly one `sev:*` label and the story it concerns
referenced, and its number goes in the run record's `bug` column. The agent
assigns the severity by the owner's rule (/n8-plan M6 round one,
2026-09-28); only the owner changes it:

- **critical** — a crash, a lost game or lost statistics, an unfinishable game;
- **high** — misleads or blocks play, or visibly breaks the design on the S26;
- **medium** — noticeable but harmless;
- **low** — polish.

Every critical and high bug is fixed with a test that failed first (or a
written manual check here that failed first); a medium or low one is fixed
or carried with the owner's OK. Only blocking bugs get a new release
candidate on the phone.
