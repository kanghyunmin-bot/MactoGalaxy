# Installed-app repair checkpoint

## Confirmed causes

1. Copying a linked executable into an existing .app without resealing the bundle caused codesign verification to fail (resources required but missing). A complete bundle must be signed and verified after including its helper. Local ad-hoc development updates can still change macOS permission identity; no permanent Developer ID trust is claimed.
2. Installed-app ScreenCaptureKit returned TCC permission denied. Running the helper from a separately authorized development host was not equivalent evidence.
3. Startup could receive early EOF through ADB forwarding before Android capabilities were ready. Added bounded pre-video handshake retries, reproduced by a real loopback socket regression test.
4. A sampled installed-app main-thread stack stopped inside AppModel.init → DeviceIdentityStore.snapshot → KeychainStore.read → SecItemCopyMatching. This blocked window creation. The actual SecurityAgent prompt requires the login keychain password for the existing MtoG identity. The prior window-restoration-only explanation was incomplete.

## Changes and verification

- AppKit owns one utility window with SwiftUI dashboard content; startup window appears before identity access.
- Existing identity loads off the main thread. Failure is displayed and retryable; it no longer silently substitutes an ephemeral identity with an empty public key.
- Actual installed app shows a visible MtoG window while awaiting the keychain. Authentication remains a user action; no password or private key was inspected, logged, changed or removed.
- Screen Recording and Accessibility status are displayed from the current process. Settings links and startup preflight provide actionable failures.
- Worker error survives termination instead of being replaced by exit code 2.
- Screen capture start/stop have deadlines; a late capture result cannot install a stream after cleanup. Capture errors propagate out of the worker.
- scripts/install-macos-dev.sh builds a complete local bundle, signs helper then app, verifies, replaces the stopped installed app, and registers Spotlight/LaunchServices. Certificate/private-key-free ad-hoc signing is for local development only.
- Full verify-no-device.sh PASS: 46 Swift tests, Android/Kotlin tests, debug/release Swift builds, Android debug build/lint, shared fixtures, artifact/legacy checks. New image test verifies JPEG bytes, MIME, filename, length and corrupted hash rejection. Oversize file rejection is tested with isolated temporary storage.

## Pending hardware qualification

ADB currently reports no connected device. Awaiting USB reconnection and user completion of the native keychain authentication prompt. Installed-app screen output, touch, repeated start/stop/reconnect, and bidirectional photo/file delivery MUST NOT be marked passed from these code or startup checks. Earlier direct-helper output is historical and does not qualify this installation.

## Retry after USB reconnection

- Galaxy [device serial omitted] is authorized over USB again.
- /Applications/MtoG.app passes strict deep signature verification, opens its dashboard, loads the existing identity, and reconnects to the trusted tablet.
- Current process reports Screen Recording and Accessibility unavailable. Screen Recording settings still displayed MtoG enabled, demonstrating that the visible stale setting alone does not prove current-process authorization.
- Used the standard settings toggle to refresh the MtoG entry. macOS presented its native Touch ID / password authentication sheet before applying the change. User authentication is pending; no authentication was bypassed.
- Installed-app extended display and touch remain DEVICE_TEST_PENDING. No new code or test-suite run in this retry.

## Fullscreen follow-up

User confirms installed-app extended display and touch work after permission approval. Fixed absent immersive mode in Android ExternalDisplayActivity. Full no-device suite PASS, replacement APK installed successfully, trusted USB reconnected and installed Mac display restarted. Live tablet window state: navigationBars visible=false; statusBars visible=false. Video SurfaceView bounds [0,0][2960,1848], no navigation bar background or pending-stream overlay in UI hierarchy. This is live layout/system-bar verification; no additional latency or physical touch accuracy claim.

## 0.2.0 release smoke check

Installed the exact universal Mac bundle from the published DMG and updated the tablet to the same source version/build 6 with its existing debug signer. Both include the new icon. Following permission refresh through System Settings, the current Mac process reports capture/accessibility granted and emits HEVC 2560×1600 readiness; tablet UI has the full 2960×1848 Surface and no pending/error overlay. Release APK signature matches the previous published APK. GitHub asset hashes match local artifacts. This is not a new full physical touch or binary-transfer qualification.
