# Device validation — 2026-09-08

Samsung SM-X930 (Android 16), USB 5 Gbit/s. Existing app data and Samsung Keyboard preserved.

- User confirmed installed-app extended display and touch after macOS permissions were granted.
- HEVC 1920×1200 and H.264 2560×1600 rendered on the tablet. Active-content samples reached 57–59 decoder submissions/s; uninterrupted 60fps is not established. The HEVC sample set has a 111-second gap.
- Tap and drag reached a generated Mac test window. Scroll and broader touch accuracy remain unqualified.
- Fullscreen update: status/navigation bars hidden; video SurfaceView covers 2960×1848. Edge swipe uses Android transient system bars.
- Automatic Korean/emoji/URL text in both directions, maximum 262130-byte text, and stop behavior passed using an independent clipboard observer. A rapid reverse-update race remains in the reconnect evidence.
- Android codec and Surface recreation instrumentation: 2 tests passed.
- Full no-device verification: 46 Swift tests plus Kotlin/Android tests, Android lint/build, shared fixtures and repository checks passed before release preparation.

See `clipboard.json`, `reconnect-with-immediate-reverse.json`, `hevc-soak.json` for measurements and `installed-app-repair.md` for permission/startup findings.

DEVICE_TEST_PENDING: end-to-end photo/file delivery, repeated physical unplug/replug, lock/background clipboard gestures, long-duration high-resolution performance, and other tablet models. Image/file serialization and size limits are covered by automated tests, not equivalent to end-to-end delivery.
