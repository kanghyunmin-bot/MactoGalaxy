#!/bin/sh

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
ANDROID_DIR="$ROOT_DIR/apps/android-companion"
DIST_DIR="$ROOT_DIR/dist"
OUTPUT_APK="$ANDROID_DIR/app/build/outputs/apk/release/app-release.apk"
DIST_APK="$DIST_DIR/MtoG-android-release.apk"

if [ -z "${JAVA_HOME:-}" ]; then
  for candidate in \
    /opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home \
    /usr/local/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home
  do
    if [ -x "$candidate/bin/java" ]; then
      export JAVA_HOME="$candidate"
      export PATH="$JAVA_HOME/bin:$PATH"
      break
    fi
  done
fi

missing=""
for name in \
  MTOG_ANDROID_KEYSTORE \
  MTOG_ANDROID_KEYSTORE_PASSWORD \
  MTOG_ANDROID_KEY_ALIAS \
  MTOG_ANDROID_KEY_PASSWORD
do
  eval "value=\${$name:-}"
  if [ -z "$value" ]; then
    missing="$missing $name"
  fi
done

if [ -n "$missing" ]; then
  echo "Android release APK 서명 환경 변수가 없습니다:$missing" >&2
  echo "처음 한 번 아래 명령으로 로컬 release keystore를 만드세요:" >&2
  echo "  ./scripts/generate-android-release-keystore.sh" >&2
  echo "  . ./.env.signing.local" >&2
  echo "  ./scripts/package-android-release.sh" >&2
  exit 2
fi

if [ ! -f "$MTOG_ANDROID_KEYSTORE" ]; then
  echo "keystore 파일을 찾지 못했습니다: $MTOG_ANDROID_KEYSTORE" >&2
  exit 1
fi

mkdir -p "$DIST_DIR"

(
  cd "$ANDROID_DIR"
  ./gradlew :app:assembleRelease
)

if [ ! -f "$OUTPUT_APK" ]; then
  echo "release APK를 찾지 못했습니다: $OUTPUT_APK" >&2
  exit 1
fi

cp "$OUTPUT_APK" "$DIST_APK"

if command -v jarsigner >/dev/null 2>&1; then
  jarsigner -verify -certs "$DIST_APK" >/dev/null
fi

echo "Android release APK 생성 완료:"
echo "  $DIST_APK"
