# Honest Chess

Flutter app (Dart) for Android, built on
`honestarcade/android-studio-app-template`. Build with `flutter pub get && flutter run`.

The quality gate is **`tools/gate.sh`** — one command running the six steps CI
runs, in order: dependencies against the lockfile, `dart analyze --fatal-infos`,
format check, `flutter test` (which includes the invariant guards below), the
release bundle build, and `tools/check_aab.sh` over that bundle. It must print
`GATE PASSED` before anything is considered done.

CI runs one more thing the gate does not: **`tools/mutation_check.py`**, its own
job, which reintroduces every known defect one at a time and requires the guard
suite to catch each — naming the assertion that must fire, so a mutation that
merely turns the suite red some other way is reported as WRONG-REASON rather
than a pass. It refuses to run on a dirty tree and restores through a
`try/finally`. Run it locally before changing a guard: a guard weakened by
accident is the failure that mechanism exists to catch, and a green suite is
not evidence that the suite can fail. **Adding a guard means adding its
mutation.**

A comment may say *why*. A claim about what the code does *now* belongs in the
`reason:` of an assertion, where it is executed; a claim about anything else —
history, a measurement, another tool's output, a count — carries a date and a
source in the same sentence, or is cut. Neither half is optional: a `reason:`
cannot hold a fact about history or a measurement, and a sentence with no date
and no source is the one nothing re-reads. Where a count can be computed, cut
it and name the command instead. When a change is reverted or narrowed, the
comments it added are part of the revert.

This rule is carried over from Honest Sudoku, where repeated verification
rounds found new violations of it — including inside the very passes meant to
fix the previous violations. Treat it as a standing hazard on any project, not
a one-time cleanup. The one thing that reliably worked there: moving a claim
into something executed rather than into a better-written sentence — see
`test/guards/dependency_policy_example_test.dart`'s own pubspec.yaml check and
`test/guards/manifest_permission_example_test.dart`'s real-manifest check for
the pattern; neither can rot silently, because a test either runs green
against reality or it doesn't.

## Project invariants

Load-bearing constraints no story may breach without an explicit conversation
with the project owner. Changing one is plan drift by definition: log it as an
ad-hoc ledger entry in `.n8/decisions.md` and suggest `/n8-replan`.

1. **No ads, no tracking, no analytics, no network.** The release build declares no Android permissions at all (INTERNET included) and all player data stays on the device. *(test-enforced: `test/guards/manifest_permission_example_test.dart`, `tools/check_aab.sh` over every built bundle via `test/guards/bundle_scan_test.dart`, and the dependency blocklist in `test/guards/dependency_policy_example_test.dart` — guard: #16 (merged))* Guards defend against honest mistakes, not deliberate evasion — a permission hidden by an obfuscated manifest edit, or a harmful package that is not on the blocklist, is left to code review and `/n8-audit` (the same scope Honest Solitaire recorded at its M0/M1 verification, 2026-09-24).
2. **Lean dependencies.** A third-party package is added only when it is necessary, carries a trailing `# why: <reason>` on its `pubspec.yaml` key line, and never brings ads, analytics or network access. A plugin is adopted only at planning, after its own `AndroidManifest.xml` has been read for permissions and the owner has approved it. *(test-enforced: blocklist and justification — guard: #16 (merged); "necessary" is honor-system, checked by audits)*
3. **Legal chess, verified.** Move generation matches published perft counts on the standard reference positions, and the computer only ever plays a legal move. *(test-enforced — guard: deferred → M2, epic #3)*
4. **The strength dial is honest, and the computer runs on the device.** Each strength step's handicap is exactly what its description says, Master has none, the search never runs on the UI thread, and the same position, step and seed always give the same move. *(test-enforced — guard: deferred → M2, epic #4)*

## n8SDLC project

This project is managed by the n8SDLC workflow (GitHub Issues = the plan;
`/n8-stat` shows where things stand). If a change made in this session
deviates from what planned issues assume — different library, provider,
architecture, dropped/added scope, or amending a declared invariant below —
do two things before finishing:
1. Append an `## Ad-hoc` entry to `.n8/decisions.md` (format documented in
   that file's header) naming the change, the why, and the milestones/issues
   likely affected.
2. Tell the user which future milestones may now have stale plans and
   suggest running `/n8-replan`.

Separately: if a `/n8-*` skill's own instructions failed, misled you, or were
silent on something this session, tell the user and offer `/n8-feedback` —
it packages the learning as an issue on the plugin repo, stripped of project
specifics, and sends nothing until the user has reviewed the exact text.
