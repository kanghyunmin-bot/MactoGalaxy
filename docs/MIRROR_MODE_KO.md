# MtoG Mirror Mode

## 목적

안정성이 가장 중요한 화면 표시/제어 경로는 직접 구현하지 않고 `scrcpy`를 관리 실행하는 방식으로 둔다.

이 모드는 MtoG의 USB-C 직접 입력 연구(AOA HID)와 별개다. 목표는 Mac에 Galaxy Tab 화면을 띄우고, 검증된 `scrcpy` 제어 경로로 즉시 조작 가능하게 만드는 것이다.

## 현재 구현

Mac 앱의 Transport 카드에서 `Start Mirror`를 누르면 다음 옵션으로 `scrcpy`를 실행한다.

```bash
scrcpy \
  --serial=<detected-adb-serial> \
  --keyboard=uhid \
  --mouse=uhid \
  --mouse-bind=++++:bhsn \
  --shortcut-mod=lalt,ralt \
  --no-clipboard-autosync \
  --video-codec=h264 \
  --max-fps=60 \
  --max-size=1920 \
  --stay-awake \
  --no-audio \
  --window-title="MtoG Galaxy Mirror"
```

## 입력 방식

`--keyboard=uhid`와 `--mouse=uhid`를 사용한다.

이유:

- Android가 입력을 물리 HID 키보드/마우스처럼 받는다.
- 별도 Android 입력기 선택을 요구하지 않는다.
- SDK 마우스 모드에서 흔한 우클릭 = Back 매핑을 피한다.
- 일반 클릭, 우클릭, 스크롤이 Android 네이티브 외부 입력 경로에 더 가깝다.

`--mouse-bind=++++:bhsn`은 일반 마우스 버튼을 기본 클릭으로 유지하고, 보조 조합에서만 Back/Home/App switch/Notification 제스처를 쓰게 하는 설정이다.

`--shortcut-mod=lalt,ralt`는 `Command` 키가 `scrcpy` 내부 단축키로 먼저 먹히는 문제를 줄이기 위한 설정이다. Mirror 창이 앞에 있을 때 MtoG는 `Command+C/V/X/A/Z/F/S` 같은 Mac 단축키를 Android `Ctrl+C/V/X/A/Z/F/S` 조합으로 변환해서 보낸다.

`--no-clipboard-autosync`는 `scrcpy` 자체 클립보드 자동 동기화와 MtoG 클립보드 엔진이 동시에 같은 클립보드를 만져 충돌하는 것을 막기 위한 설정이다.

Mirror 창이 앞에 있을 때 `Esc` 또는 `Command+Q`를 누르면 MtoG가 Mirror Mode를 중지하고 Mac 제어로 복귀한다.

## 전제 조건

- Mac에 `scrcpy`가 설치되어 있어야 한다.
- Android USB debugging이 허용되어 있어야 한다.
- ADB에서 Galaxy Tab이 `device` 상태로 보여야 한다.
- Galaxy 화면이 잠겨 있거나 USB 디버깅 권한 팝업이 미승인 상태면 실행되지 않을 수 있다.

## 검증된 실기기 상태

2026-04-24 기준 로컬 검증:

- 기기: Samsung SM-X930
- Android: 16
- 연결: USB
- `scrcpy`: 3.3.4
- 렌더러: Metal
- 표시 텍스처: 1920x1200

## 한계

이 모드는 제품 최종 구조라기보다 안정성 높은 실사용 경로다.

- `scrcpy`는 ADB 기반이므로 USB debugging이 필요하다.
- Samsung DeX/보안 앱/DRM 화면은 앱별로 표시나 입력이 제한될 수 있다.
- 한글 물리 키보드 조합은 Galaxy의 물리 키보드 레이아웃 설정에 영향을 받는다.
- 초저지연 게임 제어용으로 보장하지 않는다.

## 사용 순서

1. Galaxy Tab을 USB-C로 Mac에 연결한다.
2. Galaxy에서 USB debugging 권한을 허용한다.
3. Mac 앱 `/Applications/MtoG.app`를 실행한다.
4. Transport 카드에서 `Start Mirror`를 누른다.
5. `MtoG Galaxy Mirror` 창에서 Galaxy 화면을 조작한다.
