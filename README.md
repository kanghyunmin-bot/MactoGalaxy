# MtoG

MtoG는 Mac과 Galaxy Tab을 연결해 갤럭시 화면 미러링, 클립보드 공유, 실험적 외장 디스플레이 기능을 제공하는 Mac-to-Galaxy 도구입니다.

## 설치 파일

최신 설치 파일은 GitHub Release에서 받을 수 있습니다. Mac에는 DMG를, Galaxy Tab에는 APK를 설치하세요.

<table>
  <tr>
    <td align="center" width="50%">
      <h1>💻</h1>
      <h2>MacBook</h2>
      <p><strong>MtoG-macos.dmg</strong></p>
      <p>Mac 앱 설치 파일입니다.</p>
      <p>
        <a href="https://github.com/kanghyunmin-bot/MactoGalaxy/releases/latest/download/MtoG-macos.dmg">
          <strong>DMG 다운로드</strong>
        </a>
      </p>
    </td>
    <td align="center" width="50%">
      <h1>📱</h1>
      <h2>Galaxy Tab</h2>
      <p><strong>MtoG-android-release.apk</strong></p>
      <p>Galaxy Tab 앱 설치 파일입니다. Play Store 배포 전까지는 Play Protect 경고가 표시될 수 있습니다.</p>
      <p>
        <a href="https://github.com/kanghyunmin-bot/MactoGalaxy/releases/latest/download/MtoG-android-release.apk">
          <strong>APK 다운로드</strong>
        </a>
      </p>
    </td>
  </tr>
</table>

## 빠른 시작

1. Mac에서 `MtoG-macos.dmg`를 열고 `MtoG.app`을 Applications 폴더로 옮깁니다.
2. Galaxy Tab에서 `MtoG-android-release.apk`를 설치합니다.
3. Mac과 Galaxy Tab을 USB-C to USB-C 케이블로 연결합니다.
4. Galaxy Tab에서 USB 디버깅 허용 팝업이 뜨면 허용합니다.
5. 양쪽 기기에서 `MtoG`를 실행합니다.
6. Mac 앱에서 `USB 연결`을 누릅니다.
7. Galaxy Tab 앱의 `페어링` 카드에 표시된 4자리 코드를 Mac 앱의 `페어링 코드` 칸에 입력합니다.
8. Mac 앱에서 `페어링 저장`을 누릅니다. 이후에는 장기 신뢰 키로 재연결됩니다.

## Mac 권한

macOS 권한은 기능별로 다릅니다. 앱 실행과 USB 연결만으로 모든 권한을 요구하지 않습니다.

- `키체인`: 최초 페어링 장기 신뢰 키 저장에 필요합니다. 확인창이 뜨면 Mac 로그인 비밀번호를 입력하고 `항상 허용`을 누르세요.
- `로컬 네트워크`: 개인 Wi-Fi에서 Galaxy Tab 자동 검색을 쓸 때 필요합니다.
- `입력 모니터링`: Mac 화면 우측 상단 코너로 들어가는 전역 Android 제어 모드에서 키보드/트랙패드 입력을 읽을 때 필요합니다.
- `손쉬운 사용`: 실험적 외장 디스플레이 터치 입력 또는 접근성 fallback 제어에만 필요합니다.
- `화면 기록`: macOS 화면 자체를 캡처하는 기능을 추가로 사용할 때만 필요할 수 있습니다.

### macOS Gatekeeper 경고

현재 공개 DMG는 Apple Developer ID 서명/공증 빌드가 아니면 macOS가 `확인되지 않은 개발자` 경고를 띄울 수 있습니다.

- 개발용 배포: 앱 우클릭 > `열기`, 또는 `시스템 설정 > 개인정보 보호 및 보안`에서 수동 허용이 필요할 수 있습니다.
- 일반 사용자 배포: Apple Developer Program 가입, Developer ID Application 인증서, `notarytool` 공증, `stapler` 적용이 필요합니다.
- 앱이 macOS 설정을 자동으로 열거나 권한을 자동 부여하는 것은 보안상 불가능합니다.

## Galaxy Tab 권한

Galaxy Tab에서는 아래 설정이 필요할 수 있습니다.

- `USB 디버깅`: 현재 USB MVP 연결과 미러링에 필요합니다.
- `알림 허용`: 알림창의 수동 클립보드 동기화 버튼을 쓸 때만 필요합니다. 앱 실행 직후에는 요청하지 않습니다.
- `MtoG 접근성 서비스`: 접근성 fallback 제스처/커서 보조 기능을 쓸 때만 필요합니다.
- `MtoG 키보드`: 한글/유니코드 원격 입력 안정성을 높일 때 선택적으로 사용합니다.

### Google Play Protect 경고

GitHub에서 직접 받은 APK는 Play Store 설치가 아니므로 Google Play Protect가 unknown app 또는 scan 경고를 표시할 수 있습니다.

- 개발/테스트 배포: release-signed APK를 사용해 debug APK 경고를 줄입니다.
- 일반 사용자 배포: Google Play Console 또는 Samsung Galaxy Store 배포가 필요합니다.
- Play Protect 자체를 앱 코드로 끄거나 우회하는 것은 불가능하고, 그렇게 설계하면 보안상 잘못된 제품입니다.

## 주요 기능

### 미러링 모드

갤럭시 화면을 Mac 창에 띄우고, 미러링 창 안에서만 Galaxy Tab을 조작합니다.

- 포인터가 미러링 창 안에 있으면 Galaxy Tab을 조작합니다.
- 포인터가 창 밖으로 나오면 바로 macOS 조작으로 돌아옵니다.
- `Esc` 또는 `Command + Q`로 제어 모드에서 빠져나올 수 있습니다.

### 클립보드

현재 클립보드 동기화는 안정성을 위해 수동 버튼 방식입니다.

- `Mac 클립보드 보내기`: 현재 Mac 클립보드를 Galaxy Tab으로 보냅니다.
- `갤럭시 클립보드 가져오기`: 현재 Galaxy Tab 클립보드를 Mac으로 가져옵니다.
- `히스토리 보기`: 최근 클립보드 기록을 보고 다시 복사하거나 저장합니다.

텍스트가 가장 안정적입니다. 이미지와 파일은 Android 클립보드/ContentProvider 권한 정책에 따라 앱별 호환성이 달라질 수 있습니다.

### 외장 디스플레이 모드

Galaxy Tab을 실험적 Mac 보조 화면처럼 사용할 때만 켭니다.

- 한 번 터치: Mac 커서 이동
- 두 번 탭: 왼쪽 클릭
- 1초 이상 길게 누르기: 오른쪽 클릭
- 드래그: Mac 외장 화면에서 드래그
- 두 손가락 이동: 스크롤

이 모드는 실험 기능입니다. macOS 가상 디스플레이와 ADB 스트리밍을 사용하므로 화면 오류, 성능 저하, 재시작이 필요할 수 있습니다.

## 문제 해결

- Mac 앱이 키체인 비밀번호를 묻는 경우: Mac 로그인 비밀번호를 입력하고 `항상 허용`을 누르세요.
- 페어링 코드가 `1408`로 보이는 경우: 구버전 앱입니다. 최신 APK/DMG를 다시 설치한 뒤 Galaxy Tab에서 `새 코드`를 누르세요.
- Galaxy Tab이 안 보이는 경우: USB-C 케이블을 다시 연결하고 Android USB 디버깅 허용을 다시 확인하세요.
- Wi-Fi 검색이 안 되는 경우: 두 기기를 같은 개인 Wi-Fi 또는 개인 핫스팟에 연결하고 Mac 앱에서 IP 직접 연결을 사용하세요.
- 클릭이 안 되는 경우: macOS `시스템 설정 > 개인정보 보호 및 보안 > 손쉬운 사용`에서 `MtoG`를 다시 허용하세요.
- APK 설치가 막히는 경우: Galaxy Tab에서 해당 브라우저/파일 앱의 `알 수 없는 앱 설치` 권한을 허용하세요.

## 필요 조건

### Mac

- Apple Silicon Mac 또는 Intel Mac
- macOS 14 이상 권장
- Android platform-tools / `adb`
- `scrcpy` 설치 권장: `brew install scrcpy`

### Galaxy Tab

- Galaxy Tab S11 / S11 Ultra 대상
- Android USB 디버깅 활성화
- MtoG APK 설치

## 중요 안내

- Sidecar가 아닙니다.
- Apple Universal Control이 아닙니다.
- 아직 제품 서명/공증된 릴리스가 아닙니다.
- USB-C는 물리 케이블입니다. 현재 MVP 통신은 USB 위의 ADB를 사용합니다.
- 외장 디스플레이 모드는 실험 기능이며 안정적인 사용은 미러링 모드를 권장합니다.
- Android 클립보드 정책 때문에 모든 앱의 이미지/파일 클립보드를 100% 보장할 수 없습니다.

## 소스에서 빌드

### macOS 앱

```bash
swift build
./scripts/package-macos-dmg.sh
```

결과물:

```text
dist/MtoG.app
dist/MtoG-macos.dmg
```

### Android 앱

```bash
cd apps/android-companion
./gradlew :app:assembleDebug
```

결과물:

```text
apps/android-companion/app/build/outputs/apk/debug/app-debug.apk
```

### Android release APK

처음 한 번 로컬 release keystore를 생성합니다.

```bash
./scripts/generate-android-release-keystore.sh
. ./.env.signing.local
./scripts/package-android-release.sh
```

결과물:

```text
dist/MtoG-android-release.apk
```

주의: `secrets/mtog-release.jks`와 `.env.signing.local`은 절대 GitHub에 올리지 마세요. 이 키를 잃어버리면 같은 앱 ID로 업데이트 설치가 어려워집니다.

### macOS Developer ID 공증 빌드

Apple Developer ID 인증서와 notarytool keychain profile이 있는 경우:

```bash
export MTOG_MAC_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export MTOG_NOTARY_PROFILE="mtog-notary"
./scripts/package-macos-dmg.sh
```

`MTOG_NOTARY_PROFILE`은 사전에 아래처럼 등록해야 합니다.

```bash
xcrun notarytool store-credentials mtog-notary \
  --apple-id "you@example.com" \
  --team-id "TEAMID" \
  --password "app-specific-password"
```

## 소스 구조

```text
.
├── Package.swift
├── Sources/
│   ├── MtoGMac/                    # macOS 앱
│   └── MtoGExternalDisplayWorker/  # 외장 디스플레이 스트리밍 도우미
├── apps/
│   └── android-companion/          # Galaxy Tab APK 프로젝트
├── scripts/
│   ├── package-macos-dmg.sh
│   └── build-aoa-hid-probe.sh
└── tools/
    └── aoa-hid-probe/              # 선택형 Android Open Accessory HID 도우미
```

이 저장소는 macOS 앱, Android APK, 선택형 HID 도우미를 빌드/패키징하는 데 필요한 핵심 파일만 유지합니다. 생성된 빌드 결과물, 로컬 IDE 설정, APK/DMG, 임시 미리보기 파일은 git에서 제외합니다.
