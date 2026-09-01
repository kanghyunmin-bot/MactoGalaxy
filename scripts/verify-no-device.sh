#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

find_java_home() {
    if command -v java >/dev/null 2>&1 && java -version >/dev/null 2>&1; then
        return
    fi
    for candidate in \
        /opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home \
        /usr/local/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home
    do
        if [ -x "$candidate/bin/java" ]; then
            JAVA_HOME=$candidate
            export JAVA_HOME
            PATH="$JAVA_HOME/bin:$PATH"
            export PATH
            return
        fi
    done
    echo "JDK 17 is required" >&2
    exit 1
}

for tool in git swift python3; do
    command -v "$tool" >/dev/null 2>&1 || { echo "$tool is required" >&2; exit 1; }
done
find_java_home

printf 'optional tools:'
for tool in adb scrcpy emulator; do
    if command -v "$tool" >/dev/null 2>&1; then
        printf ' %s=FOUND' "$tool"
    else
        printf ' %s=NOT_FOUND' "$tool"
    fi
done
printf '\nbenchmark-video: NOT_RUN\n'

cd "$ROOT_DIR"
git diff --check
swift test
swift build
swift build -c release

cd "$ROOT_DIR/apps/android-companion"
./gradlew :core:test :app:testDebugUnitTest :app:lintDebug :app:assembleDebug

cd "$ROOT_DIR"
./scripts/verify-protocol-fixtures.sh
./scripts/check-legacy-paths.sh
./scripts/check-repository-policy.sh
./scripts/check-no-secrets.sh

echo "no-device verification: PASS"
