# Repository rules

- Run `./scripts/verify-no-device.sh` after each refactor slice.
- Keep protocol fixtures in `Fixtures/protocol-v2/` and require Swift and Kotlin tests to read the same files.
- Keep `MtoGCore` and Android `:core` free of AppKit, SwiftUI, Android framework, ADB, and UI dependencies.
- Do not run ADB device commands, scrcpy sessions, emulators, private display APIs, packaging, signing, or deployment as part of no-device verification.
- Record physical-device claims as `DEVICE_TEST_PENDING`. Record unsupported production authority as `BLOCKED`.
- Do not claim transport encryption. Session tokens and nonces only reject stale session traffic.
- Preserve persisted identity, trusted-peer, keychain/keystore alias, and clipboard-history formats.
- Do not add protocol v1 or JPEG display fallbacks.
- Update `docs/refactor-progress.md` before ending a slice or session.
