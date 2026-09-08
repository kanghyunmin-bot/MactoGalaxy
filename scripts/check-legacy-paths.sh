#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT_DIR"

if grep -E 'BufferedReader|readLine\(|encodeLine|decodeLine|org\.json' \
    apps/android-companion/app/src/main/java/com/mtog/app/service/AdbLoopbackServer.kt \
    apps/android-companion/app/src/main/java/com/mtog/app/session/SessionProtocol.kt >/dev/null; then
    echo "legacy Android control framing found" >&2
    exit 1
fi

if grep -E 'SessionCodec|encodeLine|decodeLine|firstIndex\(of: 0x0A\)' \
    Sources/MtoGMac/SessionClient.swift Sources/MtoGMac/SessionProtocol.swift >/dev/null; then
    echo "legacy Mac control framing found" >&2
    exit 1
fi

if grep -E 'OnPrimaryClipChangedListener|addPrimaryClipChangedListener' \
    apps/android-companion/app/src/main/java/com/mtog/app/clipboard/ClipboardSyncManager.kt >/dev/null; then
    echo "Android background clipboard listener found" >&2
    exit 1
fi

grep -q 'implementation(project(":core"))' apps/android-companion/app/build.gradle.kts
grep -q 'dependencies: \["MtoGCore"\]' Package.swift
# Production protocol/lifecycle behavior is exercised by ScrcpyAdapterTests in swift test.
if grep -R -E '^import (AppKit|SwiftUI|Network|Darwin)$|Process\(' Sources/MtoGCore >/dev/null; then
    echo "platform dependency escaped into pure Core" >&2
    exit 1
fi

if grep -E 'JSON|Base64' Sources/MtoGCore/Video*.swift \
    apps/android-companion/core/src/main/kotlin/com/mtog/core/Video*.kt >/dev/null; then
    echo "video protocol uses JSON or Base64" >&2
    exit 1
fi
grep -q 'MTGV' docs/protocol-v2.md

if grep -R -E 'CGDisplayCreateImage|MTOGVD1|"FRAM"|UTType\.jpeg|ImageIO' \
    Sources/MtoGExternalDisplayWorker >/dev/null; then
    echo "legacy Mac external display path found" >&2
    exit 1
fi

if grep -R -E 'NSClassFromString\("CGVirtualDisplay|initWithDescriptor:|applySettings:' \
    Sources/MtoGExternalDisplayWorker --exclude=CGVirtualDisplayBackend.swift >/dev/null; then
    echo "private virtual display call escaped its backend" >&2
    exit 1
fi

if grep -R -E '^import (AppKit|SwiftUI)$|ADB' Sources/MtoGMedia >/dev/null; then
    echo "MtoGMedia imported UI or ADB" >&2
    exit 1
fi
grep -q '^import ScreenCaptureKit$' Sources/MtoGExternalDisplayWorker/ScreenCaptureSource.swift
grep -q '^import VideoToolbox$' Sources/MtoGMedia/RealtimeVideoEncoder.swift

if grep -R -E 'BitmapFactory|decodeByteArray|MTOGVD1|"FRAM"|JPEG|jpeg' \
    apps/android-companion/app/src/main/java/com/mtog/app/ExternalDisplayActivity.kt \
    apps/android-companion/app/src/main/java/com/mtog/app/externaldisplay >/dev/null; then
    echo "legacy Android external display path found" >&2
    exit 1
fi
grep -q 'SurfaceView' apps/android-companion/app/src/main/java/com/mtog/app/externaldisplay/ExternalDisplaySurface.kt
grep -q 'MediaCodec' apps/android-companion/app/src/main/java/com/mtog/app/externaldisplay/MediaCodecVideoDecoder.kt

if grep -R -E 'arguments: \["(forward|reverse|shell|get-state)|process\.arguments = \[\]' \
    Sources/MtoGMac Sources/MtoGExternalDisplayWorker >/dev/null; then
    echo "device-targeted command without explicit serial found" >&2
    exit 1
fi
grep -q 'process.arguments = \["--serial", serial, "--session", sessionID.uuidString\]' \
    Sources/MtoGMac/VirtualDisplayBridge.swift
grep -q 'object\["sessionId"\]' Sources/MtoGExternalDisplayWorker/TouchInputServer.swift
grep -q 'UUID(uuidString: sessionValue) == controlSessionID' Sources/MtoGExternalDisplayWorker/TouchInputServer.swift
grep -q 'sequence > touchInputState.highestSequence' Sources/MtoGExternalDisplayWorker/TouchInputServer.swift
grep -q 'override fun onNewIntent' apps/android-companion/app/src/main/java/com/mtog/app/ExternalDisplayActivity.kt
grep -q 'sessionID = controlSessionID' apps/android-companion/app/src/main/java/com/mtog/app/externaldisplay/VideoStreamReceiver.kt

if [ -e Sources/MtoGMac/ScrcpyMirrorBridge.swift ] || [ -e Sources/MtoGMac/AoaHidBridge.swift ]; then
    echo "removed reverse-control feature returned" >&2
    exit 1
fi
if grep -E 'RemoteKeyboardService|AccessibilityControlService' apps/android-companion/app/src/main/AndroidManifest.xml >/dev/null; then
    echo "removed Android input service returned" >&2
    exit 1
fi
echo "registered legacy path checks: PASS"
