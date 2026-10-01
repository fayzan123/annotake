#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
DIR=.signing; NAME="Annotake Local Signing"; PASS=annotake-local
KC="$PWD/$DIR/annotake-signing.keychain-db"
if [ -f "$KC" ] && security find-identity -p codesigning "$KC" | grep -q "$NAME"; then
  echo "Signing identity already exists"; exit 0
fi
mkdir -p "$DIR"
cat > "$DIR/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CNF
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$DIR/cert.cnf" \
  -keyout "$DIR/key.pem" -out "$DIR/cert.pem"
/usr/bin/openssl pkcs12 -export -inkey "$DIR/key.pem" -in "$DIR/cert.pem" \
  -out "$DIR/identity.p12" -passout "pass:$PASS"
security create-keychain -p "$PASS" "$KC"
security set-keychain-settings "$KC"
security unlock-keychain -p "$PASS" "$KC"
security import "$DIR/identity.p12" -k "$KC" -P "$PASS" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple: -s -k "$PASS" "$KC" >/dev/null
security list-keychains -d user -s "$KC" $(security list-keychains -d user | tr -d '"')
rm -f "$DIR/key.pem" "$DIR/identity.p12"
security find-identity -p codesigning "$KC"
