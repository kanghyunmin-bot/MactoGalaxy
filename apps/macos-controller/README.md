# macOS Controller

Planned app responsibilities:

- global input capture
- edge detection
- Android control mode state machine
- secure session and transport selection
- clipboard sync and local clipboard history UI
- pairing, trusted-device storage, reconnect

Recommended module split:

- `ControlModeCoordinator`
- `GlobalEventTapMonitor`
- `EdgeCrossingDetector`
- `SessionManager`
- `TransportBroker`
- `ClipboardMonitor`
- `ClipboardHistoryStore`
- `SettingsWindowController`

Build target:

- universal macOS app (`arm64`, `x86_64`)
- Apple Silicon primary path
- supported Intel Macs secondary path
