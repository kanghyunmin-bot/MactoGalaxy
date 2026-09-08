# Target state

## Dependency direction

`MtoGCore` owns protocol framing, session and replay rules, reconnect policy, clipboard events, codec negotiation, geometry, and bounded queues. It imports no AppKit, SwiftUI, ADB, or media framework.

`MtoGPlatform` depends on `MtoGCore` and owns bounded process execution and the scrcpy control adapter, shared by Mac and worker. It is tested through fake executables and loopback sockets.

`MtoGMedia` depends on `MtoGCore` and owns VideoToolbox and synthetic frames. `MtoGMac` owns UI, pasteboard, processes, ADB, and feature coordination. `MtoGExternalDisplayWorker` is a small lifecycle entry point with private `CGVirtualDisplay` calls isolated to one backend file.

Android `:core` is a Kotlin/JVM module without Android imports. Android `:app` owns sockets, services, `ClipboardManager`, MediaCodec, SurfaceView, input, and Compose.

## Test and JSON dependencies

The Swift test target pins the official Swift project `swift-testing` package to `0.12.0` because the installed Command Line Tools omit both Testing and XCTest modules. The package uses Apache License 2.0 and is not linked into production targets.

Android `:core` pins `org.jetbrains.kotlinx:kotlinx-serialization-json` to `1.8.0` and the Kotlin serialization plugin to `2.1.10`. JetBrains maintains Kotlin and kotlinx.serialization. Both use the Apache License 2.0. The module uses `kotlin-test` from the same Kotlin toolchain for local JVM tests.

Android framework `org.json` methods are stubs in local JVM tests unless a separate implementation is added. The pure core therefore uses kotlinx.serialization rather than importing Android framework classes. No media or network dependency is added.

## Runtime boundaries

Control and video use separate bounded protocol v2 frames. The receiver checks declared lengths before allocating payload storage. Session tokens and nonces bind connection generations and reject stale traffic, but do not encrypt LAN traffic.

The display path is `CGVirtualDisplayBackend -> ScreenCaptureKit -> VideoToolbox -> bounded binary transport -> MediaCodec -> SurfaceView`. There is no JPEG or software-codec fallback.

Automatic clipboard sync accepts only text and URLs through the pinned scrcpy 3.3.4 shell control adapter. Selected Galaxy text paths were tested; lock/background behavior and simultaneous-change reliability remain device-pending. Missing or mismatched server bytes report unsupported; it does not use IME, Accessibility, notifications, AppOps, or background `ClipboardManager` as a permission workaround.
