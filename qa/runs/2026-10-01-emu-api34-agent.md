# Run record — 2026-10-01, emu-api34, agent

A dry run of the thinking-time tool (#112) on the emulator. These are not
the owner's phone's numbers, and they close none of #112's phone criteria.

- Build: profile-mode timing app (`perf_test/think_time_test.dart`) at 5f32e38, whose `lib/`, `android/` and `pubspec.yaml` are identical to `v1.0.0-rc.2`'s (`git diff --stat v1.0.0-rc.2 5f32e38 -- lib android pubspec.yaml` is empty, 2026-10-01)
- Device: emulator `sdk_gphone64_arm64` (`ro.build.fingerprint` google/sdk_gphone64_arm64/emu64a:14/UE1A.230829.050/12077443:userdebug/dev-keys)
- Android / One UI: API 34 (Android 14)
- Hardware or emulator: emulator (Android emulator 37.1.11.0), hosted on the dev Mac (Apple M3 Max)
- AVD and image: `emu-api34` (#108's AVD), API 34 google_apis arm64, booted with `-no-audio -gpu host`
- Runs: `tools/think_time.sh -d emulator-5560`, then the same with `--compare` against the first run's JSON
- Run by: agent

| check | result | bug |
|---|---|---|
| #112 timing run, all five steps, 40 positions each | pass | |
| #112 same moves on a repeat at Club (positions 0–9) | pass | |
| #112 same 200 moves on a second run (`--compare`) | pass | |

## Notes

The first run, as `tools/think_time.sh` printed it (2026-10-01 20:21 UTC).
Its JSON is `2026-10-01-emu-api34-agent/think_time.json`, beside this file:

```
step         stated    target       p50       p95       max vs stated  verdict
beginner       0.30      0.33      0.01      0.02      0.07      -94%  ok, overstated
casual         0.60      0.66      0.01      0.04      0.14      -94%  ok, overstated
club           1.00      1.10      0.01      0.04      0.14      -96%  ok, overstated
strong         2.00      2.20      0.08      0.34      0.53      -83%  ok, overstated
master         5.00      5.50      2.10      2.49      2.63      -50%  ok, overstated
```

The second run (20:23 UTC) gave p95s of 0.02, 0.04, 0.03, 0.26 and 2.37 s,
and all 200 of its moves matched the first's.

On this emulator every step answers well inside its stated time. Beginner to
Strong stop at their depth caps long before their node budgets. In the JSON,
their most nodes on any move were 26,396, 59,764, 59,764 and 253,224, against
budgets of 92,000, 180,000, 310,000 and 610,000. Only Master spends its
budget (1,500,000). Whether the stated times overstate the thinking on the owner's
S26 Ultra is for the phone run to show; per #112's replan (2026-09-29) it is
logged, not failed.
