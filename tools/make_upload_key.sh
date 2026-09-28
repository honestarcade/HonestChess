#!/usr/bin/env bash
# Generate the Android upload keystore for this app, once.
#
# This key becomes the app's identity. Once Play App Signing is enrolled at the
# first upload, regenerating it does NOT produce an equivalent key — Play will
# refuse bundles signed with anything else, and the only way back is the
# Console's upload-key reset flow. Hence the refusal to overwrite below: the
# most expensive mistake available here is running this twice.
#
# The password comes from the environment, never an argument, so it cannot be
# read out of shell history or a process listing.
#
# Usage:
#   HS_KEYSTORE_PASS='<a long random password>' tools/make_upload_key.sh
#
# Writes (both chmod 600, both outside the repository):
#   $HS_SECRETS_DIR/<APP_SLUG>-upload.keystore
#   $HS_SECRETS_DIR/<APP_SLUG>-signing-credentials.txt
# and the public certificate to android/signing/upload_certificate.pem.
#
# tools/rename_app.py writes the APP_SLUG and APP_DISPLAY_NAME defaults below;
# set HS_ORG_NAME for the certificate's distinguished name.
set -euo pipefail

# Relative paths below are from the repository root, so the refusal that
# protects the committed certificate looks at the committed certificate.
cd "$(dirname "$0")/.."

# Overridable, so a test never touches the owner's real secrets directory and
# a studio can keep secrets elsewhere; the default is only a convention.
SECRETS_DIR="${HS_SECRETS_DIR:-$HOME/HonestArcadeApps/secrets}"
# APP_SLUG and APP_DISPLAY_NAME defaults are written by tools/rename_app.py.
APP_SLUG="${HS_APP_SLUG:-honestchess}"
# <PLACEHOLDER> — shown in the certificate's distinguished name only.
ORG_NAME="${HS_ORG_NAME:-Your Studio}"
APP_DISPLAY_NAME="${HS_APP_DISPLAY_NAME:-Honest Chess}"
KEYSTORE="$SECRETS_DIR/$APP_SLUG-upload.keystore"
# Relative to the repository root, which this script cd's to. Overridable so
# the round trip can be tested without writing over the committed one.
CERT_OUT="${HS_UPLOAD_CERT_OUT:-android/signing/upload_certificate.pem}"
CREDENTIALS="$SECRETS_DIR/$APP_SLUG-signing-credentials.txt"
ALIAS="upload"
KEYTOOL="${HS_KEYTOOL:-/opt/homebrew/opt/openjdk@21/bin/keytool}"

# Any existing output is a refusal. The credentials file is the only record
# of the password until it reaches a password manager, the keystore cannot be
# regenerated once Play has enrolled it, and the committed certificate is what
# verify_upload_cert.sh checks every release against.
for hs_existing in "$KEYSTORE" "$CREDENTIALS" "$CERT_OUT"; do
  if [ -e "$hs_existing" ]; then
    echo "make_upload_key: $hs_existing already exists — refusing to overwrite." >&2
    echo "  This key is the app's identity with Play, and the credentials file" >&2
    echo "  is the only copy of its password until you move it to a password" >&2
    echo "  manager. If you genuinely need a new key, use the Play Console's" >&2
    echo "  upload-key reset flow and move BOTH files aside deliberately." >&2
    exit 2
  fi
done

if [ -z "${HS_KEYSTORE_PASS:-}" ]; then
  echo "make_upload_key: set HS_KEYSTORE_PASS in the environment." >&2
  echo "  Passed as an argument it would land in your shell history." >&2
  exit 2
fi

# PKCS12 and keytool accept six characters; this key signs every release, so
# the floor is 32 -- what `openssl rand -base64 24` or longer gives (#36).
if [ "${#HS_KEYSTORE_PASS}" -lt 32 ]; then
  echo "make_upload_key: HS_KEYSTORE_PASS is ${#HS_KEYSTORE_PASS} characters; 32 is the minimum." >&2
  echo "  This is an upload key that signs every release." >&2
  exit 2
fi

if [ ! -x "$KEYTOOL" ]; then
  echo "make_upload_key: no keytool at $KEYTOOL" >&2
  echo "  Override with HS_KEYTOOL=/path/to/keytool (the macOS /usr/bin/java" >&2
  echo "  stub is not a JDK; this project uses Homebrew openjdk@21)." >&2
  exit 3
fi

mkdir -p "$SECRETS_DIR"
chmod 700 "$SECRETS_DIR"

# PKCS12 is the modern default and takes one password for both the store and
# the key; -storepass:env keeps it off the command line.
"$KEYTOOL" -genkeypair \
  -storetype PKCS12 \
  -keystore "$KEYSTORE" \
  -alias "$ALIAS" \
  -keyalg RSA \
  -keysize 2048 \
  -sigalg SHA256withRSA \
  -validity 10000 \
  -dname "O=$ORG_NAME, CN=$APP_DISPLAY_NAME" \
  -storepass:env HS_KEYSTORE_PASS \
  -keypass:env HS_KEYSTORE_PASS

chmod 600 "$KEYSTORE"

# Export the public certificate with the key, so the committed certificate
# always describes the current key. It is the public half and belongs in the
# repository.
mkdir -p "$(dirname "$CERT_OUT")"
"$KEYTOOL" -exportcert -rfc \
  -keystore "$KEYSTORE" \
  -storetype PKCS12 \
  -alias "$ALIAS" \
  -storepass:env HS_KEYSTORE_PASS \
  -file "$CERT_OUT"
chmod 644 "$CERT_OUT"

FINGERPRINT="$("$KEYTOOL" -printcert -file "$CERT_OUT" |
  grep -m1 -oE 'SHA256: [0-9A-F:]+' | sed 's/^SHA256: //')"
echo "certificate written to $CERT_OUT"
echo "  alias:   $ALIAS"
echo "  SHA-256: ${FINGERPRINT:-unknown}"
echo "  Commit it, and update the table in android/signing/README.md."

umask 177

# Escape the four characters still live inside double quotes. printf %s
# writes each value literally, where a heredoc would expand `$(...)` in a
# password, and the escaping keeps the file inert if anyone sources it. Order
# matters: backslash first, or it doubles the backslashes the others add.
escape_for_double_quotes() {
  printf '%s' "$1" |
    sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\$/\\$/g' -e 's/`/\\`/g'
}

{
  printf '%s\n' \
    "# $APP_DISPLAY_NAME upload keystore credentials — MOVE TO YOUR PASSWORD MANAGER," \
    '# then delete this file.' \
    '#' \
    '# Do NOT source this file. tools/set_ci_secrets.sh PARSES it instead. The' \
    '# values are double-quoted with the shell-special characters escaped, so a' \
    '# dot-source is inert — but parsing is the supported path and the only one' \
    '# that is tested (test/guards/setup_scripts_test.dart).'
  printf 'export HS_KEYSTORE_PATH="%s"\n' "$(escape_for_double_quotes "$KEYSTORE")"
  printf 'export HS_KEYSTORE_PASS="%s"\n' "$(escape_for_double_quotes "$HS_KEYSTORE_PASS")"
  printf 'export HS_KEY_ALIAS="%s"\n' "$(escape_for_double_quotes "$ALIAS")"
  printf 'export HS_KEY_PASS="%s"\n' "$(escape_for_double_quotes "$HS_KEYSTORE_PASS")"
  printf '%s\n' \
    '# NOTE: PKCS12 keystores use ONE password for store and key — HS_KEY_PASS' \
    '# equals HS_KEYSTORE_PASS by format design, not by an oversight.'
} > "$CREDENTIALS"
chmod 600 "$CREDENTIALS"

echo "Created $KEYSTORE"
echo "Created $CREDENTIALS  (chmod 600 — move the password to your password manager and delete it)"
