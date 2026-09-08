# Verification matrix

| Area | Automated evidence | Device evidence / remaining work |
|---|---|---|
| Protocol and input geometry | Swift/Kotlin shared fixtures, malformed/fragmented frames, replay, gestures | Trusted USB reconnect, tap and drag observed; scroll pending |
| Automatic text | Fake process/real socket, UTF-8/size, stale sends and cleanup | Korean/emoji/URL and size boundary passed; rapid reverse-update race, lock/background gestures pending |
| Images/files | Original JPEG bytes/MIME/name, corrupt hash and size rejection | DEVICE_TEST_PENDING for end-to-end binary delivery |
| Video | Parsers, queue recovery, VideoToolbox round trips, Android decoder lifecycle | HEVC/H.264 output observed; user confirmed installed-app display and touch |
| Surface/fullscreen | Android Surface recreation instrumentation | 2 instrumentation tests passed; full 2960×1848 Surface, system bars hidden |
| Mac startup/permissions | Build and lifecycle cleanup checks | Startup window visible during keychain approval; valid signed bundle; user confirmed operation after grants |
| Performance | Optional synthetic benchmark only | Samples 57–59 decoder submissions/s; continuous 60fps and broad device support unproven |

Run `./scripts/verify-no-device.sh`: Swift tests/debug/release builds; Kotlin/Android tests, instrumentation compilation, lint/debug build; shared fixtures and repository policy. It never launches devices or private display APIs. Hardware tests and release packaging are separate.

VideoToolbox unit tests use 64×48 frames. Unsupported HEVC capability is reported rather than treated as a pass. `check-no-secrets.sh` checks file paths, not secret contents. See [device report](device-runs/2026-09-08/README.md) for limits and [benchmark notes](no-device-benchmark.md) for metric interpretation.
