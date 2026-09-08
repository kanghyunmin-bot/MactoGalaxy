#!/bin/sh
set -eu
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT_DIR"
if pgrep -x MtoGMac >/dev/null || pgrep -x MtoGExternalDisplayWorker >/dev/null; then
    echo "먼저 MtoG와 확장 화면을 종료하세요." >&2
    exit 1
fi
swift build
STAGE_DIR=$(mktemp -d "$ROOT_DIR/.build/local-install.XXXXXX")
trap 'rm -rf "$STAGE_DIR"' EXIT
APP_DIR="$STAGE_DIR/MtoG.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp assets/app-icon/MtoG.icns "$APP_DIR/Contents/Resources/MtoG.icns"
cp .build/debug/MtoGMac .build/debug/MtoGExternalDisplayWorker "$APP_DIR/Contents/MacOS/"
python3 - "$APP_DIR" <<'PY'
import plistlib,sys
from pathlib import Path
info = dict(CFBundleExecutable='MtoGMac', CFBundleIdentifier='com.mtog.mac',
    CFBundleIconFile='MtoG.icns', CFBundleName='MtoG', CFBundleDisplayName='MtoG', CFBundlePackageType='APPL',
    CFBundleShortVersionString='0.2.0', CFBundleVersion='6', LSMinimumSystemVersion='14.0',
    NSHighResolutionCapable=True, NSPrincipalClass='NSApplication',
    NSLocalNetworkUsageDescription='Galaxy와 로컬 연결을 사용합니다.',
    NSBonjourServices=['_mtog._tcp'])
(Path(sys.argv[1])/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
PY
# Local ad-hoc signatures require no certificate or private key.
# Seal the helper first, then the complete bundle; never overwrite a signed bundle's executable.
codesign --force --sign - --identifier com.mtog.mac.display-worker "$APP_DIR/Contents/MacOS/MtoGExternalDisplayWorker"
codesign --force --sign - --identifier com.mtog.mac "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"
if [ -e /Applications/MtoG.app ]; then
    mv /Applications/MtoG.app "$STAGE_DIR/previous.app"
fi
if ! mv "$APP_DIR" /Applications/MtoG.app; then
    if [ -d "$STAGE_DIR/previous.app" ]; then mv "$STAGE_DIR/previous.app" /Applications/MtoG.app; fi
    exit 1
fi
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/MtoG.app
mdimport /Applications/MtoG.app
codesign --verify --deep --strict /Applications/MtoG.app
echo "설치 완료: /Applications/MtoG.app"
echo "개발 빌드 변경 후 macOS 화면 기록·손쉬운 사용 권한을 다시 허용해야 할 수 있습니다."
