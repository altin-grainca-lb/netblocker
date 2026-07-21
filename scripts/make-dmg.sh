#!/bin/bash
# Packages dist/NetBlocker.app into dist/NetBlocker-<version>.dmg
set -euo pipefail
cd "$(dirname "$0")/.."

APP=NetBlocker
VERSION="${VERSION:-0.3.0}"
DMG="dist/$APP-$VERSION.dmg"

[[ -d "dist/$APP.app" ]] || { echo "run scripts/build-app.sh first"; exit 1; }

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

cp -R "dist/$APP.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
hdiutil create -volname "$APP" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
echo "==> done: $DMG"
