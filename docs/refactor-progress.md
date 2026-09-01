# Refactor progress

## Baseline

Date: 2026-09-01

Branch: `khm/mtog-harness-refactor`

The tracked baseline was clean. Swift 6.3.3 debug build passed. macOS Java lookup failed, but existing Homebrew OpenJDK 17.0.19 made Gradle 8.10.2 and `:app:assembleDebug` pass when exported as `JAVA_HOME`. ADB 37.0.0 found no devices. scrcpy 3.3.4 was available. No emulator command was available.

## Slices

| ID | Slice | Status | Device status | Remaining risk |
|---|---|---|---|---|
| S1 | Repository harness and fixture skeleton | PASS | DEVICE_TEST_PENDING | No physical device or emulator baseline |
| S2 | Bounded control session | PASS | DEVICE_TEST_PENDING | Live pairing, transport, and reconnect require hardware |
| S3 | Automatic text/URL clipboard | PASS | BLOCKED | Production standalone shell authority is not verified |
| S4 | Video protocol and synthetic transport | PASS | DEVICE_TEST_PENDING | VideoToolbox and MediaCodec are not part of this slice |
| S5 | Mac capture and encode | PASS | DEVICE_TEST_PENDING | Private display creation and capture permission require hardware validation |
| S6 | Android decode and Surface | PASS | DEVICE_TEST_PENDING | Rendered MediaCodec output requires a device or emulator |
| S7 | Session, input, and ADB serial integration | NOT_STARTED | DEVICE_TEST_PENDING | Commands can select arbitrary devices |
| S8 | Simplified UI | NOT_STARTED | DEVICE_TEST_PENDING | Current UI and combined state remain |
| S9 | Legacy removal and final verification | NOT_STARTED | DEVICE_TEST_PENDING | Final static checks not registered |

## S1 repository harness and fixture skeleton

Changed files: `Package.swift`, `Package.resolved`, Android Gradle settings, new Swift and Kotlin core/test files, shared fixture manifest, harness scripts, and architecture/protocol/validation documents.

Test-first result: Swift failed because `Sources/MtoGCore` did not exist. Kotlin failed to compile because `ProtocolLimits` did not exist. After adding the constants, Kotlin passed. The installed Command Line Tools lacked Testing and XCTest modules, so the Swift test target pins the official `swift-testing` 0.12.0 test dependency.

Focused verification:

- `swift test`: PASS, one shared-manifest test.
- `./gradlew :core:test`: PASS, one shared-manifest test.

Full verification:

- `./scripts/verify-no-device.sh`: PASS.
- Swift test, debug build, and release build: PASS.
- Android `:core:test`, `:app:testDebugUnitTest`, `:app:lintDebug`, and `:app:assembleDebug`: PASS. The app unit-test task currently reports `NO-SOURCE`.
- Fixture, repository artifact, tracked secret-path, and `git diff --check` gates: PASS.
- Benchmark: `NOT_RUN` by verifier design.

Independent review found that Gradle did not track fixture changes, artifact checks missed Swift/Gradle output directories, Python optimization could disable fixture assertions, and this record still had placeholders. The harness now declares `Fixtures/` as a Gradle input, checks all known build directories, uses explicit Python failures, and records the completed gate. No device behavior was claimed.

## S2 bounded control session

Changed files: shared control/session core types and tests, canonical control fixtures, Mac `SessionClient`, Android `AdbLoopbackServer`, module dependencies, protocol documentation, and static legacy checks.

Test-first result: Swift and Kotlin test compilation failed because control framing, replay, state, backoff, negotiation, geometry, and queue types did not exist. After implementation, focused Swift and Kotlin core tests passed. One Swift fragmented-frame test exposed nonzero `Data` indices after removal; normalizing the remaining buffer fixed the crash.

Verification:

- `swift test --no-parallel`: PASS, 11 tests.
- `swift build` and `swift build -c release`: PASS.
- `./gradlew :core:test :app:testDebugUnitTest :app:lintDebug :app:assembleDebug`: PASS. Kotlin core has 10 tests. App unit tests remain `NO-SOURCE` until app-specific state tests are added.
- `./scripts/verify-no-device.sh`: PASS after the final trust-race change.
- Canonical fixtures, registered legacy paths, repository artifacts, tracked secret paths, and diff whitespace checks: PASS.

Independent protocol review found and then rechecked timestamp incompatibility, stale replay, socket replacement races, reconnect resets, pre-handshake connected state, sequence ordering, maximum-frame concatenation, legacy mismatch reporting, UUID and geometry differences, pre-trust clipboard disclosure, handshake ordering, and reconnect-time clipboard races. The implementation now uses a four-message nonce handshake, exact confirmation ID echo, per-socket generation, serialized Android sequence/write assignment, strict trust gates on both peers, and generation-bound Mac clipboard sends. The final narrow review reported no remaining trust race.

Physical pairing, reconnect, LAN, and USB behavior remain `DEVICE_TEST_PENDING`. Session tokens and nonces do not provide transport encryption.

## S3 automatic text/URL clipboard

Changed files: shared clipboard event, loop guard, coordinator, in-memory store/transport, Swift and Kotlin tests, Mac pasteboard/backend/coordinator files, scrcpy arguments, Android manual clipboard manager, current UI status, static checks, and verification documents.

Test-first result: Swift and Kotlin tests failed because clipboard event, engine, result, and transport types did not exist. The pure implementations now validate UTF-8 byte limits and SHA-256, reject reflected hashes, duplicate sequences, and old sessions, and preserve recent hashes across reconnects.

Verification:

- `swift test --no-parallel`: PASS, 14 tests. Fake store/transport tests exercise Korean, emoji, URLs, rapid changes, reconnect staleness, bad hashes, maximum and oversized content, stop, and blocked authority.
- `swift build` and `swift build -c release`: PASS.
- `./gradlew :core:test :app:testDebugUnitTest :app:lintDebug :app:assembleDebug`: PASS. Kotlin fake transport covers the same edge set.
- `./scripts/verify-no-device.sh`: PASS after the final adapter and validation changes.

scrcpy 3.3.4 documents mirror clipboard autosync, so mirror launch no longer passes `--no-clipboard-autosync`. Its help exposes no verified standalone clipboard authority. `ShellClipboardTransport` therefore returns `BLOCKED` and starts no process. Android attaches no clipboard listener and keeps explicit manual sync.

Independent review found incorrect pasteboard suppression, unchecked public event construction, binary/file observation regression, and fake-transport coverage gaps. The adapter now suppresses an exact change count, has a separate all-types observation callback, both engines reject invalid identity/sequence/content, and both fake transports run the full edge set. Re-review reported no remaining findings. Manual image/video/file transfer and history code remain in place.

## S4 video protocol and synthetic transport

Changed files: shared video packet, parser, receiver state, latest-frame queue, fallback state, binary fixtures, MtoGMedia target, synthetic frame source, tests, fixture verifier, protocol documentation, and static checks.

Test-first result: Swift and Kotlin compilation failed because video packet, parser, receiver, queue, and fallback types did not exist. The implementations use a 64-byte `MTGV` header, raw payloads, per-kind limits, UUID sessions, sequence and timestamp checks, config-before-frame rules, keyframe recovery, and a one-time HEVC fallback.

Verification:

- `swift test --no-parallel`: PASS, 22 tests including synthetic pattern framing with 7-byte fragmentation.
- `swift build` and `swift build -c release`: PASS.
- `./gradlew :core:test :app:testDebugUnitTest :app:lintDebug :app:assembleDebug`: PASS with shared config/keyframe/delta fixtures and parser/state/queue tests.
- `./scripts/verify-no-device.sh`: PASS after final recovery-boundary assertions.

Independent review found unbound reconnect sessions, keyframe-eviction recovery gaps, whole-chunk Swift parser allocation, signed sequence mismatch, encoder/header validation differences, ignored reserved bytes, and a test-count error. Those were fixed with expected-session binding, session/sequence recovery boundaries, region-streamed parsing, signed-range parity, canonical header checks, and updated tests/docs. Re-review then found delayed acknowledgement coverage gaps; both suites now verify stale same-session and old-session acknowledgements plus active-boundary reset.

Hardware encoding and decoding remain outside this slice and `DEVICE_TEST_PENDING`.

## S5 Mac capture and encode

Changed files: MtoGMedia NAL conversion, hardware encoder/decoder and realtime encoder, VideoToolbox round-trip tests, decomposed worker backend/capture/encoder/sender/input/lifecycle files, package dependencies, benchmark script, static checks, and architecture/progress documents.

Test-first result: Swift test compilation failed because VideoToolbox capability, encoder, decoder, and round-trip result types did not exist. The implemented tests encode synthetic BGRA frames with required hardware H.264, packetize Annex-B config/access units through fragmented MTGV transport, reconstruct samples, and decode with VideoToolbox. HEVC uses the same path when hardware is available and otherwise returns an explicit unavailable reason.

Verification:

- `swift test --no-parallel`: PASS, 26 tests. H.264 and available HEVC hardware round trips pass with frame count, dimensions, monotonic timestamps, config, and keyframe evidence.
- `swift build` and `swift build -c release`: PASS with the decomposed worker.
- `./gradlew :core:test :app:testDebugUnitTest :app:lintDebug :app:assembleDebug`: PASS.
- `./scripts/verify-no-device.sh`: PASS after the final backpressure race test.
- Static search finds no `CGDisplayCreateImage`, JPEG, `FRAM`, or `MTOGVD1` in the worker. Private virtual-display lookup is confined to `CGVirtualDisplayBackend.swift`.

The worker uses a latest-frame ScreenCaptureKit callback queue, a separate encode loop, a latest-only encoded pump, and a one-second socket send timeout. Bitrate is resolution-based and capped at 40 Mbps with a data-rate window. Receiver capability negotiation defaults to H.264 until capabilities are supplied and permits one hardware HEVC-to-H.264 fallback. VideoToolbox frame drops are nonfatal. Shutdown stops capture, completes compression, drains bounded output, closes video/input sockets, joins touch input, releases the display, and removes ADB mappings.

Independent review found unbounded output, blocking shutdown, unbounded bitrate, fatal normal frame drops, missing receiver negotiation/fallback, unjoined touch input, stopped-queue retention, and config/keyframe backpressure races. All were fixed and the final narrow review reported no findings. Private display creation and real ScreenCaptureKit permission remain `DEVICE_TEST_PENDING`.

## S6 Android decode and Surface

Changed files: thin external display Activity, MTGV socket receiver, MediaCodec decoder, decoder state machine, capability reader, ViewModel diagnostics, SurfaceView Compose host, extracted touch controller, streaming notification state, app unit and instrumentation tests, static checks, and architecture/progress documents.

Test-first result: app unit-test compilation failed because decoder states and commands did not exist. Three pure lifecycle tests now cover frame-before-config, Surface availability/loss, config and session changes, keyframe recovery, duplicates, stop, and one HEVC-to-H.264 fallback request.

Verification:

- `./gradlew :app:testDebugUnitTest`: PASS, three decoder state tests.
- `./gradlew :app:compileDebugAndroidTestKotlin :app:lintDebug :app:assembleDebug`: PASS.
- `./scripts/verify-no-device.sh`: PASS with instrumentation source compilation included.
- Static search finds no Bitmap/JPEG/legacy framing in the external display Activity or package.

Socket parsing and MediaCodec feeding run on IO dispatchers. Compose hosts an aspect-fit SurfaceView and only observes diagnostics. Android advertises queried decoder size/rate capabilities over the video socket. It sends keyframe and one H.264 fallback request back to the worker. The Mac forces a keyframe or reconfigures its hardware encoder in place. Receiver reconnect accepts new clients. Pause/resume uses ordered generations and retains replacement config. MediaCodec input backpressure requests recovery. Streaming state and notification begin only from the active decoder generation’s frame-rendered callback. Diagnostics reset on config and disconnect.

Independent review found ineffective negotiation/recovery, one-shot receive, input-buffer drops, stale diagnostics, early notification, missing pause/resume, aspect/touch mismatch, codec leaks, fixed capability claims, fallback races, and stale render callbacks. All were fixed, and the final narrow review reported no findings. Actual H.264/HEVC decode, rendered Surface output, rotation, and instrumentation execution remain `DEVICE_TEST_PENDING`.
