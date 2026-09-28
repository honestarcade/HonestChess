# Honest Chess

Chess for Android from Honest Arcade: no ads, no tracking, no network.

Status: just initialized. The app is still the template's placeholder
screen; the roadmap lives in this repository's GitHub milestones and issues.

## Build and test

Requires the Flutter version in `.fvmrc`, the Android SDK and a JDK.

```
flutter pub get
flutter run            # on a device or emulator
tools/gate.sh          # everything CI runs on a pull request; must print GATE PASSED
tools/mutation_check.py  # proves the guard suite can fail (needs a clean tree)
```

Release builds are signed only in CI, from a version tag; see
`.n8/memory/play-console-runbook.md`.
