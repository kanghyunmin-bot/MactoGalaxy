# Device validation

No physical device or emulator was available during the baseline. Every row remains `DEVICE_TEST_PENDING` or `NOT_MEASURED` until evidence is attached.

| Check | Target | Measured | Status | Evidence |
|---|---|---|---|---|
| Galaxy model, Android, One UI | Supported Galaxy tablet | NOT_MEASURED | DEVICE_TEST_PENDING | None |
| Cable and negotiated USB speed | Record cable and speed | NOT_MEASURED | DEVICE_TEST_PENDING | None |
| Selected ADB serial | Exact user-selected serial | NOT_MEASURED | DEVICE_TEST_PENDING | None |
| Samsung Keyboard retained | No keyboard switch | NOT_MEASURED | DEVICE_TEST_PENDING | None |
| Text Mac to Galaxy | UTF-8 text and URL | NOT_MEASURED | DEVICE_TEST_PENDING | None |
| Text Galaxy to Mac | UTF-8 text and URL | NOT_MEASURED | DEVICE_TEST_PENDING | None |
| Foreground/background/lock clipboard | Record each state | NOT_MEASURED | DEVICE_TEST_PENDING | None |
| Disconnect and reconnect | No stale replay; bounded retry | NOT_MEASURED | DEVICE_TEST_PENDING | None |
| Trusted reconnect/history/mirror/AOA HID | Existing behavior preserved | NOT_MEASURED | DEVICE_TEST_PENDING | None |
| scrcpy autosync regression | Installed version and Galaxy | NOT_MEASURED | DEVICE_TEST_PENDING | None |
| Headless clipboard authority | Publicly documented authority | NOT_MEASURED | BLOCKED | scrcpy 3.3.4 help has no standalone authority |
| CGVirtualDisplay create/cleanup | Create, stop, reboot, recreate | NOT_MEASURED | DEVICE_TEST_PENDING | None |
| ScreenCaptureKit permission | Capture generated display | NOT_MEASURED | DEVICE_TEST_PENDING | None |
| MediaCodec HEVC | Hardware decode to Surface | NOT_MEASURED | DEVICE_TEST_PENDING | None |
| MediaCodec H.264 | Hardware decode to Surface | NOT_MEASURED | DEVICE_TEST_PENDING | None |
| Codec fallback | One HEVC to H.264 retry | NOT_MEASURED | DEVICE_TEST_PENDING | None |
| Resolution and refresh | 2560x1600, target 60 fps | NOT_MEASURED | DEVICE_TEST_PENDING | None |
| Ten-minute stream | Stable for 10 minutes | NOT_MEASURED | DEVICE_TEST_PENDING | None |
| Latency/fps/bitrate/drop | Record measured values | NOT_MEASURED | DEVICE_TEST_PENDING | None |
| Memory and thermal | Record both devices | NOT_MEASURED | DEVICE_TEST_PENDING | None |
| Rotation and Surface recreation | Resume decoded output | NOT_MEASURED | DEVICE_TEST_PENDING | None |
| Tap/drag/scroll | Correct mapped input | NOT_MEASURED | DEVICE_TEST_PENDING | None |
| Permission denial and regrant | Accessibility and Screen Recording | NOT_MEASURED | DEVICE_TEST_PENDING | None |
