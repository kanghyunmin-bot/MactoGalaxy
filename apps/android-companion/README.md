# Android Companion

Build prerequisites:

- JDK 17 available via `JAVA_HOME` or `java` on `PATH`
- Android SDK installed locally
- `local.properties` with `sdk.dir=...` when the SDK is not in the default location
- Build with `./gradlew assembleDebug`

Planned app responsibilities:

- USB and fallback transport endpoint
- foreground connection service
- accessibility-driven remote control
- companion IME for text entry and clipboard access
- provider-backed clipboard/resource reconstruction
- local clipboard history UI
- trusted-device persistence and reconnect

Recommended component split:

- `MainActivity`
- `ConnectionForegroundService`
- `RemoteAccessibilityService`
- `RemoteInputMethodService`
- `RemoteClipboardProvider`
- `ClipboardHistoryRepository`
- `SessionManager`
- `TransportBroker`

Target hardware:

- Galaxy Tab S11
- Galaxy Tab S11 Ultra
