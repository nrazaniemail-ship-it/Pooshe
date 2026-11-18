#!/usr/bin/env bash
set -euo pipefail
umask 077

ALIAS="${POOSHE_KEY_ALIAS:-pooshe-release}"
OUT_DIR="${POOSHE_SIGNING_DIR:-$HOME/pooshe-signing}"
KEYSTORE="$OUT_DIR/pooshe-release.p12"
BASE64_FILE="$OUT_DIR/pooshe-release.base64.txt"

if ! command -v keytool >/dev/null 2>&1; then
  echo "ERROR: keytool not found. Install a JDK (Java 17 or 21) and retry." >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
chmod 700 "$OUT_DIR"

if [[ -e "$KEYSTORE" || -e "$BASE64_FILE" ]]; then
  echo "ERROR: Signing files already exist in $OUT_DIR; refusing to overwrite." >&2
  exit 1
fi

read -r -s -p "Choose a strong keystore password: " POOSHE_KEYSTORE_PASSWORD
echo
read -r -s -p "Repeat password: " CONFIRM_PASSWORD
echo
if [[ -z "$POOSHE_KEYSTORE_PASSWORD" || "$POOSHE_KEYSTORE_PASSWORD" != "$CONFIRM_PASSWORD" ]]; then
  echo "ERROR: Passwords are empty or do not match." >&2
  exit 1
fi
unset CONFIRM_PASSWORD
export POOSHE_KEYSTORE_PASSWORD

keytool -genkeypair \
  -keystore "$KEYSTORE" \
  -storetype PKCS12 \
  -storepass:env POOSHE_KEYSTORE_PASSWORD \
  -keypass:env POOSHE_KEYSTORE_PASSWORD \
  -alias "$ALIAS" \
  -keyalg RSA \
  -keysize 3072 \
  -validity 10000 \
  -dname "CN=Pooshe Android Release, O=Pooshe"

keytool -list -keystore "$KEYSTORE" -storetype PKCS12 \
  -storepass:env POOSHE_KEYSTORE_PASSWORD -alias "$ALIAS" >/dev/null

base64 < "$KEYSTORE" | tr -d '\r\n' > "$BASE64_FILE"
chmod 600 "$KEYSTORE" "$BASE64_FILE"

echo
echo "Signing key created and checked."
echo "Keystore: $KEYSTORE"
echo "Base64:   $BASE64_FILE"
echo "Alias:    $ALIAS"
echo
echo "Store these GitHub Actions secrets in the Pooshe repository:"
echo "  ANDROID_KEYSTORE_BASE64      <- full contents of $BASE64_FILE"
echo "  ANDROID_KEYSTORE_PASSWORD    <- password you entered"
echo "  ANDROID_KEY_ALIAS            <- $ALIAS"
echo
echo "IMPORTANT: Keep a second encrypted offline backup of the .p12 file."
echo "Never commit either signing file or send the password in chat."
