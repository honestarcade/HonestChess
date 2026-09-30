# Run record — 2026-09-30, emu-api24, agent

This is an emulator run, not a device run. The owner has no second device, so Android 7.0 and the smallest screen are covered only by emulators (#109, /n8-plan M6 round one).

- Build: v1.0.0-rc.1 · BUILD 1031, read from Settings. It is the `v1.0.0-rc.1` GitHub release AAB, built from fa4ec7f.
- Device: emulator, Nexus S hardware profile re-set to 640 × 1136 px at 320 dpi (320 × 568 dp), with 3-button navigation.
- Android / One UI: Android 7.0, API 24 (`google/sdk_google_phone_arm64/generic_arm64:7.0/NYC/8695085:userdebug/dev-keys`)
- Hardware or emulator: emulator
- AVD and image: `emu-api24`, `system-images;android-24;google_apis;arm64-v8a`, cold boot
- Runs: the rows' options in parts rather than whole rows. Vs the computer: R1's Beginner/White/untimed, R5's Master/Black/custom 1+0, and Strong and Club games. Two players: R6's custom 90+60 with rotate on and R7's untimed with rotate off. Every switch was used off and on. Random drew White, then Black.
- Run by: agent

## Setup

The AVD. It has no `hw.mainKeys`, so it gets 3-button navigation. Audio is off because the first boot with audio hung (see Notes):

```sh
export JAVA_HOME=/opt/homebrew/opt/openjdk@21 SDK=~/Library/Android/sdk
echo no | $SDK/cmdline-tools/latest/bin/avdmanager create avd -n emu-api24 \
  -k "system-images;android-24;google_apis;arm64-v8a" -d "Nexus S"
sed -i '' -e 's/^hw.lcd.density=.*/hw.lcd.density=320/' -e 's/^hw.lcd.height=.*/hw.lcd.height=1136/' \
  -e 's/^hw.lcd.width=.*/hw.lcd.width=640/' -e 's/^hw.mainKeys=.*/hw.mainKeys=no/' \
  -e 's/^hw.ramSize=.*/hw.ramSize=2048/' -e 's/^hw.gpu.enabled=.*/hw.gpu.enabled=yes/' \
  -e 's/^hw.gpu.mode=.*/hw.gpu.mode=host/' -e 's/^hw.keyboard=.*/hw.keyboard=yes/' \
  ~/.android/avd/emu-api24.avd/config.ini
$SDK/emulator/emulator -avd emu-api24 -port 5570 -no-snapshot -no-boot-anim -no-audio -no-window -gpu host
```

The candidate. The AAB's SHA-256 matched the release's sidecar (`99a2fdac…011d`). bundletool 1.18.3 was the latest release on 2026-09-30, jar SHA-256 `a099cfa1543f55593bc2ed16a70a7c67fe54b1747bb7301f37fdfd6d91028e29`. The universal APK's SHA-256 was `2d740d3a4e4617a01f96faf0d6e24390637bfd92d26649d2d51cf7358908ff2e`.

```sh
gh release download v1.0.0-rc.1 -R honestarcade/HonestChess   # app-release.aab + .sha256
shasum -a 256 app-release.aab; cat app-release.aab.sha256
java -jar bundletool-all-1.18.3.jar build-apks --bundle=app-release.aab --output=rc1.apks \
  --mode=universal --ks=$HOME/.android/debug.keystore --ks-pass=pass:android \
  --ks-key-alias=androiddebugkey --key-pass=pass:android
unzip rc1.apks universal.apk && adb -s emulator-5570 install -r universal.apk
```

`dumpsys package` on the installed app showed versionName 1.0.0-rc.1, versionCode 1031, minSdk 24 and targetSdk 36. The only requested permission was the app's own `com.honestarcade.chess.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`, which `tools/check_aab.sh` allowlists.

Each check was driven by `adb shell input` taps and swipes. The results were read from `uiautomator dump`, which gives the app's semantics labels, and from `screencap`. Sound and haptics are `n-a` on the emulator: there was no speaker check and it has no motor. The owner checks them on the phone (#110, #111).

## Results

| check | result | bug | note |
|---|---|---|---|
| T001 | n-a | | phone only |
| T002 | n-a | | phone only |
| T003 | pass |  | default font here; largest font in `-2` |
| T101 | pass |  | mark, wordmark, BY HONEST ARCADE, bar and READY, then the fade. SETTING UP and SORTING PIECES finished between two `screencap`s (about 0.3 s apart), so only READY was seen |
| T102 | pass |  | back 0.5 s after launch kept the app, and the menu followed. Home during READY: on return the splash showed READY again and then faded to the menu. Back pressed 0.9 s after launch, during the fade itself, left the app like back on the menu |
| T103 | pass |  | API 24 has no Remove animations switch, so the three developer animation scales were set to 0. Frames 0.1 s apart showed the splash, then the menu, with no mixed frame |
| T110 | pass |  |  |
| T111 | pass |  | every entry, with ‹ and with system back |
| T112 | pass |  | "Continue vs Beginner", MOVE 3 · WHITE; opens on the pause card |
| T113 | pass |  |  |
| T114 | pass |  |  |
| T201 | pass |  |  |
| T202 | pass |  | all five descriptions word for word, with one to five pips |
| T203 | pass |  | Random drew White, then Black |
| T204 | pass |  | held buttons stopped at 1 min, 60 sec and 90 min; the button at its limit is disabled |
| T205 | pass |  | Strong, Black, Custom 15+10 kept after Force stop |
| T206 | pass |  | the old game counted as one loss |
| T210 | pass |  |  |
| T211 | pass |  |  |
| T212 | pass |  | ∞, 5, 10, 30, 90 minutes; neither clock ran before White's first move |
| T301 | pass |  | vs Strong as White, untimed |
| T302 | pass |  | THINKING… and "Strong is thinking" caught mid-slide |
| T303 | pass |  | vs Master, custom 1+0: Master opened, and its clock read 1:00 after its move |
| T304 | n-a | | phone only |
| T305 | pass |  | in R5's 1+0 game rather than R2's Blitz: red at 0:27, tenths at 0:06.8 |
| T306 | pass |  |  |
| T307 | pass |  |  |
| T308 | pass |  | "White resigned" |
| T310 | pass |  |  |
| T311 | fail | #175 | the move and the spring-back work, but the lifted and flying piece carries a yellow double underline |
| T312 | n-a | | phone only |
| T313 | pass |  | sound n-a on the emulator |
| T314 | pass |  | sound n-a |
| T315 | n-a | | phone only |
| T316 | pass |  | sound n-a |
| T317 | n-a | | phone only |
| T318 | n-a | | phone only |
| T401 | pass |  |  |
| T402 | pass |  |  |
| T403 | pass |  | end sound n-a |
| T404 | pass |  | +60 s to the mover; White's first move earns none, as `lib/engine/clock.dart` says |
| T405 | pass |  |  |
| T406 | pass |  |  |
| T407 | pass |  |  |
| T501 | pass |  |  |
| T502 | pass |  | knight, rook (by b7a8), queen, bishop |
| T503 | pass |  |  |
| T504 | pass |  |  |
| T520 | pass |  |  |
| T521 | pass |  |  |
| T522 | pass |  | Rapid 10+5: 10:01 before Home, 10:00 on Resume after 10 s away |
| T523 | pass |  |  |
| T524 | pass |  |  |
| T525 | pass |  |  |
| T530 | pass |  | vs Strong, a queen down |
| T531 | pass |  | accepted by Beginner at move 6 of an R1-style Rapid game |
| T540 | pass |  | mated Beginner in 19 moves; the moves came from Stockfish on the host. End sound n-a |
| T541 | pass |  |  |
| T542 | pass |  | the result card scrolls to Main menu on this screen |
| T543 | pass |  |  |
| T544 | pass |  |  |
| T546 | pass |  | "Black ran out of time", TIME LEFT 0:00 |
| T550 | pass |  |  |
| T551 | pass |  |  |
| T552 | pass |  |  |
| T601 | pass |  | after `pm clear` |
| T602 | pass |  |  |
| T603 | pass |  |  |
| T604 | pass |  |  |
| T605 | pass |  |  |
| T606 | pass |  |  |
| T701 | pass |  | v1.0.0-rc.1 · BUILD 1031 |
| T702 | pass |  | see #178 in the notes |
| T703 | pass |  |  |
| T710 | pass |  |  |
| T711 | pass |  |  |
| T712 | pass |  |  |
| T713 | pass |  |  |
| T714 | pass |  |  |
| T715 | pass |  |  |
| T716 | pass |  |  |
| T720 | n-a | | phone only |
| T721 | n-a | | phone only |
| T722 | n-a | | phone only |
| T801 | pass |  |  |
| T802 | pass |  |  |
| T810 | pass |  |  |
| T811 | pass |  | https://honestarcade.app and https://github.com/honestarcade/HonestChess in the WebView shell browser |
| T820 | pass |  |  |
| T821 | pass |  | /contribute, the site and github.com/honestarcade; scroll position kept |
| T822 | pass |  | here, with `org.chromium.webview_shell` disabled; also run on emu-api34 |
| T901 | pass |  | all recents cards dismissed, and the process was gone before relaunch |
| T902 | pass |  |  |
| T903 | pass |  |  |
| T904 | pass |  |  |
| T905 | pass |  |  |
| T906 | pass |  |  |
| T910 | pass |  | debug build of c080c48 (same app code as fa4ec7f), run after the release checks: `stats.bad-1790771328511.json` kept |
| T950 | n-a | | phone only |
| T951 | n-a | | phone only |
| T952 | n-a | | phone only |
| T953 | n-a | | phone only |
| T954 | n-a | | phone only |
| T955 | n-a | | phone only |
| T956 | n-a | | phone only |
| T957 | pass |  | animation scales at 0: frames 0.1 s apart show the cards and pieces with no in-between |
| T960 | n-a | | phone only |
| T961 | fail | #176, #177 | run in `2026-09-30-emu-api24-agent-2.md` |
| T962 | n-a | | phone only |

## End-to-end script

`tools/e2e.sh -d emulator-5570` was run after the manual checks, because it replaces the candidate with a debug build. It was run at c080c48, on 2026-09-30 from 12:29:47Z to 12:30:43Z UTC, and passed on its second attempt:

```
e2e tests: 2 passed, 0 failed (flutter test exit 0)
```

The first attempt, at 12:29:21Z, failed before any test ran: `Failed to load ".../integration_test/e2e_game_test.dart": WebSocketChannelException: HttpException: Connection closed before full header was received, uri = http://127.0.0.1:62405/…/ws`. The app had started and its VM service was listening, so this is the tool's connection to the device, not the app. The plan allows one retry of a flaky run. The retry passed unchanged.

## Notes

- #175 (sev:high): a dragged piece, and one springing back, is drawn with Flutter's yellow double underline. See `2026-09-30-emu-api24-agent/drag-underline.png` and `springback-underline.png`. It is also seen on emu-api34.
- #178 (sev:medium): with Outline pieces on Bone (Wood or Plain), the two sides are hard to tell apart on this board, whose squares are 30 dp. See `outline-bone-wood.png` and `outline-bone-plain.png`. T702's own expectation passes, because each look applies at once. The owner is asked to judge this on the S26 in R2 and R5.
- Two things were seen that are not failures: the clock panel's sub-line (e.g. "PLAYER TWO · BLACK · CUSTOM 90+60", or "CUSTOM 1+0" once the clock shows tenths) wraps to two lines at 320 dp without cutting anything off, and the result card needs a scroll to reach Main menu at the default font.
- The first boot of the AVD with audio on hung ("detected a hanging thread 'QEMU2 CPU0 thread'") and the emulator exited. It booted with `-no-audio`, as the studio's `solitaire-api24` AVD also runs. So the pass-2 line about checking TalkBack speech with the emulator's audio could not be done here. TalkBack (T960) is marked `phone` in the plan and was not run.
- Timings are from the host clock in UTC. The emulator's status bar shows its own local time.
