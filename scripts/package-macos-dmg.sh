#!/bin/sh

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
DIST_DIR="$ROOT_DIR/dist"
ARM64_SCRATCH="$ROOT_DIR/.build-arm64"
X64_SCRATCH="$ROOT_DIR/.build-x86_64"
ARM64_BINARY="$ARM64_SCRATCH/arm64-apple-macosx/release/MtoGMac"
X64_BINARY="$X64_SCRATCH/x86_64-apple-macosx/release/MtoGMac"
ARM64_EXTERNAL_WORKER="$ARM64_SCRATCH/arm64-apple-macosx/release/MtoGExternalDisplayWorker"
X64_EXTERNAL_WORKER="$X64_SCRATCH/x86_64-apple-macosx/release/MtoGExternalDisplayWorker"
UNIVERSAL_BINARY="$DIST_DIR/MtoGMac-universal"
UNIVERSAL_EXTERNAL_WORKER="$DIST_DIR/MtoGExternalDisplayWorker-universal"
APP_NAME="MtoG.app"
APP_DIR="$DIST_DIR/$APP_NAME"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
AOA_HELPER="$ROOT_DIR/.build/tools/aoa-hid-probe"
STAGING_DIR="$DIST_DIR/macos-dmg"
DMG_PATH="$DIST_DIR/MtoG-macos.dmg"
README_PATH="$STAGING_DIR/README.txt"

mkdir -p "$DIST_DIR"

swift build -c release --scratch-path "$ARM64_SCRATCH" --package-path "$ROOT_DIR"
swift build -c release --triple x86_64-apple-macosx14.0 --scratch-path "$X64_SCRATCH" --package-path "$ROOT_DIR"
if [ -x "$ROOT_DIR/scripts/build-aoa-hid-probe.sh" ]; then
  "$ROOT_DIR/scripts/build-aoa-hid-probe.sh" >/dev/null
fi

if [ ! -f "$ARM64_BINARY" ] || [ ! -f "$X64_BINARY" ] || [ ! -f "$ARM64_EXTERNAL_WORKER" ] || [ ! -f "$X64_EXTERNAL_WORKER" ]; then
  echo "Universal release inputs not found" >&2
  exit 1
fi

rm -rf "$APP_DIR" "$STAGING_DIR" "$DMG_PATH" "$UNIVERSAL_BINARY" "$UNIVERSAL_EXTERNAL_WORKER"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$STAGING_DIR"

lipo -create "$ARM64_BINARY" "$X64_BINARY" -output "$UNIVERSAL_BINARY"
lipo -create "$ARM64_EXTERNAL_WORKER" "$X64_EXTERNAL_WORKER" -output "$UNIVERSAL_EXTERNAL_WORKER"

cp "$UNIVERSAL_BINARY" "$MACOS_DIR/MtoGMac"
chmod +x "$MACOS_DIR/MtoGMac"
cp "$UNIVERSAL_EXTERNAL_WORKER" "$MACOS_DIR/MtoGExternalDisplayWorker"
chmod +x "$MACOS_DIR/MtoGExternalDisplayWorker"

if [ -x "$AOA_HELPER" ]; then
  cp "$AOA_HELPER" "$RESOURCES_DIR/aoa-hid-probe"
  chmod +x "$RESOURCES_DIR/aoa-hid-probe"
fi

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>MtoGMac</string>
    <key>CFBundleIdentifier</key>
    <string>com.mtog.mac</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>MtoG</string>
    <key>CFBundleDisplayName</key>
    <string>MtoG</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP_DIR"

cp -R "$APP_DIR" "$STAGING_DIR/$APP_NAME"
ln -s /Applications "$STAGING_DIR/Applications"

cat > "$README_PATH" <<'README'
MtoG macOS build

This DMG contains an ad-hoc signed development build.
It is not notarized yet.

Install:
1. Drag MtoG.app into Applications
2. Open the app
3. If Gatekeeper blocks it, right-click the app and choose Open
README

hdiutil create \
  -volname "MtoG" \
  -srcfolder "$STAGING_DIR" \
  -format UDZO \
  "$DMG_PATH" >/dev/null

echo "Created:"
echo "  $APP_DIR"
echo "  $DMG_PATH"
