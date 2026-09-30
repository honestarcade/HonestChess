# Run record — 2026-09-30, emu-api34, agent

This is an emulator run, not a device run. `emu-api34` has the same 320 × 568 dp screen as `emu-api24`, so it can show whether a finding is specific to API 24 (#109). It also takes the two checks the plan puts on `emu-api34` (T822, T910), and `tools/e2e.sh`.

- Build: v1.0.0-rc.1 · BUILD 1031, read from Settings. It is the same universal APK as in `2026-09-30-emu-api24-agent.md`. T910 and the end-to-end script used debug builds, as noted.
- Device: emulator, Nexus S hardware profile at 640 × 1136 px, 320 dpi (320 × 568 dp). It was switched to 3-button navigation for this run.
- Android / One UI: Android 14, API 34 (`google/sdk_gphone64_arm64/emu64a:14/UE1A.230829.050/12077443:userdebug/dev-keys`)
- Hardware or emulator: emulator
- AVD and image: `emu-api34` (created by #108), `system-images;android-34;google_apis;arm64-v8a`, cold boot
- Runs: no sampling row. A Club game as White (Rapid 10+5) was used for the board checks.
- Run by: agent

```sh
~/Library/Android/sdk/emulator/emulator -avd emu-api34 -port 5572 -no-snapshot -no-boot-anim -no-window
adb -s emulator-5572 shell cmd overlay enable com.android.internal.systemui.navbar.threebutton
adb -s emulator-5572 shell cmd overlay disable com.android.internal.systemui.navbar.gestural
adb -s emulator-5572 install -r universal.apk
```

## Results

| check | result | bug | note |
|---|---|---|---|
| T001 | n-a | | phone only |
| T002 | n-a | | phone only |
| T003 | pass |  | every screen from the menu and a board, at the default font |
| T101 | n-a | | covered by `2026-09-30-emu-api24-agent.md`; this AVD isolates API-24-only causes |
| T102 | n-a | | covered by `2026-09-30-emu-api24-agent.md`; this AVD isolates API-24-only causes |
| T103 | n-a | | covered by `2026-09-30-emu-api24-agent.md`; this AVD isolates API-24-only causes |
| T110 | n-a | | covered by `2026-09-30-emu-api24-agent.md`; this AVD isolates API-24-only causes |
| T111 | n-a | | covered by `2026-09-30-emu-api24-agent.md`; this AVD isolates API-24-only causes |
| T112 | n-a | | covered by `2026-09-30-emu-api24-agent.md`; this AVD isolates API-24-only causes |
| T113 | n-a | | covered by `2026-09-30-emu-api24-agent.md`; this AVD isolates API-24-only causes |
| T114 | n-a | | covered by `2026-09-30-emu-api24-agent.md`; this AVD isolates API-24-only causes |
| T201 | n-a | | covered by `2026-09-30-emu-api24-agent.md`; this AVD isolates API-24-only causes |
| T202 | n-a | | covered by `2026-09-30-emu-api24-agent.md`; this AVD isolates API-24-only causes |
| T203 | n-a | | covered by `2026-09-30-emu-api24-agent.md`; this AVD isolates API-24-only causes |
| T204 | n-a | | covered by `2026-09-30-emu-api24-agent.md`; this AVD isolates API-24-only causes |
| T205 | n-a | | covered by `2026-09-30-emu-api24-agent.md`; this AVD isolates API-24-only causes |
| T206 | n-a | | covered by `2026-09-30-emu-api24-agent.md`; this AVD isolates API-24-only causes |
| T210 | n-a | | covered by `2026-09-30-emu-api24-agent.md`; this AVD isolates API-24-only causes |
| T211 | n-a | | covered by `2026-09-30-emu-api24-agent.md`; this AVD isolates API-24-only causes |
| T212 | n-a | | covered by `2026-09-30-emu-api24-agent.md`; this AVD isolates API-24-only causes |
| T301 | n-a | | covered by `2026-09-30-emu-api24-agent.md`; this AVD isolates API-24-only causes |
| T302 | n-a | | covered by `2026-09-30-emu-api24-agent.md`; this AVD isolates API-24-only causes |
| T303 | n-a | | covered by `2026-09-30-emu-api24-agent.md`; this AVD isolates API-24-only causes |
| T304 | n-a | | phone only |
| T305 | n-a | | covered by `2026-09-30-emu-api24-agent.md`; this AVD isolates API-24-only causes |
| T306 | n-a | | covered by `2026-09-30-emu-api24-agent.md`; this AVD isolates API-24-only causes |
| T307 | n-a | | covered by `2026-09-30-emu-api24-agent.md`; this AVD isolates API-24-only causes |
| T308 | n-a | | covered by `2026-09-30-emu-api24-agent.md`; this AVD isolates API-24-only causes |
| T310 | n-a | | covered by `2026-09-30-emu-api24-agent.md`; this AVD isolates API-24-only causes |
| T311 | fail | #175 | spot check to see whether #175 is API-24-only: the yellow double underline shows here too |
| T312 | n-a | | phone only |
| T313 | n-a | | covered by `2026-09-30-emu-api24-agent.md`; this AVD isolates API-24-only causes |
| T314 | n-a | | covered by `2026-09-30-emu-api24-agent.md`; this AVD isolates API-24-only causes |
| T315 | n-a | | phone only |
| T316 | n-a | | covered by `2026-09-30-emu-api24-agent.md`; this AVD isolates API-24-only causes |
| T317 | n-a | | phone only |
| T318 | n-a | | phone only |
| T401 | n-a | | covered by `2026-09-30-emu-api24-agent.md`; this AVD isolates API-24-only causes |
| T402 | n-a | | covered by `2026-09-30-emu-api24-agent.md`; this AVD isolates API-24-only causes |
| T403 | n-a | | covered by `2026-09-30-emu-api24-agent.md`; this AVD isolates API-24-only causes |
| T404 | n-a | | covered by `2026-09-30-emu-api24-agent.md`; this AVD isolates API-24-only causes |
| T405 | n-a | | covered by `2026-09-30-emu-api24-agent.md`; this AVD isolates API-24-only causes |
| T406 | n-a | | covered by `2026-09-30-emu-api24-agent.md`; this AVD isolates API-24-only causes |
| T407 | n-a | | covered by `2026-09-30-emu-api24-agent.md`; this AVD isolates API-24-only causes |
| T501 | n-a | | covered by `2026-09-30-emu-api24-agent.md`; this AVD isolates API-24-only causes |
| T502 | n-a | | covered by `2026-09-30-emu-api24-agent.md`; this AVD isolates API-24-only causes |
| T503 | n-a | | covered by `2026-09-30-emu-api24-agent.md`; this AVD isolates API-24-only causes |
| T504 | n-a | | covered by `2026-09-30-emu-api24-agent.md`; this AVD isolates API-24-only causes |
| T520 | n-a | | covered by `2026-09-30-emu-api24-agent.md`; this AVD isolates API-24-only causes |
| T521 | n-a | | covered by `2026-09-30-emu-api24-agent.md`; this AVD isolates API-24-only causes |
| T522 | n-a | | covered by `2026-09-30-emu-api24-agent.md`; this AVD isolates API-24-only causes |
| T523 | n-a | | covered by `2026-09-30-emu-api24-agent.md`; this AVD isolates API-24-only causes |
| T524 | n-a | | covered by `2026-09-30-emu-api24-agent.md`; this AVD isolates API-24-only causes |
| T525 | n-a | | covered by `2026-09-30-emu-api24-agent.md`; this AVD isolates API-24-only causes |
| T530 | n-a | | covered by `2026-09-30-emu-api24-agent.md`; this AVD isolates API-24-only causes |
| T531 | n-a | | covered by `2026-09-30-emu-api24-agent.md`; this AVD isolates API-24-only causes |
| T540 | n-a | | covered by `2026-09-30-emu-api24-agent.md`; this AVD isolates API-24-only causes |
| T541 | n-a | | covered by `2026-09-30-emu-api24-agent.md`; this AVD isolates API-24-only causes |
| T542 | n-a | | covered by `2026-09-30-emu-api24-agent.md`; this AVD isolates API-24-only causes |
| T543 | n-a | | covered by `2026-09-30-emu-api24-agent.md`; this AVD isolates API-24-only causes |
| T544 | n-a | | covered by `2026-09-30-emu-api24-agent.md`; this AVD isolates API-24-only causes |
| T546 | n-a | | covered by `2026-09-30-emu-api24-agent.md`; this AVD isolates API-24-only causes |
| T550 | n-a | | covered by `2026-09-30-emu-api24-agent.md`; this AVD isolates API-24-only causes |
| T551 | n-a | | covered by `2026-09-30-emu-api24-agent.md`; this AVD isolates API-24-only causes |
| T552 | n-a | | covered by `2026-09-30-emu-api24-agent.md`; this AVD isolates API-24-only causes |
| T601 | n-a | | covered by `2026-09-30-emu-api24-agent.md`; this AVD isolates API-24-only causes |
| T602 | n-a | | covered by `2026-09-30-emu-api24-agent.md`; this AVD isolates API-24-only causes |
| T603 | n-a | | covered by `2026-09-30-emu-api24-agent.md`; this AVD isolates API-24-only causes |
| T604 | n-a | | covered by `2026-09-30-emu-api24-agent.md`; this AVD isolates API-24-only causes |
| T605 | n-a | | covered by `2026-09-30-emu-api24-agent.md`; this AVD isolates API-24-only causes |
| T606 | n-a | | covered by `2026-09-30-emu-api24-agent.md`; this AVD isolates API-24-only causes |
| T701 | n-a | | covered by `2026-09-30-emu-api24-agent.md`; this AVD isolates API-24-only causes |
| T702 | n-a | | covered by `2026-09-30-emu-api24-agent.md`; this AVD isolates API-24-only causes |
| T703 | n-a | | covered by `2026-09-30-emu-api24-agent.md`; this AVD isolates API-24-only causes |
| T710 | n-a | | covered by `2026-09-30-emu-api24-agent.md`; this AVD isolates API-24-only causes |
| T711 | n-a | | covered by `2026-09-30-emu-api24-agent.md`; this AVD isolates API-24-only causes |
| T712 | n-a | | covered by `2026-09-30-emu-api24-agent.md`; this AVD isolates API-24-only causes |
| T713 | n-a | | covered by `2026-09-30-emu-api24-agent.md`; this AVD isolates API-24-only causes |
| T714 | n-a | | covered by `2026-09-30-emu-api24-agent.md`; this AVD isolates API-24-only causes |
| T715 | n-a | | covered by `2026-09-30-emu-api24-agent.md`; this AVD isolates API-24-only causes |
| T716 | n-a | | covered by `2026-09-30-emu-api24-agent.md`; this AVD isolates API-24-only causes |
| T720 | n-a | | phone only |
| T721 | n-a | | phone only |
| T722 | n-a | | phone only |
| T801 | n-a | | covered by `2026-09-30-emu-api24-agent.md`; this AVD isolates API-24-only causes |
| T802 | n-a | | covered by `2026-09-30-emu-api24-agent.md`; this AVD isolates API-24-only causes |
| T810 | n-a | | covered by `2026-09-30-emu-api24-agent.md`; this AVD isolates API-24-only causes |
| T811 | n-a | | covered by `2026-09-30-emu-api24-agent.md`; this AVD isolates API-24-only causes |
| T820 | n-a | | covered by `2026-09-30-emu-api24-agent.md`; this AVD isolates API-24-only causes |
| T821 | n-a | | covered by `2026-09-30-emu-api24-agent.md`; this AVD isolates API-24-only causes |
| T822 | pass |  | Chrome disabled with `pm disable-user`: the snackbar reads "No browser found" and the app stays in front; Chrome re-enabled afterwards |
| T901 | n-a | | covered by `2026-09-30-emu-api24-agent.md`; this AVD isolates API-24-only causes |
| T902 | n-a | | covered by `2026-09-30-emu-api24-agent.md`; this AVD isolates API-24-only causes |
| T903 | n-a | | covered by `2026-09-30-emu-api24-agent.md`; this AVD isolates API-24-only causes |
| T904 | n-a | | covered by `2026-09-30-emu-api24-agent.md`; this AVD isolates API-24-only causes |
| T905 | n-a | | covered by `2026-09-30-emu-api24-agent.md`; this AVD isolates API-24-only causes |
| T906 | n-a | | covered by `2026-09-30-emu-api24-agent.md`; this AVD isolates API-24-only causes |
| T910 | pass |  | debug build of c080c48: banner shown, `stats.bad-1790771256277.json` kept, Statistics at zero, the saved game still offered, and no banner after Dismiss and a relaunch |
| T950 | n-a | | phone only |
| T951 | n-a | | phone only |
| T952 | n-a | | phone only |
| T953 | n-a | | phone only |
| T954 | n-a | | phone only |
| T955 | n-a | | phone only |
| T956 | n-a | | phone only |
| T957 | n-a | | covered by `2026-09-30-emu-api24-agent.md`; this AVD isolates API-24-only causes |
| T960 | n-a | | phone only |
| T961 | fail | #176, #177 | spot check at `font_scale 1.3`: both reproduce |
| T962 | n-a | | phone only |

## End-to-end script

`tools/e2e.sh -d emulator-5572` was run after the checks above. It was run at c080c48, on 2026-09-30 from 12:30:49Z to 12:31:44Z UTC:

```
e2e tests: 2 passed, 0 failed (flutter test exit 0)
```

## Notes

- #175 (sev:high) reproduces here. See `2026-09-30-emu-api34-agent/drag-underline.png`.
- #176 and #177 reproduce here with `adb shell settings put system font_scale 1.3`. See `random-split.png` and `about-footer.png`. Android 14's own Largest step is above 1.3×, and the app clamps text at 1.3×, so 1.3 was set directly.
