#!/bin/sh
# Installs Annotake's latest build, or updates the one you have. It also replaces Flipbook, its old name.
#
#   curl -fsSL https://raw.githubusercontent.com/fayzan123/annotake-releases/main/install.sh | sh
#
# It downloads Annotake.zip from the latest release, checks its signature, puts Annotake in /Applications
# (or ~/Applications if you can't write there), removes Flipbook, and opens Annotake.
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
    quit Flipbook com.fayzanmalik.flipbook
  fi

  mkdir -p "$dest"
  rm -rf "$dest/Annotake.app"
  ditto "$app" "$dest/Annotake.app"
  xattr -dr com.apple.quarantine "$dest/Annotake.app" 2>/dev/null || true

  if [ "$testing" = 1 ]; then
    echo "Installed in $dest (test run: nothing quit, opened, or removed)."
    return
  fi

  # Keep one copy: another in the other Applications folder would confuse launch at login. Flipbook goes
  # too, from both, so only Annotake answers Right ⌘, and its old permission rows leave System Settings.
  replaced=0
  for folder in /Applications "$HOME/Applications"; do
    if [ "$folder" != "$dest" ] && [ -d "$folder/Annotake.app" ]; then
      rm -rf "$folder/Annotake.app" 2>/dev/null || true
    fi
    if [ -d "$folder/Flipbook.app" ]; then
      rm -rf "$folder/Flipbook.app" 2>/dev/null && replaced=1
    fi
  done
  tccutil reset All com.fayzanmalik.flipbook >/dev/null 2>&1 || true
  if [ "$replaced" = 1 ]; then
    echo "Flipbook, Annotake's old name, was removed."
  fi

  open "$dest/Annotake.app"
  echo "Annotake is installed in $dest and opening now."
  echo "Follow its first run: three permissions, then a practice recording."
  echo "It updates itself; running this command again also updates it."
}

# Quits a running app by name and bundle id: politely, then after 5 s, firmly.
quit() {
  if pgrep -xq "$1"; then
    echo "Quitting the $1 that's running…"
    osascript -e "tell application id \"$2\" to quit" >/dev/null 2>&1 || true
    i=0
    while pgrep -xq "$1" && [ "$i" -lt 50 ]; do
      sleep 0.1
      i=$((i + 1))
    done
    pkill -x "$1" 2>/dev/null || true
  fi
}

fail() {
  echo "Annotake: $*" >&2
  exit 1
}

main "$@"
