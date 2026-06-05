#!/bin/sh

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SECRETS_DIR="$ROOT_DIR/secrets"
KEYSTORE_PATH="${MTOG_ANDROID_KEYSTORE:-$SECRETS_DIR/mtog-release.jks}"
KEY_ALIAS="${MTOG_ANDROID_KEY_ALIAS:-mtog-release}"
ENV_PATH="$ROOT_DIR/.env.signing.local"

if [ -z "${JAVA_HOME:-}" ]; then
  for candidate in \
    /opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home \
    /usr/local/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home
  do
    if [ -x "$candidate/bin/keytool" ]; then
      export JAVA_HOME="$candidate"
      export PATH="$JAVA_HOME/bin:$PATH"
      break
    fi
  done
fi

if [ -f "$KEYSTORE_PATH" ]; then
  echo "이미 keystore가 있습니다: $KEYSTORE_PATH" >&2
  echo "새로 만들려면 기존 파일을 안전하게 백업한 뒤 삭제하세요." >&2
  exit 1
fi

if ! command -v keytool >/dev/null 2>&1; then
  echo "keytool을 찾지 못했습니다. JDK 17 이상을 설치하세요." >&2
  exit 1
fi

if ! command -v openssl >/dev/null 2>&1; then
  echo "openssl을 찾지 못했습니다." >&2
  exit 1
fi

mkdir -p "$SECRETS_DIR"

STORE_PASSWORD=$(openssl rand -base64 32 | tr -d '\n')
KEY_PASSWORD=$(openssl rand -base64 32 | tr -d '\n')

keytool -genkeypair \
  -v \
  -keystore "$KEYSTORE_PATH" \
  -storetype PKCS12 \
  -alias "$KEY_ALIAS" \
  -keyalg RSA \
  -keysize 4096 \
  -validity 10000 \
  -storepass "$STORE_PASSWORD" \
  -keypass "$KEY_PASSWORD" \
  -dname "CN=MtoG Local Release, OU=MtoG, O=MtoG, L=Seoul, ST=Seoul, C=KR"

cat > "$ENV_PATH" <<EOF
export JAVA_HOME="${JAVA_HOME:-}"
export MTOG_ANDROID_KEYSTORE="$KEYSTORE_PATH"
export MTOG_ANDROID_KEYSTORE_PASSWORD="$STORE_PASSWORD"
export MTOG_ANDROID_KEY_ALIAS="$KEY_ALIAS"
export MTOG_ANDROID_KEY_PASSWORD="$KEY_PASSWORD"
EOF

chmod 600 "$ENV_PATH" "$KEYSTORE_PATH"

echo "Android release keystore 생성 완료:"
echo "  $KEYSTORE_PATH"
echo "서명 환경 파일:"
echo "  $ENV_PATH"
echo ""
echo "사용:"
echo "  . \"$ENV_PATH\""
echo "  ./scripts/package-android-release.sh"
echo ""
echo "주의: 이 keystore를 잃어버리면 같은 앱 ID로 업데이트 설치가 어려워집니다. 안전하게 백업하세요."
