# Verification matrix

| Area | No-device evidence | Device status |
|---|---|---|
| Shared limits | Swift and Kotlin read `Fixtures/protocol-v2/manifest.json` | Not required |
| Control protocol v2 | Shared canonical frame, fragmentation, truncation, malformed header/JSON, replay, and backoff tests | DEVICE_TEST_PENDING for live pairing and reconnect |
| Pairing identity and trust | Existing persistence formats remain unchanged | DEVICE_TEST_PENDING |
| Clipboard history | Existing persistence formats remain unchanged | DEVICE_TEST_PENDING |
| Manual image and file clipboard | Existing app path remains during refactor | DEVICE_TEST_PENDING |
| Mirror and USB bootstrap | Existing app path remains during refactor | DEVICE_TEST_PENDING |
| Input and AOA HID | Existing app path remains during refactor | DEVICE_TEST_PENDING |
| Automatic text/URL clipboard | Swift in-memory store/transport round trip plus Swift/Kotlin event, hash, loop, replay, reconnect, UTF-8, URL, and 256 KiB tests | BLOCKED until production shell authority is verified |
| H.264/HEVC stream | Shared binary config/keyframe/delta fixtures, incremental parser/state/queue tests, and synthetic BGRA framing | DEVICE_TEST_PENDING for VideoToolbox and MediaCodec display |
| Private virtual display | Build and failure isolation planned in S5 | DEVICE_TEST_PENDING |
| UI states | Reducer tests and Mac mock-state exercise planned in S8 | Android interaction DEVICE_TEST_PENDING without emulator |

No no-device result proves Galaxy compatibility, hardware codec output, private API behavior, USB operation, or performance.
