#!/bin/bash
# make release NOTES="what changed" [DRY_RUN=1] [NOTARY_TIMEOUT=30m]  (spec §9)
#
# Builds Annotake for release, notarizes and staples it, makes the zip (Sparkle's archive, and what install.sh
# downloads) and the disk image, signs the zip for Sparkle, then publishes a GitHub release in
# fayzan123/annotake-releases with its appcast.xml, install.sh, and README.md. The zip, the disk image, and in
# a dry run the feed end up in build/release.
#
# DRY_RUN=1 runs it all locally without credentials: a build with whatever identity the keychain has, no
# notarization, and build/release/appcast.xml as a fresh feed instead of publishing.
# Publishing comes last, so any failure leaves the releases repo and its feed untouched.
#
# Apple can take minutes or hours to notarize, especially for a new developer account. When it takes longer
# than NOTARY_TIMEOUT, the release stops before publishing, and running the same command again picks up
# where it left off: the signed app, the disk image, and Apple's submission ids stay in a work folder for this
# version and build until it's published, and anything Apple has notarized by then just gets its ticket stapled.
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
NOTARY_TIMEOUT=${NOTARY_TIMEOUT:-30m}
VERSION=$(cat VERSION)
BUILD=$(git rev-list --count HEAD)
TAG="v$VERSION-$BUILD"
DOWNLOAD="https://github.com/$REPO/releases/download/$TAG"

step() { printf '\n== %s\n' "$*"; }
fail() { echo "release: $*" >&2; exit 1; }
dry() { [ "$DRY_RUN" = 1 ]; }
# One field of notarytool's JSON output, or nothing.
field() { /usr/bin/python3 -c 'import json, sys; print(json.load(sys.stdin).get(sys.argv[1], ""))' "$1" 2>/dev/null || true; }

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
# so the release is put together in a temporary folder outside it (scripts/bundle-app.sh). A real release keeps
# that folder, one per version and build, until it's published; a dry run starts fresh every time.
if dry; then
  WORK=$(mktemp -d "${TMPDIR:-/tmp}/annotake-release-dry.XXXXXX")
  trap 'rm -rf "$WORK"' EXIT
else
  WORK="${TMPDIR:-/tmp}/annotake-release-$VERSION-$BUILD"
  mkdir -p "$WORK"
fi
APP="$WORK/Annotake.app"

# 2. Build, unless an earlier run of this release already did: its app is the one Apple may have notarized.
if [ -d "$APP" ] && ! dry; then
  step "Building: reusing the app an earlier run of $VERSION ($BUILD) built"
else
  step "Building"
  if dry; then make app; else make app RELEASE=1; fi
  rm -rf "$APP.partial"
  ditto --norsrc --noextattr --noacl build/Annotake.app "$APP.partial"
  mv "$APP.partial" "$APP"
fi
codesign --verify --deep --strict "$APP"
IDENTITY=$(codesign -dvv "$APP" 2>&1 | sed -n 's/^Authority=//p' | head -1)
echo "signed by: $IDENTITY"

# Gets Apple's ticket for <target> and staples it. When Apple already has one for this exact code (an earlier
# run's submission finished after that run stopped waiting), it's just stapled. Otherwise this waits on an earlier
# run's submission, or submits <upload>; anything but Accepted stops the release before it publishes.
notarize() {
  local target=$1 upload=$2 saved="$WORK/$3.notary-id" result id status
  if xcrun stapler staple "$target" >/dev/null 2>&1; then
    echo "Apple has already notarized $(basename "$target"); its ticket is stapled"
    return
  fi
  if [ -s "$saved" ]; then
    id=$(cat "$saved")
    echo "an earlier run submitted $(basename "$upload") as $id"
  else
    result=$(xcrun notarytool submit "$upload" --keychain-profile "$PROFILE" --output-format json) \
      || fail "couldn't upload $(basename "$upload") to Apple: $result"
    id=$(field id <<< "$result")
    [ -n "$id" ] || fail "Apple didn't return a submission id: $result"
    echo "$id" > "$saved"
    echo "uploaded $(basename "$upload") as $id"
  fi
  echo "waiting for Apple, up to $NOTARY_TIMEOUT (a new account's first submissions can take longer)…"
  result=$(xcrun notarytool wait "$id" --keychain-profile "$PROFILE" --timeout "$NOTARY_TIMEOUT" --output-format json) || true
  status=$(field status <<< "$result")
  case "$status" in
    Accepted)
      echo "notarized $(basename "$upload") ($id)" ;;
    "")
      fail "Apple is still notarizing $(basename "$upload") (submission $id). Nothing was published." \
           "Run the same command again later; it picks up where it left off." ;;
    *)
      printf '%s\n' "$result" >&2
      xcrun notarytool log "$id" --keychain-profile "$PROFILE" >&2 || true
      rm -f "$saved"
      fail "Apple's notarization of $(basename "$upload") ended with status '$status' (its log is above)" ;;
  esac
  xcrun stapler staple "$target"
}

# 3. Notarize the app.
if dry; then
  step "Notarizing the app: skipped in a dry run"
else
  step "Notarizing the app"
  ditto -c -k --keepParent --norsrc --noextattr --noacl "$APP" "$WORK/notarize.zip"
  notarize "$APP" "$WORK/notarize.zip" app
  xcrun stapler validate "$APP"
  spctl -a -t exec -vv "$APP" 2>&1 | tee "$WORK/spctl.txt"
  grep -q "source=Notarized Developer ID" "$WORK/spctl.txt" || fail "Gatekeeper doesn't see the app as notarized"
fi

# 4. The zip: Sparkle's archive, and what install.sh downloads.
step "Zipping"
ditto -c -k --keepParent --norsrc --noextattr --noacl "$APP" "$WORK/Annotake.zip"

# 5. The disk image, unless an earlier run already submitted one: that's the one Apple may have notarized.
step "Making the disk image"
DMG="$WORK/Annotake.dmg"
if [ -f "$DMG" ] && [ -s "$WORK/dmg.notary-id" ] && ! dry; then
  echo "reusing the disk image an earlier run submitted to Apple"
else
  rm -f "$DMG"
  # As a module, not through bin/dmgbuild, whose first line names the project folder's path: renaming the
  # folder would break it.
  "$VENV/bin/python3" -c 'import dmgbuild' 2>/dev/null || make dmg-venv
  "$VENV/bin/python3" -m dmgbuild -s scripts/dmg-settings.py -D app="$APP" -D icon="$ROOT/Resources/AppIcon.icns" \
    -D background="$ROOT/Resources/dmg-background.tiff" Annotake "$DMG"
  security unlock-keychain -p annotake-local "$KC"
  if dry; then TIMESTAMP=--timestamp=none; else TIMESTAMP=--timestamp; fi
  codesign --force --sign "$IDENTITY" --keychain "$KC" "$TIMESTAMP" "$DMG"
fi
codesign --verify --verbose=2 "$DMG"
if ! dry; then
  notarize "$DMG" "$DMG" dmg
  xcrun stapler validate "$DMG"
  spctl -a -t open --context context:primary-signature -vv "$DMG"
fi

# 6. The Sparkle signature: every update's zip must carry one from the key whose public half is in the app.
step "Signing the update for Sparkle"
SIGN_UPDATE=$(find .build/artifacts -type f -name sign_update -print -quit 2>/dev/null || true)
if [ -f "$SPARKLE_KEY" ] && [ -n "$SIGN_UPDATE" ]; then
  SIGNED=$("$SIGN_UPDATE" --ed-key-file "$SPARKLE_KEY" "$WORK/Annotake.zip")
  ED_SIGNATURE=$(printf '%s' "$SIGNED" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')
  LENGTH=$(printf '%s' "$SIGNED" | sed -n 's/.*length="\([0-9]*\)".*/\1/p')
  [ -n "$ED_SIGNATURE" ] && [ -n "$LENGTH" ] || fail "couldn't read sign_update's output: $SIGNED"
elif dry; then
  echo "warning: no $SPARKLE_KEY or sign_update, so the dry run's feed gets a placeholder signature" >&2
  ED_SIGNATURE=DRY-RUN-UNSIGNED
  LENGTH=$(stat -f%z "$WORK/Annotake.zip")
else
  fail "can't sign the update: $SPARKLE_KEY or Sparkle's sign_update is missing (make sparkle-keys)"
fi

rm -rf "$OUT"
mkdir -p "$OUT"
cp "$WORK/Annotake.zip" "$DMG" "$OUT/"
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
  rm -rf "$WORK"
fi

# 8. Where it is.
step "Done: Annotake $VERSION ($BUILD)"
echo "Disk image:      https://github.com/$REPO/releases/latest/download/Annotake.dmg"
echo "Install command: curl -fsSL https://raw.githubusercontent.com/$REPO/main/install.sh | sh"
(cd "$OUT" && shasum -a 256 Annotake.zip Annotake.dmg)
