#!/bin/bash
# Builds NetBlocker.app (universal, ad-hoc signed) into dist/
set -euo pipefail
cd "$(dirname "$0")/.."

APP=NetBlocker
VERSION="${VERSION:-0.1.0}"

echo "==> swift build (release, universal)"
if swift build -c release --arch arm64 --arch x86_64 2>/dev/null; then
    BIN=".build/apple/Products/Release/$APP"
else
    echo "    universal build unavailable, falling back to native arch"
    swift build -c release
    BIN=".build/release/$APP"
fi

echo "==> assembling dist/$APP.app"
rm -rf "dist/$APP.app"
mkdir -p "dist/$APP.app/Contents/MacOS" "dist/$APP.app/Contents/Resources"
cp "$BIN" "dist/$APP.app/Contents/MacOS/$APP"
cp assets/AppIcon.icns "dist/$APP.app/Contents/Resources/AppIcon.icns"

cat > "dist/$APP.app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>$APP</string>
    <key>CFBundleIdentifier</key><string>dev.grainca.netblocker</string>
    <key>CFBundleName</key><string>$APP</string>
    <key>CFBundleDisplayName</key><string>$APP</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>MIT License</string>
</dict>
</plist>
PLIST

echo "==> ad-hoc codesign"
codesign --force --sign - "dist/$APP.app"

echo "==> done: dist/$APP.app"
