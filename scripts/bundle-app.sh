#!/bin/bash
# Usage: VERSION=<x.y.z> BUILD=<n> [RELEASE=1] [SIGN_IDENTITY=<name>] bundle-app.sh <executable> <AppName> <bundle-id> <out-dir>
# VERSION and BUILD become CFBundleShortVersionString and CFBundleVersion; the Makefile passes them.
#
# Always signs, with the hardened runtime: with SIGN_IDENTITY when it's set, otherwise the signing keychain's
# Developer ID Application identity, otherwise "Annotake Local Signing". RELEASE=1 requires the Developer ID
# and a secure timestamp; every other build uses --timestamp=none (spec §9).
set -euo pipefail
USAGE="usage: VERSION=<x.y.z> BUILD=<n> [RELEASE=1] $0 <executable> <AppName> <bundle-id> <out-dir>"
if [ $# -ne 4 ] || [ -z "${VERSION:-}" ] || [ -z "${BUILD:-}" ]; then
  echo "$USAGE" >&2; exit 1
fi
EXE=$1; NAME=$2; ID=$3; OUT=$4
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KC="$ROOT/.signing/annotake-signing.keychain-db"
LOCAL_IDENTITY="Annotake Local Signing"
APP="$OUT/$NAME.app"
ICON="$ROOT/Resources/AppIcon.icns"

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

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$EXE" "$APP/Contents/MacOS/$NAME"
if [ ! -f "$ICON" ]; then
  echo "missing $ICON; run make icon" >&2; exit 1
fi
cp "$ICON" "$APP/Contents/Resources/AppIcon.icns"
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
</dict>
</plist>
PLIST
plutil -lint "$APP/Contents/Info.plist" >/dev/null

# Signs one piece of code, nested code first and never --deep. ~/Documents may be synced by iCloud Drive,
# which tags new bundles with Finder/file-provider attributes that codesign rejects ("resource fork, Finder
# information, or similar detritus"). It can tag the bundle again between the strip and the signing, so
# strip and try up to three times.
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

# The same tagging can land after the signing, and a strict check rejects it. It isn't part of the
# signature, so strip it and check again.
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
sign "$APP"
verify
