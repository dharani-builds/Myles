#!/usr/bin/env bash
#
# Build a distributable .dmg from an exported Myles.app.
#
#   ./scripts/make-dmg.sh /path/to/Myles.app
#   ./scripts/make-dmg.sh                      # defaults to /Applications/Myles.app
#
# Produces  dist/Myles-<version>.dmg  — a disk image that opens to a window
# with Myles on the left and an Applications shortcut on the right, so
# installing is a single drag.
#
# Uses only hdiutil + osascript, both built into macOS. No Homebrew, no
# create-dmg, nothing to install first.
#
# NOTE ON SIGNING
#   This script does not sign anything — it packages whatever you hand it.
#   With a free Apple Developer account the app carries an "Apple
#   Development" certificate, which Gatekeeper flags on other people's
#   Macs: they'll need Privacy & Security → "Open Anyway" the first time.
#   That step disappears only with a paid Developer ID certificate plus
#   notarization.

set -euo pipefail

APP_PATH="${1:-/Applications/Myles.app}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$REPO_ROOT/dist"
VOL_NAME="Myles"

# --- sanity -----------------------------------------------------------------

if [[ ! -d "$APP_PATH" ]]; then
  echo "error: no app bundle at $APP_PATH" >&2
  echo "       export one first: Xcode → Product → Archive → Distribute App → Custom → Copy App" >&2
  exit 1
fi

VERSION="$(defaults read "$APP_PATH/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "0.0")"
DMG_PATH="$OUT_DIR/Myles-$VERSION.dmg"

echo "app      : $APP_PATH"
echo "version  : $VERSION"
echo "output   : $DMG_PATH"

# Report the signing situation rather than hiding it — the answer changes
# what the person installing this will experience.
echo -n "signing  : "
codesign -dvv "$APP_PATH" 2>&1 | grep '^Authority=' | head -1 | sed 's/^Authority=//' || echo "unsigned"
if spctl -a "$APP_PATH" >/dev/null 2>&1; then
  echo "gatekeep : accepted — installs without warnings"
else
  echo "gatekeep : rejected — recipients need Privacy & Security → Open Anyway"
fi

# --- stage ------------------------------------------------------------------

mkdir -p "$OUT_DIR"
rm -f "$DMG_PATH"

# Two separate temp dirs on purpose: WORK holds the intermediate .dmg, and
# STAGE holds only what should end up inside the image. Nesting the two
# makes hdiutil try to image the file it's currently writing.
WORK="$(mktemp -d)"
STAGE="$WORK/stage"
mkdir -p "$STAGE"
trap 'if [[ -n "${MOUNT_DIR:-}" ]]; then hdiutil detach "$MOUNT_DIR" -quiet 2>/dev/null || true; fi; rm -rf "$WORK"' EXIT

cp -R "$APP_PATH" "$STAGE/Myles.app"
ln -s /Applications "$STAGE/Applications"

# --- build a read/write image we can style, then compress it ----------------

RW_DMG="$WORK/rw.dmg"
hdiutil create \
  -srcfolder "$STAGE" \
  -volname "$VOL_NAME" \
  -fs HFS+ \
  -format UDRW \
  -size 200m \
  "$RW_DMG" >/dev/null

MOUNT_DIR="$(mktemp -d)"
hdiutil attach "$RW_DMG" -quiet -nobrowse -mountpoint "$MOUNT_DIR"

# Lay the window out so the drag gesture is obvious on open. Failures here
# are cosmetic only — a DMG with default styling still installs fine — so
# don't let AppleScript flakiness kill the build.
osascript <<EOF 2>/dev/null || echo "note: window styling skipped (cosmetic only)"
tell application "Finder"
  tell disk "$VOL_NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 150, 800, 530}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 128
    set position of item "Myles.app" of container window to {150, 190}
    set position of item "Applications" of container window to {450, 190}
    close
    open
    update without registering applications
    delay 1
  end tell
end tell
EOF

sync
hdiutil detach "$MOUNT_DIR" -quiet
MOUNT_DIR=""

hdiutil convert "$RW_DMG" -quiet -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH"

echo
echo "done: $DMG_PATH  ($(du -h "$DMG_PATH" | cut -f1))"
