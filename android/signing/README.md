# Upload signing certificate

`upload_certificate.pem` here is the public half of the app's upload key. It
is written by `tools/make_upload_key.sh`, committed on purpose, and read by
`tools/verify_upload_cert.sh` (release.yml) and `play-api-check.yml` to prove
a bundle, or the keystore secret, carries the key Play enrolled.

The private key and its password never enter this repository;
`test/guards/signing_guard_test.dart` asserts git ignores every file shape
they could arrive in.

| Created | SHA-256 fingerprint | Notes |
|---|---|---|
| | | |
