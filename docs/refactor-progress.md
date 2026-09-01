# Refactor progress

## Baseline

Date: 2026-09-01  
Branch: `khm/mtog-harness-refactor`

The tracked baseline was clean. Swift 6.3.3 debug build passed. macOS Java lookup failed, but existing Homebrew OpenJDK 17.0.19 made Gradle 8.10.2 and `:app:assembleDebug` pass when exported as `JAVA_HOME`. ADB 37.0.0 found no devices. scrcpy 3.3.4 was available. No emulator command was available.

## Slices

| ID | Slice | Status | Device status | Remaining risk |
|---|---|---|---|---|
| S1 | Repository harness and fixture skeleton | PASS | DEVICE_TEST_PENDING | No physical device or emulator baseline |
| S2 | Bounded control session | NOT_STARTED | DEVICE_TEST_PENDING | Newline JSON remains |
| S3 | Automatic text/URL clipboard | NOT_STARTED | BLOCKED | No verified standalone shell authority |
| S4 | Video protocol and synthetic transport | NOT_STARTED | DEVICE_TEST_PENDING | Binary framing not implemented |
| S5 | Mac capture and encode | NOT_STARTED | DEVICE_TEST_PENDING | JPEG worker remains |
| S6 | Android decode and Surface | NOT_STARTED | DEVICE_TEST_PENDING | Bitmap decode remains |
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
