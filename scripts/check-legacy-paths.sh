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

if grep -R -- '--no-clipboard-autosync' Sources apps/android-companion/app/src/main >/dev/null; then
    echo "scrcpy clipboard autosync is disabled" >&2
    exit 1
fi

if grep -E 'OnPrimaryClipChangedListener|addPrimaryClipChangedListener' \
    apps/android-companion/app/src/main/java/com/mtog/app/clipboard/ClipboardSyncManager.kt >/dev/null; then
    echo "Android background clipboard listener found" >&2
    exit 1
fi

grep -q 'implementation(project(":core"))' apps/android-companion/app/build.gradle.kts
grep -q 'dependencies: \["MtoGCore"\]' Package.swift
grep -q 'ClipboardAuthorityStatus = .blocked' Sources/MtoGMac/ShellClipboardTransport.swift

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

echo "registered legacy path checks: PASS"
