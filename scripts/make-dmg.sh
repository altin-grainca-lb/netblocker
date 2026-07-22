#!/bin/bash
# Packages dist/NetBlocker.app into dist/NetBlocker-<version>.dmg with a
# Finder-styled installer window: big icons, background art, an arrow from
# the app to Applications. Icon positions here must match the arrow drawn
# in scripts/make-dmg-background.swift (assets/dmg-background.png).
set -euo pipefail
cd "$(dirname "$0")/.."

APP=NetBlocker
VOLNAME="$APP"
VERSION="${VERSION:-0.3.0}"
DMG="dist/$APP-$VERSION.dmg"
RW_DMG="dist/.$APP-rw.dmg"

[[ -d "dist/$APP.app" ]] || { echo "run scripts/build-app.sh first"; exit 1; }

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"; hdiutil detach "/Volumes/$VOLNAME" >/dev/null 2>&1 || true' EXIT

cp -R "dist/$APP.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
mkdir -p "$STAGE/.background"
cp assets/dmg-background.png "$STAGE/.background/background.png"

rm -f "$DMG" "$RW_DMG"
hdiutil create -volname "$VOLNAME" -srcfolder "$STAGE" -ov -format UDRW -fs HFS+ "$RW_DMG" >/dev/null

MOUNT_DIR="/Volumes/$VOLNAME"
hdiutil attach "$RW_DMG" -noautoopen >/dev/null

# Window bounds/icon positions are Finder coordinates (origin top-left).
osascript <<OSA
tell application "Finder"
    tell disk "$VOLNAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {400, 100, 1060, 540}
        set theViewOptions to icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 128
        set background picture of theViewOptions to file ".background:background.png"
        set position of item "$APP.app" of container window to {180, 190}
        set position of item "Applications" of container window to {480, 190}
        update without registering applications
        delay 1
        close
    end tell
end tell
OSA

# Give Finder's writes (.DS_Store etc.) a moment to land before detaching.
sync
sleep 1
hdiutil detach "$MOUNT_DIR" >/dev/null

hdiutil convert "$RW_DMG" -format UDZO -ov -o "$DMG" >/dev/null
rm -f "$RW_DMG"
echo "==> done: $DMG"
