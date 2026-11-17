#!/bin/bash
# Bundle the compiled Ports On executable into a minimal .app for running.
# Usage: ./bundle.sh
set -euo pipefail
CONFIG="${1:-debug}"
BUNDLE_ID="dev.mhiqram.portson"
APP_NAME="Ports On"

# Build the universal binary (arm64 + x86_64). SwiftPM puts a multi-arch build in
# .build/out/Products/<Config>/, NOT .build/<config>/ — ask it where rather than guess.
swift build -c "$CONFIG" --arch arm64 --arch x86_64
BIN_DIR="$(swift build --show-bin-path -c "$CONFIG" --arch arm64 --arch x86_64)"
BIN="$BIN_DIR/PortsOn"
[[ -f "$BIN" ]] || { echo "error: expected built binary at $BIN" >&2; exit 1; }

APP=".build/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>PortsOn</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>LSUIElement</key><false/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

cp "$BIN" "$APP/Contents/MacOS/PortsOn"

# App icon (shows in dock, Finder, and the DMG window).
if [[ -f "Resources/AppIcon.icns" ]]; then
  cp "Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

echo "Architectures: $(lipo -archs "$APP/Contents/MacOS/PortsOn")"
echo "Bundled: $APP"
echo "Run it with: open \"$APP\""
