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
ICONSET_DIR="$ROOT_DIR/Resources/AppIcon.iconset"
ICON_FILE="$RESOURCES_DIR/AppIcon.icns"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"
KEYCHAIN_PATH="$HOME/Library/Keychains/slickshot-signing.keychain-db"
KEYCHAIN_PASSWORD="${SLICKSHOT_KEYCHAIN_PASSWORD:-slickshot-local-signing}"
IDENTITY_NAME="${CODESIGN_IDENTITY:-SlickShot Local Signing}"
P12_PASSWORD="slickshot-export"
SPARKLE_FEED_URL="${SLICKSHOT_SU_FEED_URL:-https://downloads.slick-shot.com/appcast.xml}"
SPARKLE_PUBLIC_ED_KEY="${SLICKSHOT_SPARKLE_PUBLIC_ED_KEY:-REPLACE_WITH_SPARKLE_PUBLIC_ED25519_KEY}"

mkdir -p "$HOME/Applications"

current_keychains="$(security list-keychains -d user | tr -d '"')"
security list-keychains -d user -s "$KEYCHAIN_PATH" $current_keychains >/dev/null

ensure_signing_identity() {
  if security find-identity -v -p codesigning "$KEYCHAIN_PATH" 2>/dev/null | grep -Fq "$IDENTITY_NAME"; then
    return
  fi

  local temp_dir private_key certificate pem_bundle
  temp_dir="$(mktemp -d)"
  private_key="$temp_dir/slickshot.key"
  certificate="$temp_dir/slickshot.crt"
  pem_bundle="$temp_dir/slickshot.p12"

  if [[ ! -f "$KEYCHAIN_PATH" ]]; then
    security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
    security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
  fi

  security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"

  openssl req \
    -x509 \
    -newkey rsa:2048 \
    -keyout "$private_key" \
    -out "$certificate" \
    -days 3650 \
    -nodes \
    -subj "/CN=$IDENTITY_NAME/" \
    -addext "basicConstraints=critical,CA:FALSE" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" \
    >/dev/null 2>&1

  openssl pkcs12 \
    -export \
    -legacy \
    -inkey "$private_key" \
    -in "$certificate" \
    -out "$pem_bundle" \
    -passout "pass:$P12_PASSWORD" \
    >/dev/null 2>&1

  security import "$pem_bundle" \
    -k "$KEYCHAIN_PATH" \
    -P "$P12_PASSWORD" \
    -T /usr/bin/codesign \
    -T /usr/bin/security \
    >/dev/null

  security add-trusted-cert -d -r trustRoot -k "$KEYCHAIN_PATH" "$certificate" >/dev/null

  security set-key-partition-list \
    -S apple-tool:,apple:,codesign: \
    -s \
    -k "$KEYCHAIN_PASSWORD" \
    "$KEYCHAIN_PATH" \
    >/dev/null

  rm -rf "$temp_dir"
}

ensure_signing_identity
IDENTITY_HASH="$(
  security find-identity -v -p codesigning "$KEYCHAIN_PATH" |
    awk -v name="$IDENTITY_NAME" '$0 ~ name { print $2; exit }'
)"
if [[ -z "$IDENTITY_HASH" ]]; then
  echo "Unable to resolve codesigning identity hash for $IDENTITY_NAME" >&2
  exit 1
fi

swift build \
  --package-path "$ROOT_DIR" \
  --scratch-path "$SCRATCH_PATH" \
  -c "$BUILD_CONFIG"

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$FRAMEWORKS_DIR"

cp "$EXECUTABLE_PATH" "$MACOS_DIR/SlickShot"
/usr/bin/iconutil -c icns "$ICONSET_DIR" -o "$ICON_FILE"

SPARKLE_FRAMEWORK_SOURCE="$(find "$SCRATCH_PATH" -path '*Sparkle.framework' -type d | head -n 1)"
if [[ -n "$SPARKLE_FRAMEWORK_SOURCE" ]]; then
  rm -rf "$FRAMEWORKS_DIR/Sparkle.framework"
  cp -R "$SPARKLE_FRAMEWORK_SOURCE" "$FRAMEWORKS_DIR/Sparkle.framework"
fi

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

security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
/usr/bin/codesign --force --deep --keychain "$KEYCHAIN_PATH" --sign "$IDENTITY_HASH" "$APP_DIR"

touch "$APP_DIR"
echo "Installed $APP_DIR"
