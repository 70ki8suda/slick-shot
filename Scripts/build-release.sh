#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRATCH_PATH="${SCRATCH_PATH:-$ROOT_DIR/.build-release}"
BUILD_CONFIG="${BUILD_CONFIG:-release}"
PRODUCT_DIR="$SCRATCH_PATH/arm64-apple-macosx/$BUILD_CONFIG"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"
APP_DIR="$DIST_DIR/SlickShot.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"
EXECUTABLE_PATH="$PRODUCT_DIR/SlickShotApp"
ICONSET_DIR="$ROOT_DIR/Resources/AppIcon.iconset"
ICON_FILE="$RESOURCES_DIR/AppIcon.icns"

DEVELOPER_ID_APP="${SLICKSHOT_DEVELOPER_ID_APP:-}"
NOTARY_PROFILE="${SLICKSHOT_NOTARY_PROFILE:-}"
SPARKLE_FEED_URL="${SLICKSHOT_SU_FEED_URL:-https://downloads.slick-shot.com/appcast.xml}"
SPARKLE_PUBLIC_ED_KEY="${SLICKSHOT_SPARKLE_PUBLIC_ED_KEY:-REPLACE_WITH_SPARKLE_PUBLIC_ED25519_KEY}"

if [[ -z "$DEVELOPER_ID_APP" ]]; then
  echo "Missing SLICKSHOT_DEVELOPER_ID_APP" >&2
  exit 1
fi

swift build \
  --package-path "$ROOT_DIR" \
  --scratch-path "$SCRATCH_PATH" \
  -c "$BUILD_CONFIG"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$FRAMEWORKS_DIR"

cp "$EXECUTABLE_PATH" "$MACOS_DIR/SlickShot"
/usr/bin/iconutil -c icns "$ICONSET_DIR" -o "$ICON_FILE"

SPARKLE_FRAMEWORK_SOURCE="$(find "$SCRATCH_PATH" -path '*Sparkle.framework' -type d | head -n 1)"
if [[ -z "$SPARKLE_FRAMEWORK_SOURCE" ]]; then
  echo "Unable to locate Sparkle.framework under $SCRATCH_PATH" >&2
  exit 1
fi

cp -R "$SPARKLE_FRAMEWORK_SOURCE" "$FRAMEWORKS_DIR/Sparkle.framework"

if ! otool -l "$MACOS_DIR/SlickShot" | grep -Fq "@executable_path/../Frameworks"; then
  install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS_DIR/SlickShot"
fi

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
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
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
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
  <key>SlickShotDistributionBuild</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>SUEnableAutomaticChecks</key>
  <true/>
  <key>SUFeedURL</key>
  <string>$SPARKLE_FEED_URL</string>
  <key>SUPublicEDKey</key>
  <string>$SPARKLE_PUBLIC_ED_KEY</string>
</dict>
</plist>
PLIST

/usr/bin/codesign --force --deep --options runtime --timestamp --sign "$DEVELOPER_ID_APP" "$APP_DIR"
/usr/bin/codesign --verify --deep --strict "$APP_DIR"

ZIP_PATH="$DIST_DIR/SlickShot.zip"
rm -f "$ZIP_PATH"
/usr/bin/ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"

if [[ -n "$NOTARY_PROFILE" ]]; then
  xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP_DIR"
  rm -f "$ZIP_PATH"
  /usr/bin/ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"
fi

echo "Built release artifact: $ZIP_PATH"
