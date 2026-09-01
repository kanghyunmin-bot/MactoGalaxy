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

grep -q 'implementation(project(":core"))' apps/android-companion/app/build.gradle.kts
grep -q 'dependencies: \["MtoGCore"\]' Package.swift

echo "registered legacy path checks: PASS"
