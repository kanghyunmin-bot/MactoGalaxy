# VS Code UI Preview

## 빠른 실행

VS Code 통합 터미널에서 아래 명령을 실행:

```bash
python3 -m http.server 4173 -d preview
```

그 다음 VS Code에서:

1. Command Palette 실행
2. `Simple Browser: Show` 선택
3. `http://127.0.0.1:4173` 입력

## 용도

- macOS 앱과 Android 앱의 화면 구성을 빠르게 확인
- 4자리 페어링, 전송 상태, 클립보드 히스토리 레이아웃 검토
- Xcode / Android Studio 없이 VS Code 안에서 확인

## 제한

- 실제 앱이 아니라 정적 프리뷰
- 현재 상태에서는 데이터 저장이나 실제 제어 동작 없음
