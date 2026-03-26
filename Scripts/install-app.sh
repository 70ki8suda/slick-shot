#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRATCH_PATH="${SCRATCH_PATH:-/tmp/slickshot-app-install}"
BUILD_CONFIG="${BUILD_CONFIG:-release}"
PRODUCT_DIR="$SCRATCH_PATH/arm64-apple-macosx/$BUILD_CONFIG"
APP_DIR="$HOME/Applications/SlickShot.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
EXECUTABLE_PATH="$PRODUCT_DIR/SlickShotApp"

mkdir -p "$HOME/Applications"

swift build \
  --package-path "$ROOT_DIR" \
  --scratch-path "$SCRATCH_PATH" \
  -c "$BUILD_CONFIG"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$EXECUTABLE_PATH" "$MACOS_DIR/SlickShot"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>SlickShot</string>
  <key>CFBundleExecutable</key>
  <string>SlickShot</string>
  <key>CFBundleIdentifier</key>
  <string>com.yasudanaoki.SlickShot</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>SlickShot</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

touch "$APP_DIR"
echo "Installed $APP_DIR"
