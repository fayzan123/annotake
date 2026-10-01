#!/bin/bash
# The Developer ID Application certificate, without Xcode (spec §9):
#   devid.sh csr           writes .signing/devid.key and the request to upload, .signing/devid.csr
#   devid.sh import <cer>  imports the certificate Apple issued for that request into the signing keychain
# SIGNING_DIR overrides .signing, for rehearsing with a throwaway keychain.
set -euo pipefail
cd "$(dirname "$0")/.."
DIR=${SIGNING_DIR:-.signing}
PASS=annotake-local
KEY="$DIR/devid.key"
CSR="$DIR/devid.csr"
PEM="$DIR/devid.pem"
P12="$DIR/devid.p12"
INTERMEDIATE_URL=https://www.apple.com/certificateauthority/DeveloperIDG2CA.cer

usage() {
  echo "usage: $0 csr | import <certificate.cer>" >&2
  exit 2
}

csr() {
  if [ -e "$KEY" ]; then
    echo "$KEY already exists, so a request made with it may be waiting at Apple." >&2
    echo "Import that certificate (make devid-import CER=…), or delete $KEY to start over." >&2
    exit 1
  fi
  mkdir -p "$DIR"
  (umask 077 && /usr/bin/openssl req -new -newkey rsa:2048 -nodes -keyout "$KEY" -out "$CSR" \
    -subj "/CN=Annotake Developer ID/C=CA")
  cat <<EOF

The certificate signing request is $(cd "$DIR" && pwd)/devid.csr.
Its private key stays in $KEY until the import, which moves it into the keychain.
To get the certificate:
  1. At developer.apple.com/account: Certificates, IDs & Profiles → Certificates → +
  2. Choose Developer ID Application, then the G2 Sub-CA, and upload devid.csr.
  3. Download the certificate, then run:
       make devid-import CER=~/Downloads/developerID_application.cer
EOF
}

import_certificate() {
  local cer=${1/#\~/$HOME}
  local kc out team
  [ -f "$cer" ] || { echo "no such file: $cer" >&2; exit 1; }
  [ -f "$KEY" ] || { echo "no $KEY: the certificate must come from this Mac's request (make devid-csr)." >&2; exit 1; }
  kc="$(cd "$DIR" && pwd)/annotake-signing.keychain-db"
  [ -f "$kc" ] || { echo "no signing keychain at $kc; run make cert first." >&2; exit 1; }
  trap 'rm -f "$PEM" "$P12"' EXIT

  # Apple issues DER; accept PEM too.
  /usr/bin/openssl x509 -inform DER -in "$cer" -out "$PEM" 2>/dev/null \
    || /usr/bin/openssl x509 -inform PEM -in "$cer" -out "$PEM"
  if [ "$(/usr/bin/openssl x509 -noout -modulus -in "$PEM")" != "$(/usr/bin/openssl rsa -noout -modulus -in "$KEY")" ]; then
    echo "$cer wasn't issued for this Mac's request ($CSR)." >&2
    exit 1
  fi
  (umask 077 && /usr/bin/openssl pkcs12 -export -inkey "$KEY" -in "$PEM" -out "$P12" -passout "pass:$PASS")

  # Without Xcode nothing installs Apple's intermediate, and codesign can't build the chain without it.
  curl -fsSL --retry 3 "$INTERMEDIATE_URL" -o "$DIR/DeveloperIDG2CA.cer"

  security unlock-keychain -p "$PASS" "$kc"
  security import "$P12" -k "$kc" -P "$PASS" -T /usr/bin/codesign
  if ! out=$(security import "$DIR/DeveloperIDG2CA.cer" -k "$kc" 2>&1); then
    case "$out" in
      *"already exists"*) ;;
      *) echo "$out" >&2; exit 1 ;;
    esac
  fi
  # As make-cert.sh does, so signing never prompts.
  security set-key-partition-list -S apple-tool:,apple: -s -k "$PASS" "$kc" >/dev/null

  # The team id is the certificate's organizational unit.
  team=$(/usr/bin/openssl x509 -noout -subject -in "$PEM" | grep -oE 'OU ?= ?[A-Z0-9]{10}' | head -1 | grep -oE '[A-Z0-9]{10}$' || true)
  if [ -n "$team" ]; then
    echo "$team" > "$DIR/team-id"
  else
    echo "warning: no team id in the certificate's subject" >&2
  fi
  rm -f "$KEY"
  security find-identity -v -p codesigning "$kc"
}

case "${1:-}" in
  csr) [ $# -eq 1 ] || usage; csr ;;
  import) [ $# -eq 2 ] || usage; import_certificate "$2" ;;
  *) usage ;;
esac
