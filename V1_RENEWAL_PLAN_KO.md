# MtoG V1 리뉴얼 실행 계획

## 0. 결론

MtoG V1은 더 이상 "ADB로 일단 되는 MVP"가 아니다. V1은 MacBook과 Galaxy Tab S11 사이에서 실제 사용 가능한 제품형 입력 공유 및 클립보드 동기화 시스템으로 재정의한다.

공개 제품 버전은 `V1` 하나로 둔다. 기존에 V2부터 V7까지 흩어져 있던 항목은 V1 내부 마일스톤으로 흡수한다.

```text
V1-A: 현재 ADB MVP 안정화
V1-B: 자체 프로토콜 v2
V1-C: 보안 세션 완성
V1-D: 입력 품질 재설계
V1-E: 클립보드 blob 전송
V1-F: ADB 없는 USB production transport 검증
V1-G: 배포, 진단, QA, 제품화
```

가장 중요한 원칙은 다음이다.

- ADB는 V1-A에서만 연결 bootstrap으로 허용한다.
- ADB shell input은 제품 입력 경로에서 제거한다.
- UDP는 목표가 아니다. USB 또는 IP 경로가 실제로 존재할 때만 후보가 된다.
- 키보드는 Android IME 중심으로 처리한다.
- 포인터/제스처는 AccessibilityService로 처리하되, 이벤트 스케줄링을 Mac 쪽에서 안정화한다.
- 클립보드는 text inline, image/file/video blob stream으로 분리한다.
- Android 백그라운드 클립보드 완전 자동 감지는 일반 앱 권한으로 약속하지 않는다.
- Mac과 Android 사이의 모든 제어/클립보드 payload는 세션 암호화 이후에만 흐른다.

## 1. V1 제품 목표

V1에서 사용자가 체감해야 하는 목표는 명확하다.

- Mac 우측 상단 코너로 포인터를 밀면 Galaxy Tab 제어 모드로 자연스럽게 넘어간다.
- Android 제어 모드에서는 Mac 쪽 입력이 중복으로 들어가지 않는다.
- Galaxy Tab 좌측 하단 복귀 영역 또는 Mac 전용 탈출 단축키로 Mac 제어로 돌아온다.
- Mac 트랙패드/마우스로 Android에서 포인터 이동, 클릭, 우클릭, 드래그, 스크롤, 핀치 확대/축소가 가능한 수준으로 동작한다.
- Mac 키보드로 Android 텍스트 필드에 한글, 영어, 숫자, 특수문자를 입력할 수 있다.
- 우클릭은 Back이 아니라 Android의 컨텍스트 동작에 가장 가까운 long press/context press로 처리한다.
- Back/Home/Recents는 명시 단축키나 3손가락 제스처로만 처리한다.
- Mac 클립보드와 Galaxy 클립보드는 텍스트와 이미지를 우선 안정적으로 동기화한다.
- 파일과 영상은 같은 blob 전송 구조 위에서 지원한다.
- 양쪽 앱에서 최근 클립보드 히스토리를 보고 다시 복사할 수 있다.
- 한 번 페어링한 기기는 다시 4자리 코드를 입력하지 않아도 자동 신뢰 재연결된다.

## 2. V1에서 제거할 현재 구조

다음 항목은 V1 최종 구조에서 제거하거나 디버그 fallback으로만 남긴다.

| 현재 구조 | 문제 | V1 처리 |
|---|---|---|
| `adb shell input tap` | 클릭 위치/지연/권한 상태가 불안정 | 제거 |
| `adb shell input text` | 한글 분해, 특수문자 실패 | 제거 |
| `adb shell input swipe` | 스와이프/핀치가 부자연스러움 | 제거 |
| `adb shell input mouse scroll` | Android 앱별 동작 불안정 | 제거 |
| JSON line + `[String:String]` payload | 타입 안정성 낮음, 대용량 부적합 | protobuf frame으로 교체 |
| 이미지/파일 base64 inline | 메모리 낭비, 큰 파일 취약 | blob chunk stream으로 교체 |
| 우클릭 = Back | UX 오류 | context press로 교체 |
| Android 클립보드 백그라운드 상시 감지 약속 | Android 정책 위반 가능 | foreground/manual/IME-assisted 모드로 설계 |
| UDP 우선 설계 | USB-C 케이블만으로 UDP 경로 없음 | 검증된 IP 경로에서만 사용 |

## 3. V1 최종 아키텍처

```text
macOS
  MtoGMacApp
    AppModel
    PointerCornerMonitor
    ControlModeInputController
    InputEventRouter
    InputFrameScheduler
    ClipboardCoordinator
    BlobTransferManager
    SecureSessionManager
    TransportManager
      AdbForwardTransport
      UsbNetworkTransportCandidate
      WifiFallbackTransport

Secure framed channel
  MtoG Frame v2
  Protobuf messages
  Stream IDs
  AEAD encryption
  Replay guard
  ACK/retry for reliable streams

Android
  MainActivity
  LinkForegroundService
    TransportManager
      AdbForwardServer
      UsbNetworkServerCandidate
      WifiFallbackServer
    SecureSessionManager
    AndroidInputDispatcher
    ClipboardCoordinator
    BlobTransferManager
  RemoteAccessibilityService
  RemoteKeyboardService
  ClipboardFileProvider
  ClipboardHistoryStore
```

## 4. Transport 전략

### V1-A: ADB forward 유지

목적은 개발과 기능 검증이다.

- Mac에서 `adb forward tcp:<hostPort> tcp:<androidPort>`로 터널을 연다.
- 이후에는 ADB shell input을 쓰지 않는다.
- 제어/키보드/클립보드는 전부 앱 프로토콜로 전송한다.
- 사용자 UI에는 `USB ADB Dev Mode`라고 명확히 표시한다.

### V1-F: ADB 없는 production transport 검증

1순위 후보는 USB-C 연결 후 생성 가능한 USB network/IP 경로 위 `TCP + MtoG secure session`이다.

검증 항목:

- Galaxy Tab S11에서 Mac과 USB-C 연결 시 앱이 사용할 수 있는 IP 경로가 생기는가.
- USB tethering 또는 RNDIS/NCM 계열이 사용자 설정 없이 가능한가.
- 사용자가 케이블만 연결했을 때 자동 연결 UX가 가능한가.
- Android 앱이 production 권한만으로 서버 socket을 열고 Mac이 발견할 수 있는가.

2순위 후보는 Android Open Accessory 또는 USB accessory 계열이다. 단, Galaxy Tab S11에서 실제 bulk endpoint 통신이 가능한지 먼저 검증해야 한다.

Wi-Fi는 fallback이다. Bluetooth는 V1 primary transport로 쓰지 않는다.

## 5. MtoG Frame v2

V1에서는 JSON line을 버리고 length-prefixed encrypted binary frame을 사용한다.

```text
Header
  magic: 4 bytes = "MTG2"
  version: UInt16 = 1
  headerLength: UInt16
  streamId: UInt16
  flags: UInt16
  sequenceNo: UInt64
  payloadLength: UInt32

Payload
  encrypted protobuf bytes
```

Stream ID:

| Stream | 용도 | 신뢰성 |
|---|---|---|
| 1 | session, pairing, capabilities | reliable |
| 2 | pointer move, cursor state | latest-wins |
| 3 | click, key, text, gesture command | reliable ordered |
| 4 | clipboard metadata | reliable ordered |
| 5 | blob chunks | reliable chunked |
| 6 | diagnostics | best effort |

ACK 정책:

- Stream 1, 3, 4, 5는 ACK 대상이다.
- Stream 2 pointer move는 ACK하지 않는다.
- Stream 2는 queue에 오래된 move가 쌓이면 최신값만 남긴다.
- Clipboard chunk는 `clipboardId + chunkIndex + sha256` 기준으로 idempotent 처리한다.

## 6. Protobuf 메시지

`proto/mtog.proto`는 V1의 source of truth가 된다.

필수 메시지:

```proto
message Hello {
  string device_id = 1;
  string device_name = 2;
  string app_version = 3;
  repeated string capabilities = 4;
  bytes identity_public_key = 5;
  bytes ephemeral_public_key = 6;
}

message SessionReady {
  string session_id = 1;
  bool trusted = 2;
  DisplayInfo display = 3;
  repeated string enabled_features = 4;
}

message PointerMove {
  float x = 1;
  float y = 2;
  float dx = 3;
  float dy = 4;
  uint64 event_time_micros = 5;
}

message PointerButton {
  enum Button {
    LEFT = 0;
    RIGHT = 1;
    MIDDLE = 2;
  }
  enum Phase {
    DOWN = 0;
    UP = 1;
    CLICK = 2;
  }
  Button button = 1;
  Phase phase = 2;
  float x = 3;
  float y = 4;
}

message TextCommit {
  string text = 1;
  string locale = 2;
  bool composition_committed = 3;
}

message KeyCommand {
  string key = 1;
  repeated string modifiers = 2;
  string semantic = 3;
}

message GestureCommand {
  string kind = 1;
  float start_x = 2;
  float start_y = 3;
  float end_x = 4;
  float end_y = 5;
  float scale = 6;
  int32 duration_ms = 7;
}

message ClipboardOffer {
  string clipboard_id = 1;
  string kind = 2;
  string mime_type = 3;
  string file_name = 4;
  uint64 size_bytes = 5;
  bytes sha256 = 6;
  bool inline_text_available = 7;
  string inline_text = 8;
}

message ClipboardChunk {
  string clipboard_id = 1;
  uint32 chunk_index = 2;
  uint64 offset = 3;
  bytes data = 4;
}

message ClipboardComplete {
  string clipboard_id = 1;
  bytes sha256 = 2;
}
```

## 7. 보안 설계

장기 키:

- Mac: Keychain에 P-256 또는 Curve25519 identity key 저장
- Android: Android Keystore에 identity key 저장
- 저장 항목: deviceId, deviceName, identity public key, private key reference

페어링:

1. 양쪽 앱이 ephemeral key를 생성한다.
2. 서로 `Hello`를 교환한다.
3. 사용자가 양쪽에 같은 4자리 코드를 입력한다.
4. 4자리 코드는 transcript confirmation에만 사용한다.
5. 성공 시 peer deviceId와 identity public key를 trusted peer로 저장한다.

세션 키:

- 매 연결마다 새 ephemeral ECDH를 수행한다.
- HKDF-SHA256으로 다음 키를 만든다.
- `client_to_server_key`
- `server_to_client_key`
- `header_auth_key`
- `session_nonce_base`

암호화:

- payload는 AES-GCM 또는 ChaCha20-Poly1305로 암호화한다.
- nonce는 `session_nonce_base + streamId + sequenceNo`에서 만든다.
- AAD에는 magic, version, streamId, sequenceNo, payloadLength를 포함한다.

Replay 방지:

- `sessionId + streamId`마다 highest sequence와 sliding window를 유지한다.
- 재접속하면 sessionId와 session key가 바뀐다.
- 오래된 sessionId frame은 폐기한다.

Revocation:

- Mac UI와 Android UI에서 trusted peer 삭제 제공
- 삭제 즉시 해당 public key로 오는 reconnect 거부
- 재페어링은 4자리 코드부터 다시 시작

## 8. 입력 설계

### Mac 입력 파이프라인

```text
CGEventTap
  -> ControlModeInputController
  -> InputEventRouter
  -> InputFrameScheduler
  -> SecureSessionManager
```

`InputEventRouter` 책임:

- macOS raw event를 MtoG semantic event로 변환
- left/right/middle click 분리
- right click을 Back으로 변환하지 않음
- 한글 조합 완료 문자열과 raw key command 분리
- control mode 중 Mac local delivery suppress 결정

`InputFrameScheduler` 책임:

- pointer move coalescing: 최대 120Hz
- scroll coalescing: 최대 60Hz
- pinch coalescing: 최대 30Hz
- click/key/text는 즉시 전송
- queue가 밀리면 오래된 pointer move 폐기
- 전송 지연이 80ms 이상이면 gesture frequency 자동 하향

### Android 입력 파이프라인

```text
AndroidInputDispatcher
  -> RemoteKeyboardService for text
  -> RemoteAccessibilityService for gestures
  -> Global action for Back/Home/Recents
  -> Cursor overlay for visual pointer
```

매핑:

| Mac 입력 | Android 동작 |
|---|---|
| pointer move | cursor overlay 이동 |
| left click | tap |
| right click | context press 또는 long press |
| double click | double tap 후보, 앱별 검증 |
| drag | continuous touch stroke |
| two-finger scroll | accessibility gesture scroll |
| pinch | two-pointer pinch gesture |
| three-finger up | Recents |
| three-finger down | foreground app 복귀 후보 |
| Cmd+Left | Back |
| Cmd+H | Home |
| Cmd+Tab 후보 | Recents |
| text | IME `commitText()` |
| delete | IME deleteSurroundingText |
| enter | IME action 또는 key event |

제한:

- Android 일반 앱은 진짜 시스템 HID 마우스/키보드 이벤트를 만들 수 없다.
- Accessibility gesture는 앱별로 거부되거나 취소될 수 있다.
- 일부 앱은 custom canvas에서 long press/context 동작이 다르다.

## 9. 클립보드 설계

### 텍스트/URL

- 256KB 이하 텍스트는 `ClipboardOffer.inline_text`로 보낸다.
- URL은 별도 kind로 표시하되 destination에서는 plain text clipboard로도 구성한다.
- Mac은 NSPasteboard string/url type을 등록한다.
- Android는 `ClipData.newPlainText()` 또는 URL MIME metadata를 사용한다.

### 이미지

- Mac source:
  - NSPasteboard에서 PNG/TIFF/PDF image representation 추출
  - PNG 우선 정규화
  - `ClipboardOffer` 전송
  - `ClipboardChunk`로 bytes 전송
- Android destination:
  - cache file 저장
  - `FileProvider`로 `content://` URI 생성
  - `ClipData.newUri()`로 clipboard 구성
  - history에는 thumbnail, mimeType, size, blobId 저장

### 파일/영상

- 파일은 원본 파일명, MIME, 크기, sha256을 metadata로 보낸다.
- 대용량은 chunk 전송과 resume을 지원한다.
- 기본 max size는 V1에서 256MB로 제한한다.
- 256MB 초과는 "send as file transfer" UX로 분리한다.

### Android -> Mac 제한

Android 10+에서는 백그라운드 앱이 시스템 클립보드를 항상 읽을 수 없다.

V1 지원 모드:

| 모드 | 설명 | 신뢰도 |
|---|---|---|
| Foreground Sync | Android 앱이 전면일 때 읽기 | 높음 |
| Manual Pull | Mac에서 Pull Android Clipboard 클릭 | 중간 |
| IME Assisted | MtoG Keyboard가 선택된 텍스트 입력 상황 | 높음 |
| Background Always-On | 일반 앱 권한으로는 불가 | 약속 금지 |

## 10. UI/UX 범위

### macOS

- 메뉴바 앱 + 대시보드 창
- 연결 상태: disconnected, connecting, paired, trusted, control mode
- transport 상태: ADB Dev, USB Candidate, Wi-Fi Fallback
- 권한 상태: Accessibility, Input Monitoring
- Pairing card: 4자리 코드 입력, trusted peer 표시, revoke
- Control card: 진입 corner, 복귀 gesture, 현재 target display
- Clipboard card: push, pull, history
- Diagnostics card: latency, dropped frames, last error

### Android

- Compose UI 유지
- 첫 화면에서 transport, pairing, accessibility, keyboard, clipboard 상태를 한눈에 표시
- Accessibility 설정 열기 버튼
- Keyboard picker 열기 버튼
- Clipboard Sync Now 버튼
- Trusted peer 삭제
- Clipboard history
- Foreground service notification

UI 문구는 불가능한 자동화를 약속하지 않는다.

## 11. 구현 작업 목록

### V1-A: 현재 MVP 안정화

목표: 지금 앱을 망가뜨리지 않고 ADB shell input 의존을 끊는다.

작업:

- Mac `ADBCommandChannel`의 tap/text/swipe/scroll 사용 지점 제거
- `ControlModeInputController`가 모든 입력을 `SessionClient`로만 보내게 정리
- Android `AdbLoopbackServer`가 input dispatcher로 위임하도록 분리
- 우클릭 매핑을 Back에서 context press로 고정
- 한글 입력은 `RemoteKeyboardService.commitText()` 우선으로 고정
- clipboard paste fallback은 debug fallback으로 격리
- Mac에서 control mode 중 local event suppress 재검증

완료 기준:

- 우클릭이 Back으로 동작하지 않는다.
- 한글 문장 입력이 자모 분해되지 않는다.
- 클릭/드래그/스크롤이 ADB shell 없이 동작한다.
- 연결 끊김 시 Mac 입력이 즉시 복구된다.

### V1-B: Protocol v2

목표: typed binary protocol과 stream 구조를 도입한다.

작업:

- `proto/mtog.proto`를 v2로 재작성
- Swift protobuf generation 추가
- Android protobuf-kotlin-lite 추가
- length-prefixed frame encoder/decoder 구현
- streamId, sequenceNo, ACK 구현
- pointer latest-wins queue 구현
- diagnostics counters 추가

완료 기준:

- JSON line 없이 hello/pair/input/clipboard text가 동작한다.
- pointer move 120Hz 입력에서도 queue가 계속 증가하지 않는다.
- reliable stream에서 ACK timeout/retry가 동작한다.

### V1-C: Secure session

목표: 실제 payload 암호화와 신뢰 재연결을 완성한다.

작업:

- Mac Keychain identity key 재검증
- Android Keystore identity key 재검증
- ephemeral ECDH handshake 구현
- HKDF session key 생성
- AES-GCM 또는 ChaCha20-Poly1305 적용
- stream별 replay guard 적용
- pairing lockout 구현
- trusted peer revoke UI 연결

완료 기준:

- Wireshark/adb tcp dump에서 payload가 평문으로 보이지 않는다.
- 재연결마다 session key가 바뀐다.
- 이전 session frame replay가 거부된다.
- trusted peer 삭제 후 자동 재연결이 실패한다.

### V1-D: Input quality

목표: 실제 사용 가능한 수준으로 입력 품질을 올린다.

작업:

- `InputEventRouter.swift` 추가
- `InputFrameScheduler.swift` 추가
- `AndroidInputDispatcher.kt` 추가
- cursor overlay 좌표 보정
- Galaxy Tab portrait/landscape 좌표 변환
- pinch gesture cancellation 감소
- scroll inertia tuning
- three-finger up/down semantic command 구현
- Mac trackpad 설정 반영: natural scroll, speed, pinch enabled

완료 기준:

- 클릭 위치 평균 오차 10px 이하
- pointer latency p95 80ms 이하
- scroll latency p95 120ms 이하
- Gallery/Chrome/Notes에서 pinch 확대/축소 성공
- Notes/Chrome/KakaoTalk 텍스트 필드에 한글 입력 성공

### V1-E: Clipboard blob

목표: 텍스트/이미지/파일/영상 클립보드를 같은 구조로 처리한다.

작업:

- `ClipboardCoordinator` Mac/Android 분리
- `BlobTransferManager` Mac/Android 추가
- base64 inline 제거
- chunk transfer 구현
- sha256 검증
- Android `FileProvider` 권한 검증
- Mac NSPasteboard image/file reconstruction
- thumbnail 생성
- history TTL/LRU 정리

완료 기준:

- Mac -> Android text 성공
- Android -> Mac text foreground/manual/IME 경로 성공
- Mac -> Android PNG 5MB 성공
- Android -> Mac PNG foreground/manual 경로 성공
- Mac -> Android PDF/ZIP/MP4 파일 clipboard 구성 성공
- history에서 최근 30개 표시와 re-copy 가능

### V1-F: ADB 없는 USB 검증

목표: production transport 가능 여부를 결정한다.

작업:

- Galaxy Tab S11 USB-C 연결 시 네트워크 인터페이스 생성 가능성 검증
- USB tethering 기반 Mac<->Android IP route 검증
- Android app server socket discovery 검증
- AOA bulk endpoint prototype
- 실패 시 Wi-Fi fallback을 production fallback으로 고정

완료 기준:

- ADB off 상태에서 최소 하나의 USB transport prototype이 hello/pair/ping까지 성공한다.
- 불가능하면 제품 문구에서 "ADB 없는 USB 자동 연결"을 제거하고 fallback 정책을 확정한다.

### V1-G: Product release

목표: 설치 가능한 제품 품질로 마감한다.

작업:

- Mac universal build
- DMG packaging
- Developer ID signing
- notarization
- Android release signing
- crash-safe reconnect
- permission onboarding
- diagnostics export
- QA matrix 실행
- release checklist 작성

완료 기준:

- Intel Mac과 Apple Silicon Mac에서 앱 실행
- Galaxy Tab S11 실기기에서 release APK 실행
- 권한 미허용 상태에서 앱이 죽지 않고 안내 표시
- cable unplug/replug 20회 반복에서 입력 복구
- clipboard payload가 로그에 남지 않음

## 12. 파일별 수정 계획

### macOS

| 파일 | 수정 |
|---|---|
| `Sources/MtoGMac/SessionProtocol.swift` | v2 frame/protobuf wrapper로 교체 |
| `Sources/MtoGMac/SessionClient.swift` | `MtoGLinkSession`으로 분리 |
| `Sources/MtoGMac/Transport.swift` | transport protocol 정의 |
| `Sources/MtoGMac/ADBCommandChannel.swift` | bootstrap 전용으로 축소 또는 제거 |
| `Sources/MtoGMac/ControlModeInputController.swift` | raw capture만 담당하도록 축소 |
| `Sources/MtoGMac/InputEventRouter.swift` | 신규 |
| `Sources/MtoGMac/InputFrameScheduler.swift` | 신규 |
| `Sources/MtoGMac/ClipboardSyncController.swift` | `ClipboardCoordinator`로 재설계 |
| `Sources/MtoGMac/ClipboardHistoryPersistence.swift` | metadata/blob reference 구조로 변경 |
| `Sources/MtoGMac/DeviceIdentityStore.swift` | ephemeral key/session handshake 추가 |
| `Sources/MtoGMac/SessionReplayGuard.swift` | stream별 replay guard로 변경 |
| `Sources/MtoGMac/DashboardView.swift` | transport/security/diagnostics UI 정리 |

### Android

| 파일 | 수정 |
|---|---|
| `AdbLoopbackServer.kt` | `AdbForwardServer` + dispatcher로 분리 |
| `SessionProtocol.kt` | v2 protobuf/frame으로 교체 |
| `SessionForegroundService.kt` | `LinkForegroundService` 역할로 확장 |
| `AccessibilityControlService.kt` | gesture primitive만 담당 |
| `RemoteKeyboardService.kt` | text/IME command 중심으로 고정 |
| `RemoteInputBridge.kt` | bridge 축소, dispatcher에서 호출 |
| `ClipboardSyncManager.kt` | metadata/blob 구조로 교체 |
| `ClipboardHistoryStore.kt` | thumbnail/blob reference/TTL 추가 |
| `DeviceIdentityStore.kt` | ephemeral key/session handshake 추가 |
| `SessionReplayGuard.kt` | stream별 replay guard |
| `UsbDirectTransportAdapter.kt` | production candidate prototype |
| `UdpTransportAdapter.kt` | fallback/experimental로 격리 |
| `MainActivity.kt` | onboarding/diagnostics/revoke/history 정리 |

## 13. 우선순위

지금 바로 시작할 순서는 다음이다.

1. 우클릭/키보드/클립보드 fallback처럼 UX를 망치는 현재 매핑 제거
2. ADB shell input 의존 제거
3. 입력 이벤트 router/scheduler 추가
4. Protocol v2 설계와 protobuf 적용
5. 세션 암호화 적용
6. 클립보드 blob 전송 구현
7. ADB 없는 USB prototype
8. release packaging과 QA

## 14. QA 매트릭스

필수 테스트 기기:

- Apple Silicon MacBook
- Intel Mac
- Galaxy Tab S11
- Galaxy Tab S11 Ultra 가능하면 추가

필수 Android 앱:

- Samsung Notes
- Samsung Gallery
- Chrome
- Files
- YouTube
- KakaoTalk
- Gmail 또는 Google Docs

필수 입력 테스트:

- single click
- right click context
- drag select
- two-finger scroll
- pinch zoom in/out
- three-finger recents
- 한글 문장 입력
- 영어/숫자/특수문자 입력
- delete/enter/arrow
- control mode exit

필수 클립보드 테스트:

- Mac -> Android text
- Android -> Mac text
- Mac -> Android URL
- Mac -> Android PNG
- Android -> Mac PNG
- Mac -> Android PDF
- Mac -> Android MP4
- history re-copy
- large file rejection
- clipboard permission blocked state

필수 failure 테스트:

- cable unplug during control
- cable unplug during clipboard transfer
- Mac sleep/wake
- Android screen lock/unlock
- Accessibility disabled
- MtoG Keyboard disabled
- trusted peer revoked
- corrupted frame
- replayed frame
- wrong pairing code 5회

## 15. 절대 약속하면 안 되는 것

- 모든 Android 앱에서 완전 동일한 마우스/키보드 동작
- Android 백그라운드 클립보드 100% 자동 감지
- ADB 없는 USB 자동 연결 100% 보장
- Bluetooth 기반 primary 저지연 제어
- 게임용 초저지연 입력
- Mac이 Galaxy에 진짜 USB HID 키보드/마우스로 보인다는 주장
- Samsung/OEM 권한 없이 시스템 수준 입력 주입 가능하다는 주장

## 16. V1 최종 Definition of Done

V1은 다음 조건을 모두 만족해야 완료로 본다.

- Mac/Android release install package가 존재한다.
- 최초 4자리 페어링과 trusted reconnect가 동작한다.
- 모든 payload가 세션 암호화된다.
- ADB shell input 없이 클릭/키보드/스크롤/핀치가 동작한다.
- 한글 입력이 자모 분해되지 않는다.
- 우클릭이 Back으로 동작하지 않는다.
- Mac -> Android 텍스트/이미지 클립보드가 안정적으로 동작한다.
- Android -> Mac 텍스트/이미지 클립보드는 foreground/manual/IME-assisted 중 지원 경로가 명확하다.
- 파일/영상 클립보드는 chunk/blob 구조로 동작하거나 명확한 제한 UI를 가진다.
- history는 최근 항목을 빠르게 보여주고 re-copy가 가능하다.
- 연결 끊김, 권한 해제, 앱 재시작에서 입력이 Mac에 갇히지 않는다.
- Intel Mac과 Apple Silicon Mac에서 같은 앱 bundle이 실행된다.
- Galaxy Tab S11에서 APK가 설치되고 앱이 crash 없이 실행된다.
- QA 매트릭스의 필수 항목이 통과하거나 known limitation으로 문서화된다.

