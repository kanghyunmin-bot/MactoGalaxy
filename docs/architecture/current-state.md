# Architecture

- **MtoGCore / Android core:** bounded protocol v2 framing, replay/session state, clipboard payloads, display geometry and gestures; shared fixtures.
- **MtoGPlatform:** bounded subprocesses and pinned scrcpy 3.3.4 control-only clipboard transport.
- **MtoGMac:** AppKit window hosting SwiftUI, asynchronous keychain identity startup, trusted connection coordination, pasteboard sharing and Mac touch event synthesis.
- **MtoGExternalDisplayWorker:** isolated private CGVirtualDisplay backend, ScreenCaptureKit capture, VideoToolbox encoder, bounded video transport and touch receiver.
- **Android companion:** foreground connection service, sharing entry point and immersive MediaCodec Surface display. A new control session recreates its Surface callbacks.

The video path is ScreenCaptureKit → HEVC/H.264 → USB → MediaCodec. It has no JPEG fallback. Input uses shared coordinate mapping. Automatic text uses a separate scrcpy control-only session; images/files use manual protocol-v2 transfer.

Identity, trusted-peer and clipboard-history formats are preserved. Galaxy mirroring, edge activation, AOA/HID and custom IME/accessibility control are removed. Session validation is not transport encryption.

[Device qualification](../device-runs/2026-09-08/README.md) is separate from [no-device verification](../verification-matrix.md).
