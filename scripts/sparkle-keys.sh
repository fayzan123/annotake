#!/bin/bash
# Sparkle's EdDSA key for signing updates (spec §9). Idempotent: an existing key is reused.
# - The private key lives in the login keychain, under its own account, and in .signing/sparkle-private-key,
#   which release.sh signs with (sign_update --ed-key-file), so signing never prompts. Back it up: losing it
#   means existing installs can never be updated.
# - The public key goes to Resources/sparkle-public-key.txt, which is committed, and from there into Info.plist.
set -euo pipefail
cd "$(dirname "$0")/.."
ACCOUNT=annotake
PUBLIC=Resources/sparkle-public-key.txt
PRIVATE=.signing/sparkle-private-key
TOOL=$(find .build/artifacts -type f -name generate_keys -print -quit 2>/dev/null || true)
if [ -z "$TOOL" ]; then
  echo "Sparkle's tools aren't in .build/artifacts; run swift package resolve first." >&2
  exit 1
fi
mkdir -p .signing Resources
if [ -f "$PRIVATE" ] && ! "$TOOL" --account "$ACCOUNT" -p >/dev/null 2>&1; then
  # The keychain doesn't have it (another Mac, say): put the backed-up key back.
  "$TOOL" --account "$ACCOUNT" -f "$PRIVATE"
fi
"$TOOL" --account "$ACCOUNT"
"$TOOL" --account "$ACCOUNT" -p > "$PUBLIC"
if [ ! -f "$PRIVATE" ]; then
  (umask 077 && "$TOOL" --account "$ACCOUNT" -x "$PRIVATE")
fi
echo "public key $(cat "$PUBLIC"), in $PUBLIC: commit it"
echo "private key in the login keychain (account $ACCOUNT) and $PRIVATE: back it up, never commit it"
