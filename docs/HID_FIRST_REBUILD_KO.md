# MtoG HID-first 재구성

## 결론

최종 입력 구조는 Android 앱이 키보드/마우스를 흉내내는 방식이 아니라, Mac이 USB 연결에서 Galaxy Tab에 외부 HID 키보드/마우스처럼 입력을 보내는 방식으로 바꾼다.

이 방식은 Bluetooth가 아니다. USB-C 케이블 위에서 Android Open Accessory 2.0 HID를 검증한다.

## 중요한 전제

Thunderbolt 4는 물리 케이블/버스 계층이다. Galaxy Tab이 Thunderbolt 장치처럼 동작한다는 뜻은 아니다. 실제로는 Mac의 USB host controller에 Galaxy Tab이 USB device로 붙는다.

가능한 제품 구조는 다음이다.

```text
MacBook USB host
  -> AOA 2.0 HID control requests
  -> Galaxy Tab Android input system
  -> Android가 외부 키보드/마우스처럼 처리
```

이 구조가 실기기에서 성공하면 다음 문제가 해결된다.

- MtoG Keyboard를 기본 입력기로 선택할 필요가 줄어든다.
- 한글 입력은 Android 시스템이 외부 키보드 입력으로 처리한다.
- 마우스 커서는 Android 네이티브 커서가 된다.
- 우클릭/스크롤/포인터 이동이 Accessibility gesture보다 자연스러울 가능성이 높다.

단, 클립보드는 HID로 처리할 수 없다. 클립보드는 계속 Android 앱과 Mac 앱 사이의 별도 secure app channel이 필요하다.

## 새 아키텍처

```text
macOS
  InputCapture
  HIDReportEncoder
  AoaHidTransport
  ClipboardLinkSession
  PairingTrustStore

USB-C
  AOA 2.0 HID for keyboard/mouse
  ADB MVP or future USB app channel for clipboard/control metadata

Android
  Native Android input stack receives HID
  MtoG app handles pairing, clipboard, history, diagnostics
  Accessibility/IME remain fallback only
```

## 구현 우선순위

1. Mac에서 Galaxy Tab USB device 탐지
2. AOA `GET_PROTOCOL`로 AOA2 지원 여부 확인
3. AOA mode 진입
4. HID keyboard descriptor 등록
5. HID mouse descriptor 등록
6. keyboard report 전송 테스트
7. mouse move/click report 전송 테스트
8. 성공 시 Mac 앱 입력 경로를 HID-first로 교체
9. Android 앱에서는 IME/Accessibility를 fallback으로 강등
10. 클립보드는 별도 secure channel로 유지

## 현재 추가된 실험 도구

빌드:

```bash
./scripts/build-aoa-hid-probe.sh
```

USB 후보 확인:

```bash
.build/tools/aoa-hid-probe --list
```

AOA protocol 확인:

```bash
.build/tools/aoa-hid-probe --probe
```

AOA HID 테스트:

```bash
.build/tools/aoa-hid-probe --hid-test
```

주의: `--hid-test`는 AOA mode 진입을 시도하므로 현재 ADB 연결이 끊길 수 있다. 실패하면 케이블을 다시 꽂고 Android에서 USB 디버깅 허용을 다시 확인한다.

## 성공 판정

성공이면 Galaxy Tab에서 다음 중 하나 이상이 보여야 한다.

- Android 네이티브 마우스 커서가 나타남
- 커서가 움직임
- 클릭 이벤트가 들어감
- 텍스트 필드에 `a`가 입력됨
- Android 설정의 물리 키보드/마우스 항목에 장치가 보임

## 한국어 입력

AOA HID 경로에서는 MtoG Keyboard를 기본 입력기로 강제하지 않는다. Android가 외부 물리 키보드 입력으로 처리한다.

Mac 앱은 다음 키를 Android 물리 키보드의 `LANG1` 한/영 전환 usage로 보낸다.

- Caps Lock
- Command + Space
- Control + Space
- 우측 Command 단독
- JIS Eisu/Kana 계열 키

한국어 조합 품질은 Galaxy의 현재 물리 키보드 레이아웃과 삼성/Android 입력기 설정에 의존한다. Galaxy에서 물리 키보드 레이아웃이 한국어로 잡히면 두벌식 조합은 Android 네이티브 입력 경로가 처리한다.

## Mac 키보드 의미 변환

Mac 키보드 자체 설정은 바꾸지 않는다. MtoG가 Android로 보내는 단계에서만 Android/Windows식 의미로 변환한다.

- Mac `Command` + 문자: Android `Ctrl` + 문자
- Mac `Control` + 문자: Android `Ctrl` + 문자
- Mac `Shift`: Android `Shift`
- Mac `Option`: Android `Alt`
- Mac `Command + Space`, `Control + Space`, 우측 `Command`, `Caps Lock`, JIS 한/영 계열: Android `LANG1` 또는 `KEYCODE_LANGUAGE_SWITCH`

예:

- `Command + C` -> Android `Ctrl + C`
- `Command + V` -> Android `Ctrl + V`
- `Command + A` -> Android `Ctrl + A`
- `Command + Z` -> Android `Ctrl + Z`
- `Command + F` -> Android `Ctrl + F`

Mirror Mode에서는 `scrcpy`의 내부 단축키 modifier를 `Alt`로 제한하고, `scrcpy` 창이 앞에 있을 때 MtoG가 `Command` 단축키를 Android `Ctrl` 조합으로 다시 전송한다.

## 제어 모드 탈출

Android 제어 모드에서 Mac 제어로 즉시 돌아오는 키는 다음이다.

- `Esc`
- `Command + Q`
- 기존 fallback: `Control + Option + Command + Left Arrow`

이 키들은 Android로 전달하지 않고 MtoG가 먼저 소비한다.

## 트랙패드 감각 튜닝

AOA HID 경로에서는 Mac delta를 그대로 증폭하지 않는다.

- 포인터 이동은 낮은 HID 전용 gain으로 감쇠한다.
- 마우스 report는 작은 단위로 coalescing해서 보낸다.
- wheel scroll은 큰 trackpad delta를 1-step 단위로 나눠 보낸다.
- pinch는 AOA touch HID report로 두 손가락 sequence를 보낸다.
- swipe fallback은 travel을 줄이고 duration을 늘려 과속을 피한다.

실패면 다음 중 하나다.

- Galaxy Tab S11이 AOA accessory mode를 막음
- macOS에서 libusb가 필요한 control transfer를 보낼 수 없음
- Samsung USB configuration이 AOA HID를 현재 모드에서 받지 않음
- AOA 진입은 되지만 HID report가 Android input stack으로 전달되지 않음

이 경우 앱만으로는 "입력기 선택 없는 완전 네이티브 외부 키보드/마우스"를 보장할 수 없다. 그때는 Accessibility/IME fallback 또는 별도 USB HID 브릿지 하드웨어가 필요하다.
