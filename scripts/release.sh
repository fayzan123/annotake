#!/bin/bash
# make release NOTES="what changed" [DRY_RUN=1]  (spec §9)
#
# Builds Annotake for release, notarizes and staples it, makes the zip (Sparkle's archive, and what install.sh
# downloads) and the disk image, signs the zip for Sparkle, then publishes a GitHub release in
# fayzan123/annotake-releases with its appcast.xml, install.sh, and README.md. The zip, the disk image, and in
# a dry run the feed end up in build/release.
#
# DRY_RUN=1 runs it all locally without credentials: a build with whatever identity the keychain has, no
# notarization, and build/release/appcast.xml as a fresh feed instead of publishing.
# Publishing comes last, so any failure leaves the releases repo and its feed untouched.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$PWD
REPO=fayzan123/annotake-releases
PROFILE=annotake-notary
KC="$ROOT/.signing/annotake-signing.keychain-db"
SPARKLE_KEY="$ROOT/.signing/sparkle-private-key"
OUT="$ROOT/build/release"
VENV="$ROOT/.build/dmgbuild-venv"
DRY_RUN=${DRY_RUN:-0}
NOTES=${NOTES:-}
VERSION=$(cat VERSION)
BUILD=$(git rev-list --count HEAD)
TAG="v$VERSION-$BUILD"
DOWNLOAD="https://github.com/$REPO/releases/download/$TAG"

step() { printf '\n== %s\n' "$*"; }
fail() { echo "release: $*" >&2; exit 1; }
dry() { [ "$DRY_RUN" = 1 ]; }

# 1. Preconditions.
[ -n "$NOTES" ] || fail 'NOTES is empty: make release NOTES="what changed"'
if dry; then
  step "Dry run of Annotake $VERSION ($BUILD): nothing is notarized or published"
else
  step "Checking before releasing Annotake $VERSION ($BUILD)"
  [ -z "$(git status --porcelain)" ] || fail "the git tree isn't clean"
  [ "$(git symbolic-ref --short HEAD)" = main ] || fail "not on main"
  git fetch -q origin main
  [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || fail "HEAD isn't origin/main: push main first"
  security find-identity -v -p codesigning "$KC" | grep -q '"Developer ID Application: ' \
    || fail "no Developer ID Application identity in $KC (make devid-csr, then make devid-import)"
  xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null \
    || fail "no notarization credentials (xcrun notarytool store-credentials $PROFILE …)"
  [ -f "$SPARKLE_KEY" ] || fail "no $SPARKLE_KEY (make sparkle-keys)"
  gh auth status >/dev/null 2>&1 || fail "gh isn't signed in (gh auth login)"
  gh repo view "$REPO" >/dev/null || fail "no $REPO on GitHub"
  if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then fail "$REPO already has $TAG"; fi
fi

# iCloud Drive tags bundles in ~/Documents with Finder information, which strict code-signing checks reject,
# so the release is put together in a temporary folder outside it (scripts/bundle-app.sh).
STAGE=$(mktemp -d "${TMPDIR:-/tmp}/annotake-release.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT

# 2. Build.
step "Building"
if dry; then make app; else make app RELEASE=1; fi
APP="$STAGE/Annotake.app"
ditto --norsrc --noextattr --noacl build/Annotake.app "$APP"
codesign --verify --deep --strict "$APP"
IDENTITY=$(codesign -dvv "$APP" 2>&1 | sed -n 's/^Authority=//p' | head -1)
echo "signed by: $IDENTITY"

# Submits a file to Apple and waits; anything but Accepted prints Apple's log and stops the release.
notarize() {
  local file=$1 result id status
  result=$(xcrun notarytool submit "$file" --keychain-profile "$PROFILE" --wait --timeout 30m --output-format json) || true
  id=$(printf '%s' "$result" | /usr/bin/python3 -c 'import json, sys; print(json.load(sys.stdin).get("id", ""))' 2>/dev/null || true)
  status=$(printf '%s' "$result" | /usr/bin/python3 -c 'import json, sys; print(json.load(sys.stdin).get("status", ""))' 2>/dev/null || true)
  if [ "$status" != Accepted ]; then
    printf '%s\n' "$result" >&2
    if [ -n "$id" ]; then xcrun notarytool log "$id" --keychain-profile "$PROFILE" >&2 || true; fi
    fail "notarizing $(basename "$file") ended with status '${status:-unknown}'"
  fi
  echo "notarized $(basename "$file") ($id)"
}

# 3. Notarize the app.
if dry; then
  step "Notarizing the app: skipped in a dry run"
else
  step "Notarizing the app"
  ditto -c -k --keepParent --norsrc --noextattr --noacl "$APP" "$STAGE/notarize.zip"
  notarize "$STAGE/notarize.zip"
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
  spctl -a -t exec -vv "$APP" 2>&1 | tee "$STAGE/spctl.txt"
  grep -q "source=Notarized Developer ID" "$STAGE/spctl.txt" || fail "Gatekeeper doesn't see the app as notarized"
fi

# 4. The zip: Sparkle's archive, and what install.sh downloads.
step "Zipping"
ditto -c -k --keepParent --norsrc --noextattr --noacl "$APP" "$STAGE/Annotake.zip"

# 5. The disk image.
step "Making the disk image"
[ -x "$VENV/bin/dmgbuild" ] || make dmg-venv
"$VENV/bin/dmgbuild" -s scripts/dmg-settings.py -D app="$APP" -D icon="$ROOT/Resources/AppIcon.icns" \
  -D background="$ROOT/Resources/dmg-background.tiff" Annotake "$STAGE/Annotake.dmg"
security unlock-keychain -p annotake-local "$KC"
if dry; then TIMESTAMP=--timestamp=none; else TIMESTAMP=--timestamp; fi
codesign --force --sign "$IDENTITY" --keychain "$KC" "$TIMESTAMP" "$STAGE/Annotake.dmg"
codesign --verify --verbose=2 "$STAGE/Annotake.dmg"
if ! dry; then
  notarize "$STAGE/Annotake.dmg"
  xcrun stapler staple "$STAGE/Annotake.dmg"
  xcrun stapler validate "$STAGE/Annotake.dmg"
  spctl -a -t open --context context:primary-signature -vv "$STAGE/Annotake.dmg"
fi

# 6. The Sparkle signature: every update's zip must carry one from the key whose public half is in the app.
step "Signing the update for Sparkle"
SIGN_UPDATE=$(find .build/artifacts -type f -name sign_update -print -quit 2>/dev/null || true)
if [ -f "$SPARKLE_KEY" ] && [ -n "$SIGN_UPDATE" ]; then
  SIGNED=$("$SIGN_UPDATE" --ed-key-file "$SPARKLE_KEY" "$STAGE/Annotake.zip")
  ED_SIGNATURE=$(printf '%s' "$SIGNED" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')
  LENGTH=$(printf '%s' "$SIGNED" | sed -n 's/.*length="\([0-9]*\)".*/\1/p')
  [ -n "$ED_SIGNATURE" ] && [ -n "$LENGTH" ] || fail "couldn't read sign_update's output: $SIGNED"
elif dry; then
  echo "warning: no $SPARKLE_KEY or sign_update, so the dry run's feed gets a placeholder signature" >&2
  ED_SIGNATURE=DRY-RUN-UNSIGNED
  LENGTH=$(stat -f%z "$STAGE/Annotake.zip")
else
  fail "can't sign the update: $SPARKLE_KEY or Sparkle's sign_update is missing (make sparkle-keys)"
fi

rm -rf "$OUT"
mkdir -p "$OUT"
cp "$STAGE/Annotake.zip" "$STAGE/Annotake.dmg" "$OUT/"
appcast() {
  swift run -q -c release annotake-appcast --feed "$1" --version "$VERSION" --build "$BUILD" \
    --url "$DOWNLOAD/Annotake.zip" --length "$LENGTH" --signature "$ED_SIGNATURE" --notes "$NOTES"
}

# 7. Publish.
if dry; then
  step "Publishing: skipped in a dry run; the feed it would get is $OUT/appcast.xml"
  appcast "$OUT/appcast.xml"
else
  step "Publishing $TAG"
  gh repo clone "$REPO" "$OUT/repo" -- --depth 1 -q
  # The feed and the files first, so nothing announces a release before it exists.
  appcast "$OUT/repo/appcast.xml"
  cp scripts/install.sh "$OUT/repo/install.sh"
  cp scripts/releases-README.md "$OUT/repo/README.md"
  git -C "$OUT/repo" add appcast.xml install.sh README.md
  git -C "$OUT/repo" commit -q -m "Annotake $VERSION ($BUILD)"
  gh release create "$TAG" "$OUT/Annotake.zip" "$OUT/Annotake.dmg" --repo "$REPO" \
    --title "Annotake $VERSION ($BUILD)" --notes "$NOTES" --latest
  git -C "$OUT/repo" push -q origin HEAD \
    || fail "the release exists, but the feed didn't reach GitHub: run git -C build/release/repo push"
fi

# 8. Where it is.
step "Done: Annotake $VERSION ($BUILD)"
echo "Disk image:      https://github.com/$REPO/releases/latest/download/Annotake.dmg"
echo "Install command: curl -fsSL https://raw.githubusercontent.com/$REPO/main/install.sh | sh"
(cd "$OUT" && shasum -a 256 Annotake.zip Annotake.dmg)
