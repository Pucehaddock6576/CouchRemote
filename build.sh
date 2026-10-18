#!/bin/bash
# Builds "Couch Remote.app" using the free Xcode Command Line Tools.
#   1. xcode-select --install      (one time)
#   2. cd into this folder and run:  bash build.sh
set -e
cd "$(dirname "$0")"

APP="Couch Remote.app"
BIN="CouchRemote"
SDK=$(xcrun --show-sdk-path --sdk macosx 2>/dev/null || true)
if [ -z "$SDK" ]; then
  echo "❌ macOS SDK not found. Run: xcode-select --install"; exit 1
fi
ARCH=$(uname -m)
TARGET="$ARCH-apple-macosx13.0"

echo "▶︎ Compiling for ${TARGET}..."
mkdir -p build
swiftc -O -sdk "$SDK" -target "$TARGET" \
  -import-objc-header Support/MultitouchBridge.h \
  -framework AppKit -framework SwiftUI -framework IOKit -framework CoreGraphics \
  -framework ServiceManagement -framework Carbon -framework EventKit -framework CoreAudio -framework AudioToolbox -framework Network -framework CoreImage -framework WebKit \
  -o "build/$BIN" Sources/*.swift

echo "▶︎ Packaging ${APP}..."
rm -rf "build/$APP"
mkdir -p "build/$APP/Contents/MacOS" "build/$APP/Contents/Resources"
cp "build/$BIN" "build/$APP/Contents/MacOS/$BIN"
if [ -f "Assets/Brand/CouchRemote.icns" ]; then
  cp "Assets/Brand/CouchRemote.icns" "build/$APP/Contents/Resources/CouchRemote.icns"
fi
cat > "build/$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>CouchRemote</string>
  <key>CFBundleIdentifier</key><string>local.couchremote.app</string>
  <key>CFBundleName</key><string>Couch Remote</string>
  <key>CFBundleDisplayName</key><string>Couch Remote</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>CouchRemote</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>Couch Remote controls apps like Music, Safari and Keynote when you press remote buttons.</string>
  <key>NSBluetoothAlwaysUsageDescription</key><string>Couch Remote reads your Siri Remote over Bluetooth.</string>
  <key>NSCalendarsUsageDescription</key><string>Couch Remote can show your next calendar event on Big Screen (only if you turn it on).</string>
  <key>NSCalendarsFullAccessUsageDescription</key><string>Couch Remote can show your next calendar event on Big Screen (only if you turn it on).</string>
</dict></plist>
PLIST

# Ad-hoc signature so macOS can remember the permissions you grant.
codesign --force --deep --sign - "build/$APP" >/dev/null 2>&1 || true

echo ""
echo "✅ Built: build/$APP"
echo "   Move it to /Applications, open it, then follow the Setup checklist in its window."
echo "   Tip: after rebuilding, macOS may ask you to re-allow Accessibility and Input Monitoring."
