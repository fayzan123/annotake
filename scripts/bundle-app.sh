#!/bin/bash
# Usage: VERSION=<x.y.z> BUILD=<n> FRAMEWORKS_DIR=<dir> [RELEASE=1] [SIGN_IDENTITY=<name>] \
#          bundle-app.sh <executable> <AppName> <bundle-id> <out-dir>
# VERSION and BUILD become CFBundleShortVersionString and CFBundleVersion. FRAMEWORKS_DIR holds the
# Sparkle.framework SwiftPM built next to the executable. The Makefile passes all three.
#
# Always signs, with the hardened runtime: with SIGN_IDENTITY when it's set, otherwise the signing keychain's
# Developer ID Application identity, otherwise "Annotake Local Signing". RELEASE=1 requires the Developer ID
# and a secure timestamp; every other build uses --timestamp=none (spec §9).
set -euo pipefail
USAGE="usage: VERSION=<x.y.z> BUILD=<n> FRAMEWORKS_DIR=<dir> [RELEASE=1] $0 <executable> <AppName> <bundle-id> <out-dir>"
if [ $# -ne 4 ] || [ -z "${VERSION:-}" ] || [ -z "${BUILD:-}" ] || [ -z "${FRAMEWORKS_DIR:-}" ]; then
  echo "$USAGE" >&2; exit 1
fi
EXE=$1; NAME=$2; ID=$3; OUT=$4
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KC="$ROOT/.signing/annotake-signing.keychain-db"
LOCAL_IDENTITY="Annotake Local Signing"
ICON="$ROOT/Resources/AppIcon.icns"
SPARKLE="$FRAMEWORKS_DIR/Sparkle.framework"
PUBLIC_KEY_FILE="$ROOT/Resources/sparkle-public-key.txt"
FEED_URL=https://raw.githubusercontent.com/fayzan123/annotake-releases/main/appcast.xml

# The identity, first, so a release without a Developer ID fails before anything is built.
security unlock-keychain -p annotake-local "$KC"
# codesign builds the certificate chain from the search list, and the project folder can move (it's renamed
# at Checkpoint 3), so the keychain's current path must be on the list.
if ! security list-keychains -d user | grep -qF "\"$KC\""; then
  security list-keychains -d user -s "$KC" $(security list-keychains -d user | tr -d '"')
fi
DEVELOPER_ID=$(security find-identity -v -p codesigning "$KC" \
  | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)
IDENTITY=${SIGN_IDENTITY:-${DEVELOPER_ID:-$LOCAL_IDENTITY}}
if [ "${RELEASE:-0}" = 1 ]; then
  case "$IDENTITY" in
    "Developer ID Application: "*) ;;
    *) echo "RELEASE=1 needs a Developer ID: $KC has no valid \"Developer ID Application\" identity" \
         "(make devid-csr, then make devid-import)." >&2
       exit 1 ;;
  esac
  TIMESTAMP=--timestamp
else
  TIMESTAMP=--timestamp=none
fi
if [ ! -d "$SPARKLE" ]; then
  echo "missing $SPARKLE: the executable links Sparkle and can't launch without it" >&2; exit 1
fi
# Sparkle checks every update against this key. Without it updates are refused, which a release can't ship.
if [ -s "$PUBLIC_KEY_FILE" ]; then
  PUBLIC_KEY_ENTRY="<key>SUPublicEDKey</key><string>$(tr -d '[:space:]' < "$PUBLIC_KEY_FILE")</string>"
elif [ "${RELEASE:-0}" = 1 ]; then
  echo "RELEASE=1 needs Sparkle's public key in $PUBLIC_KEY_FILE (make sparkle-keys)." >&2; exit 1
else
  echo "warning: no $PUBLIC_KEY_FILE, so Info.plist has no SUPublicEDKey (make sparkle-keys)" >&2
  PUBLIC_KEY_ENTRY=""
fi

# iCloud Drive syncs ~/Documents, and it tags bundle folders with Finder information as they change, faster
# than they can be stripped and signed; codesign rejects that. So the app is assembled, signed, and checked
# in a temporary folder outside it, then copied to OUT.
STAGE=$(mktemp -d "${TMPDIR:-/tmp}/annotake-bundle.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT
APP="$STAGE/$NAME.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$EXE" "$APP/Contents/MacOS/$NAME"
if [ ! -f "$ICON" ]; then
  echo "missing $ICON; run make icon" >&2; exit 1
fi
cp "$ICON" "$APP/Contents/Resources/AppIcon.icns"
mkdir -p "$APP/Contents/Frameworks"
ditto "$SPARKLE" "$APP/Contents/Frameworks/Sparkle.framework"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleIdentifier</key><string>$ID</string>
	<key>CFBundleName</key><string>$NAME</string>
	<key>CFBundleExecutable</key><string>$NAME</string>
	<key>CFBundleIconFile</key><string>AppIcon</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>$VERSION</string>
	<key>CFBundleVersion</key><string>$BUILD</string>
	<key>LSMinimumSystemVersion</key><string>15.0</string>
	<key>LSUIElement</key><true/>
	<key>NSHighResolutionCapable</key><true/>
	<key>SUFeedURL</key><string>$FEED_URL</string>
	<key>SUEnableAutomaticChecks</key><true/>
	<key>SUScheduledCheckInterval</key><integer>86400</integer>
	<key>SUEnableSystemProfiling</key><false/>
	$PUBLIC_KEY_ENTRY
</dict>
</plist>
PLIST
plutil -lint "$APP/Contents/Info.plist" >/dev/null

# Signs one piece of code, nested code first and never --deep. Copied files can carry Finder information,
# which codesign rejects ("resource fork, Finder information, or similar detritus"), so strip it first, and
# try up to three times.
sign() {
  local target=$1; shift
  local attempt
  for attempt in 1 2 3; do
    xattr -cr "$APP"
    if codesign --force --options runtime "$TIMESTAMP" --keychain "$KC" --sign "$IDENTITY" "$@" "$target"; then
      return 0
    fi
    if [ "$attempt" -eq 3 ]; then return 1; fi
    echo "signing attempt $attempt failed; retrying" >&2
    sleep 1
  done
}

verify() {
  local attempt
  for attempt in 1 2 3; do
    xattr -cr "$APP"
    if codesign --verify --deep --strict --verbose=2 "$APP"; then
      return 0
    fi
    if [ "$attempt" -eq 3 ]; then return 1; fi
    echo "verification attempt $attempt failed; retrying" >&2
    sleep 1
  done
}

echo "signing with \"$IDENTITY\" ($TIMESTAMP)"
# Sparkle's nested code, inside out, as Sparkle's documentation does it; then the app.
SPARKLE_B="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
sign "$SPARKLE_B/XPCServices/Installer.xpc"
sign "$SPARKLE_B/XPCServices/Downloader.xpc" --preserve-metadata=entitlements
sign "$SPARKLE_B/Autoupdate"
sign "$SPARKLE_B/Updater.app"
sign "$APP/Contents/Frameworks/Sparkle.framework"
# The hardened runtime loads only libraries signed by the app's own team. A self-signed identity has no team,
# so without a Developer ID the app opts out of library validation to load its own copy of Sparkle. Developer
# ID builds, releases included, never do.
case "$IDENTITY" in
  "Developer ID Application: "*)
    sign "$APP" ;;
  *)
    cat > "$STAGE/local.entitlements" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.cs.disable-library-validation</key><true/>
</dict>
</plist>
PLIST
    sign "$APP" --entitlements "$STAGE/local.entitlements" ;;
esac
verify

rm -rf "${OUT:?}/$NAME.app"
mkdir -p "$OUT"
ditto "$APP" "$OUT/$NAME.app"
# Not --strict: iCloud Drive may tag the copy again, which doesn't touch the signature.
codesign --verify --deep --verbose=2 "$OUT/$NAME.app"
