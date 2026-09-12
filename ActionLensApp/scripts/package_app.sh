#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/arm64-apple-macosx/debug"
EXECUTABLE="$BUILD_DIR/ActionLensApp"
APP_NAME="ActionLens.app"
APP_DIR="$ROOT_DIR/dist/$APP_NAME"
INSTALL_DIR="${HOME}/Applications/$APP_NAME"

if [ ! -f "$EXECUTABLE" ]; then
  echo "Building ActionLensApp first..."
  swift build --disable-sandbox --package-path "$ROOT_DIR"
fi

mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"
mkdir -p "$(dirname "$INSTALL_DIR")"

cp "$EXECUTABLE" "$APP_DIR/Contents/MacOS/ActionLens"
chmod +x "$APP_DIR/Contents/MacOS/ActionLens"

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>ActionLens</string>
  <key>CFBundleIdentifier</key>
  <string>com.sjeffzhang.actionlens</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>ActionLens</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true
fi

rm -rf "$INSTALL_DIR"
cp -R "$APP_DIR" "$INSTALL_DIR"

echo "Packaged app:"
echo "  $APP_DIR"
echo "Installed app:"
echo "  $INSTALL_DIR"
echo
echo "Launch with:"
echo "  open \"$INSTALL_DIR\""
