#!/bin/sh
# Installs Annotake's latest build, or updates the one you have.
#
#   curl -fsSL https://raw.githubusercontent.com/fayzan123/annotake-releases/main/install.sh | sh
#
# It downloads Annotake.zip from the latest release, checks its signature, puts Annotake in /Applications
# (or ~/Applications if you can't write there), and opens Annotake. Annotake is recognized by its bundle id,
# never by name alone, so another app that shares the name is never touched.
#
# For testing: ANNOTAKE_INSTALL_DIR=<folder> installs there instead, and quits, opens, and removes nothing.
# ANNOTAKE_ZIP_URL=<url> downloads another zip, file:// included.

set -eu

main() {
  zip_url="${ANNOTAKE_ZIP_URL:-https://github.com/fayzan123/annotake-releases/releases/latest/download/Annotake.zip}"

  [ "$(uname -s)" = Darwin ] || fail "this installer is for macOS."
  version=$(sw_vers -productVersion)
  [ "${version%%.*}" -ge 15 ] || fail "Annotake needs macOS 15 or later, and this Mac has macOS $version."

  testing=0
  if [ -n "${ANNOTAKE_INSTALL_DIR:-}" ]; then
    dest=$ANNOTAKE_INSTALL_DIR
    testing=1
  elif [ -w /Applications ]; then
    dest=/Applications
  else
    dest="$HOME/Applications"
  fi

  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT

  echo "Downloading Annotake…"
  curl -fsSL "$zip_url" -o "$tmp/Annotake.zip" || fail "the download failed. Check your connection and run the command again."
  ditto -x -k "$tmp/Annotake.zip" "$tmp/unzipped" || fail "couldn't unpack the download. Run the command again."
  app="$tmp/unzipped/Annotake.app"
  codesign --verify --strict --deep "$app" 2>/dev/null || fail "the download looks damaged: its signature doesn't check out. Run the command again."

  if [ "$testing" = 0 ]; then
    quit Annotake com.fayzanmalik.annotake
  fi

  mkdir -p "$dest"
  rm -rf "$dest/Annotake.app"
  ditto "$app" "$dest/Annotake.app"
  xattr -dr com.apple.quarantine "$dest/Annotake.app" 2>/dev/null || true

  if [ "$testing" = 1 ]; then
    echo "Installed in $dest (test run: nothing quit, opened, or removed)."
    return
  fi

  # Keep one copy: another in the other Applications folder would confuse launch at login.
  for folder in /Applications "$HOME/Applications"; do
    if [ "$folder" != "$dest" ] && [ "$(bundle_id "$folder/Annotake.app")" = com.fayzanmalik.annotake ]; then
      rm -rf "$folder/Annotake.app" 2>/dev/null || true
    fi
  done

  open "$dest/Annotake.app"
  echo "Annotake is installed in $dest and opening now."
  echo "Follow its first run: three permissions, then a practice recording."
  echo "It updates itself; running this command again also updates it."
}

# Quits a running app, found by its bundle id: politely, then after 5 s, firmly.
quit() {
  pid=$(running_pid "$2")
  if [ -n "$pid" ]; then
    echo "Quitting the $1 that's running…"
    osascript -e "tell application id \"$2\" to quit" >/dev/null 2>&1 || true
    i=0
    while kill -0 "$pid" 2>/dev/null && [ "$i" -lt 50 ]; do
      sleep 0.1
      i=$((i + 1))
    done
    kill "$pid" 2>/dev/null || true
  fi
}

# The bundle id in an app's Info.plist, or nothing when there's no app there.
bundle_id() {
  [ -f "$1/Contents/Info.plist" ] || return 0
  /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$1/Contents/Info.plist" 2>/dev/null || true
}

# The process id of the running app with this bundle id, or nothing.
running_pid() {
  lsappinfo info -only pid -app "$1" 2>/dev/null | sed -n 's/^"pid"=\([0-9][0-9]*\)$/\1/p'
}

fail() {
  echo "Annotake: $*" >&2
  exit 1
}

main "$@"
