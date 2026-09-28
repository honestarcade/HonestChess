---
name: play-console
description: The Play Console app entry, the CI service account, and the constraints a personal developer account puts on getting to production
metadata:
  type: project
---

# Play Console (Honest Chess)

**Never store credentials here.** Identifiers and constraints only; secret
values live in the repository's Actions secrets and the owner's password
manager.

The click-by-click procedure is `play-console-runbook.md`; this file records
what it produced for this app.

## The app entry

| | |
|---|---|
| name | Honest Chess |
| package | `com.honestarcade.chess` (set by the first bundle upload, #22) |
| type | Game, free |
| default language | English (US) |
| Console app id | `4973093225361555116` |
| developer account id | `5264586118822775573` (same account as Honest Solitaire and Honest Sudoku) |
| owner account | `ntpond@gmail.com` |
| internal testers list | "Testers" — the owner's Google account only |

## CI service account

| | |
|---|---|
| Cloud project | `honestchess-ci` |
| service account | `honestchess-ci@honestchess-ci.iam.gserviceaccount.com` |
| Play permissions | Release to testing tracks; View app information and download bulk reports — nothing else |
| secret | `PLAY_SERVICE_ACCOUNT_JSON` |
| key id | `6efd070a114d7ef200d8fe17cff5550edde3f6cf` (public; needed to revoke the right key) |

## Constraints

- Personal developer account: production access needs a closed test with at
  least 12 testers opted in for 14 continuous days.
- `alpha` in the API is the Console's closed testing track.
- Until the first release is published, Play refuses a `completed` release on
  any track but `internal`; `tools/play_promote.sh` falls back to `draft` only
  on that exact refusal.

## Setup status (UTC dates)

- 2026-09-27: upload keystore created (see [[android-signing]]), #15.
- 2026-09-28: owner created the app entry (runbook step 1) and the internal
  testers list "Testers", and put the keystore password and file into their
  password manager. #21.
- 2026-09-28: `tools/setup_play_ci.sh` (account ntpond@gmail.com) created the
  Cloud project and service account, enabled the Android Publisher API, and set
  `PLAY_SERVICE_ACCOUNT_JSON` from key `6efd070a…`, deleted from disk after
  upload (runbook step 3). #21.
