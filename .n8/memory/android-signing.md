---
name: android-signing
description: Where the Android upload keystore lives, how builds consume it, and how to rotate it
metadata:
  type: project
---

# Android upload signing

**Never store the password here.** Locations and procedure only.

- **Keystore:** `~/HonestArcadeApps/secrets/honestchess-upload.keystore` —
  outside the repository, chmod 600. PKCS12, alias `upload`, RSA 2048,
  SHA256withRSA, 10,000 days, dname `O=Honest Arcade, CN=Honest Chess`.
  Created 2026-09-27 by `tools/make_upload_key.sh` (#15) with a password from
  `openssl rand -base64 33`, passed in the environment and never printed.
- **Password:** in the owner's password manager (with the keystore file as an
  attachment, owner-confirmed 2026-09-28), and in the `HS_KEYSTORE_PASS` /
  `HS_KEY_PASS` repository secrets (set 2026-09-28, #21). The credentials file
  was deleted the same day; to run `tools/set_ci_secrets.sh` again, recreate it
  from the password manager.
  PKCS12 has one password, so `HS_KEY_PASS` equals `HS_KEYSTORE_PASS`.
- **Owner follow-ups** (owner's round-two answer at /n8-plan M0, 2026-09-27):
  1. Store the password **and the `.keystore` file itself** (as an attachment)
     in the password manager — the file exists only on this Mac otherwise.
  2. Once #21's `tools/set_ci_secrets.sh` has run and follow-up 1 is
     confirmed, `~/HonestArcadeApps/secrets/honestchess-signing-credentials.txt`
     is deleted (#21 does it). To run that script again later, recreate the
     file from the password manager.
- **Certificate:** committed at `android/signing/upload_certificate.pem`; the
  fingerprint is in `android/signing/README.md`, held to the PEM by
  `test/guards/signing_readme_test.dart`.
- **Build consumption:** `android/app/build.gradle.kts` reads
  `HS_KEYSTORE_PATH`, `HS_KEYSTORE_PASS`, `HS_KEY_ALIAS`, `HS_KEY_PASS` from the
  environment. There is no `key.properties`.
  - all four set → signed with the upload key
  - none set, `HS_RELEASE` unset → debug key, with a warning printed
  - `HS_RELEASE=1` and any missing → configuration fails naming the variable
  - partly set, in any mode → configuration fails
- **CI secret names:** `HS_KEYSTORE_B64`, `HS_KEYSTORE_PASS`, `HS_KEY_ALIAS`,
  `HS_KEY_PASS`, plus `PLAY_SERVICE_ACCOUNT_JSON`.

## Never regenerate silently

Once Play App Signing is enrolled at the first upload (v0.1.0, #22), this
certificate **is** the app's upload identity. If the keystore or its password
is lost after enrolment, do not re-run `make_upload_key.sh` (it refuses to
overwrite anyway); use the Play Console's upload-key reset under *Test and
release → Play Store protection* (the location Honest Sudoku's memory recorded
on 2026-09-22).

Before enrolment, regenerating is harmless: move all three outputs aside
(keystore, credentials file, committed PEM) and re-run the script.
