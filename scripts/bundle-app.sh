#!/bin/bash
# Usage: bundle-app.sh <executable> <AppName> <bundle-id> <out-dir>
set -euo pipefail
if [ $# -ne 4 ]; then
  echo "usage: $0 <executable> <AppName> <bundle-id> <out-dir>" >&2; exit 1
fi
EXE=$1; NAME=$2; ID=$3; OUT=$4
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KC="$ROOT/.signing/annotake-signing.keychain-db"
APP="$OUT/$NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$EXE" "$APP/Contents/MacOS/$NAME"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleIdentifier</key><string>$ID</string>
	<key>CFBundleName</key><string>$NAME</string>
	<key>CFBundleExecutable</key><string>$NAME</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>0.0.1</string>
	<key>CFBundleVersion</key><string>1</string>
	<key>LSMinimumSystemVersion</key><string>15.0</string>
	<key>LSUIElement</key><true/>
	<key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
plutil -lint "$APP/Contents/Info.plist" >/dev/null
# ~/Documents may be synced by iCloud Drive, which tags new bundles with Finder/file-provider
# attributes that codesign rejects ("resource fork, Finder information, or similar detritus").
# It can tag the bundle again between the strip and the signing, so try a few times.
security unlock-keychain -p annotake-local "$KC"
for attempt in 1 2 3; do
  xattr -cr "$APP"
  if codesign --force --options runtime --timestamp=none --keychain "$KC" --sign "Annotake Local Signing" "$APP"; then
    break
  fi
  if [ "$attempt" -eq 3 ]; then exit 1; fi
  echo "signing attempt $attempt failed; retrying" >&2
  sleep 1
done
codesign --verify --verbose=2 "$APP"
