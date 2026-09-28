# Decisions

A dated, append-only narrative of choices made during planning and execution
-- not a source of current counts or facts. If a sentence here would state a
number or a status that a command could compute, prefer the command; a
narrative entry is a record of *why*, not a live dashboard. (See
CLAUDE.md's note on the same rule.)

Entries are appended by `/n8-exec`, `/n8-replan`, and any session that makes
a decision outside those commands (a project's `CLAUDE.md` should carry the
standing instruction to log here; `/n8-init` writes it).

Format:

```markdown
## /n8-exec M1 -- 2026-08-27

- **Decision:** <what was chosen>
  **Why:** <the reasoning>
  **Issue:** <#N>
```

Ad-hoc entries (decisions made outside a planning/execution command) use:

```markdown
## Ad-hoc -- 2026-08-27

- **Change:** <what changed>
  **Why:** <the reasoning>
  **Affects:** <milestones/issues likely affected>
```

## /n8-init — 2026-09-27

- **Decision:** Package id `com.honestarcade.chess`, label "Honest Chess", Dart package `honest_chess`, slug `honestchess` (keystore files and Cloud project `honestchess-ci`), minSdk 24, portrait only, Android only.
  **Why:** The studio's naming, as for Solitaire and Sudoku; one slug for both keys because the template's `rename_app.py` uses one.
  **Issue:** #1
- **Decision:** Template applied from `honestarcade/android-studio-app-template` `origin/main` by `git archive`, not by clone, so the new repository starts with its own history.
  **Why:** The template's history is not this app's.
  **Issue:** #1

## /n8-roadmap — 2026-09-27

- **Decision:** Rules scope is FIDE Laws of Chess 2023, Basic Rules (Arts. 1–5) plus 6.9 and 9; threefold repetition and the fifty-move rule end the game automatically; dead-position detection is limited to insufficient material; arbiter procedure is out.
  **Why:** Owner's answer to the totalising "full rule set" question; the design's prototype had no repetition rule at all.
  **Issue:** #3, milestone M2
- **Decision:** The computer is our own pure-Dart engine in an isolate, not Stockfish.
  **Why:** Owner's choice: no dependencies, no native code, no GPL obligation; Master targets roughly 1800–2000.
  **Issue:** #4
- **Decision:** Move list, captured-piece tray, puzzles and landscape tablet layout are post-v1.
  **Why:** Owner selected none of the design's "next" items for v1.
  **Issue:** #12
- **Decision:** Milestones follow Honest Solitaire's shape (M0 infrastructure, M1 CI, M2 engine, M3 board, M4 screens/persistence, M5 brand/accessibility, M6 testing, M7 launch, M8 audit), with the engine and computer as two epics in one milestone.
  **Why:** The shape carried two apps to a release; the computer is chess's counterpart of Solitaire's solver.
  **Issue:** #1–#11
- **Decision:** The Audit milestone has no epic of its own; findings attach to the epic they concern.
  **Why:** The n8SDLC convention (Solitaire had an audit epic; this app does not).
  **Issue:** M8

## /n8-plan M0,M1 — 2026-09-27

- **Decision:** M0 is six stories (#14 identity and placeholder, #15 upload key, #16 invariant 1–2 guards, #17 privacy/licence/security, #18 launcher icon, #19 gate and battery) and M1 three (#20 PR gate, #21 Play Console and secrets, #22 v0.1.0 to internal), following Honest Solitaire's M0/M1 shape on the template that absorbed Solitaire's fix passes.
  **Why:** The template already carries the guards, gate, battery and workflows; these milestones apply and prove them for Honest Chess.
  **Issue:** #1, #2
- **Decision:** The dependency blocklist widens to network clients, attribution, crash reporting, push and remote config.
  **Why:** Owner, round two ("Widen it"): invariant 1's "no network" read as a package policy, not only a permission policy.
  **Issue:** #16
- **Decision:** The launcher icon moves from M5 (epic #8) to M0 (epic #1, story #18).
  **Why:** Owner, round two: "Real icon now", so v0.1.0 on the internal track looks like Honest Chess.
  **Issue:** #18, #1, #8
- **Decision:** Play App Signing uses a Google-generated app signing key; the owner backs the upload keystore up into the password manager.
  **Why:** Owner, round two; the same choice as Honest Solitaire.
  **Issue:** #15, #22
- **Decision:** The release version code stays CI-computed (1000 + run×10 + attempt) and `release.yml` stays the template's; no tag-equals-pubspec check.
  **Why:** Pass-1 simulation found the draft's "version code 1" contradicted `tools/ci_version.sh`; the template's formula lets a failed release re-run.
  **Issue:** #22
- **Decision:** Integration tests (`integration_test`) are deferred to M6 and epic #10 gains the criterion.
  **Why:** The coverage check found them unowned; M0/M1 have no game to drive, and Solitaire's M6 carried the same scripted end-to-end game.
  **Issue:** #10
- **Decision:** The second executor-simulation pass ran as a background Workflow rather than individual subagent calls.
  **Why:** An orchestration slip — the owner had not opted into workflows; the pass itself is the one the plan requires.
  **Issue:** #14–#22

## /n8-exec M0 — 2026-09-27

- **Decision:** The Honest Chess upload keystore was generated with `tools/make_upload_key.sh` (dname `O=Honest Arcade, CN=Honest Chess`, SHA-256 `41:84:0F:…:AB:4C` — full value in `android/signing/README.md`), password from `openssl rand -base64 33`, never printed.
  **Why:** Owner's answer at /n8-init: generate it now; before enrolment regeneration is harmless, after it the key is the app's identity.
  **Issue:** #15
- **Decision:** The fingerprint guard hashes the certificate with a SHA-256 written in `test/guards/sha256.dart` (checked against FIPS 180-4 vectors), not a package or a `keytool` subprocess.
  **Why:** Invariant 2 (no new package for a test helper), and a JVM start-up per run would push the guard into the `slow` set.
  **Issue:** #15
- **Decision:** Removing the PEM from `references_test.dart`'s `createdLater` broke that guard's own "files that exist pass" fixture; the fixture's existing-set now names the PEM instead of restoring the exemption (Rule 3).
  **Why:** The exemption was for fresh clones of the template; this repository has the file.
  **Issue:** #15
