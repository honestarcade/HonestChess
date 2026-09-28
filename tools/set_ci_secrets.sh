#!/usr/bin/env bash
# Load the four signing secrets into the repository from the credentials file
# tools/make_upload_key.sh wrote.
#
# It PARSES that file rather than sourcing it, so nothing in a password is
# ever executed, whatever the writer does in future.
#
# Prints the names of the secrets it set. Never a value.
#
# Usage: tools/set_ci_secrets.sh
set -euo pipefail
export LC_ALL=C
cd "$(dirname "$0")/.."

# The APP_SLUG default is written by tools/rename_app.py. HS_SECRETS_DIR, if
# set, must match the one make_upload_key.sh used.
APP_SLUG="${HS_APP_SLUG:-honestchess}"
SECRETS_DIR="${HS_SECRETS_DIR:-$HOME/HonestArcadeApps/secrets}"
CREDENTIALS="$SECRETS_DIR/$APP_SLUG-signing-credentials.txt"

# Named (owner/repo), not inferred: `gh` otherwise resolves the repository from
# `git remote`, so a fork clone would send the keystore and its password to
# somebody else's repository secrets.
REPO="${HS_REPO:?set HS_REPO to owner/repo, or edit this line}"

command -v gh > /dev/null 2>&1 || {
  echo "set_ci_secrets: gh is not on PATH" >&2
  exit 3
}

[ -r "$CREDENTIALS" ] || {
  echo "set_ci_secrets: cannot read $CREDENTIALS" >&2
  echo "  It is written by tools/make_upload_key.sh and is not in the repository." >&2
  exit 2
}

# Read one `export NAME=value` from the credentials file, without executing it.
#
# Carriage returns are stripped and anything after the closing quote is
# dropped, so neither can end up inside a secret. Inside double quotes the
# escaped characters are unescaped; inside single quotes nothing is. Nothing
# is ever expanded or executed.
read_credential() {
  tr -d '\r' < "$CREDENTIALS" |
    sed -n "s/^[[:space:]]*export[[:space:]][[:space:]]*$1=//p" |
    head -1 |
    awk '{
      line = $0
      if (substr(line, 1, 1) == "\"") {
        # Scan to the matching quote, unescaping the four characters
        # make_upload_key.sh escapes, so the round trip is exact. Anything
        # after the closing quote (a comment, stray spaces) is not the value.
        out = ""
        for (i = 2; i <= length(line); i++) {
          c = substr(line, i, 1)
          if (c == "\\" && i < length(line)) {
            n = substr(line, i + 1, 1)
            if (n == "\"" || n == "$" || n == "\\" || n == "`") { out = out n; i++; continue }
            out = out c; continue
          }
          if (c == "\"") break
          out = out c
        }
        print out
      } else if (substr(line, 1, 1) == "\047") {
        out = ""
        for (i = 2; i <= length(line); i++) {
          c = substr(line, i, 1)
          if (c == "\047") break
          out = out c
        }
        print out
      } else {
        # Unquoted: a `#` after whitespace starts a comment, as in a shell.
        sub(/[[:space:]]+#.*$/, "", line)
        sub(/[[:space:]]+$/, "", line)
        print line
      }
    }'
}

KEYSTORE_PATH="$(read_credential HS_KEYSTORE_PATH)"
KEYSTORE_PASS="$(read_credential HS_KEYSTORE_PASS)"
KEY_ALIAS="$(read_credential HS_KEY_ALIAS)"
KEY_PASS="$(read_credential HS_KEY_PASS)"

for pair in "HS_KEYSTORE_PATH:$KEYSTORE_PATH" "HS_KEYSTORE_PASS:$KEYSTORE_PASS" \
  "HS_KEY_ALIAS:$KEY_ALIAS" "HS_KEY_PASS:$KEY_PASS"; do
  name="${pair%%:*}"
  value="${pair#*:}"
  [ -n "$value" ] || {
    echo "set_ci_secrets: $name is missing or empty in $CREDENTIALS" >&2
    exit 2
  }
done

# A PKCS12 keystore has one password, and keytool ignores `-keypass` and exits
# 0 whatever it is given, so no command can check HS_KEY_PASS. Asserting it
# equals the store password is the check that can fail.
[ "$KEY_PASS" = "$KEYSTORE_PASS" ] || {
  echo "set_ci_secrets: HS_KEY_PASS differs from HS_KEYSTORE_PASS." >&2
  echo "  A PKCS12 keystore has one password; keytool ignores a separate key" >&2
  echo "  password, so a mismatch here cannot be caught later and would fail" >&2
  echo "  the release build instead. Check $CREDENTIALS." >&2
  exit 2
}

[ -r "$KEYSTORE_PATH" ] || {
  echo "set_ci_secrets: the keystore named in the credentials file is not readable:" >&2
  echo "  $KEYSTORE_PATH" >&2
  exit 2
}

# Pre-flight: prove the parsed password and alias open the keystore before
# any of it leaves this machine, rather than minutes into a release build.
# `-storepass:env` keeps the password out of the process table.
#
# keytool is probed rather than trusted: `/usr/bin/keytool` on macOS is a stub
# that exists, is executable, and cannot run.
KEYTOOL="${HS_KEYTOOL:-/opt/homebrew/opt/openjdk@21/bin/keytool}"
if [ ! -x "$KEYTOOL" ] && command -v keytool > /dev/null 2>&1; then
  KEYTOOL="$(command -v keytool)"
fi
KEYTOOL_PROBE=""
[ -x "$KEYTOOL" ] && KEYTOOL_PROBE="$("$KEYTOOL" -help 2>&1 || true)"
case "${KEYTOOL_PROBE:-none}" in
none | *"Unable to locate a Java Runtime"*)
  echo "set_ci_secrets: no usable keytool, so the keystore pre-flight is SKIPPED." >&2
  echo "  Set HS_KEYTOOL to a real one to have the password checked before upload." >&2
  ;;
*)
  HS_PASS_PROBE="$KEYSTORE_PASS" "$KEYTOOL" -list \
    -keystore "$KEYSTORE_PATH" \
    -storetype PKCS12 \
    -storepass:env HS_PASS_PROBE \
    -alias "$KEY_ALIAS" > /dev/null 2>&1 || {
    echo "set_ci_secrets: the parsed password and alias do not open the keystore." >&2
    echo "  Nothing was uploaded. Check $CREDENTIALS for stray quoting," >&2
    echo "  a carriage return, or an alias that is not the one in the keystore." >&2
    exit 2
  }
  ;;
esac

# Base64 on one line: `gh secret set` takes the value on stdin, and a newline
# inside it would survive into the runner's decode.
base64 < "$KEYSTORE_PATH" | tr -d '\n' | gh secret set HS_KEYSTORE_B64 -R "$REPO"
printf '%s' "$KEYSTORE_PASS" | gh secret set HS_KEYSTORE_PASS -R "$REPO"
printf '%s' "$KEY_ALIAS" | gh secret set HS_KEY_ALIAS -R "$REPO"
printf '%s' "$KEY_PASS" | gh secret set HS_KEY_PASS -R "$REPO"

echo "set: HS_KEYSTORE_B64 HS_KEYSTORE_PASS HS_KEY_ALIAS HS_KEY_PASS"
echo "  in $REPO"
echo "(PLAY_SERVICE_ACCOUNT_JSON is set by tools/setup_play_ci.sh)"
