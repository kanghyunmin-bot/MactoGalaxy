# Standalone USB text clipboard

## Pinned source and authority

The production adapter uses the unmodified **scrcpy-server v3.3.4**, executed through selected-serial ADB shell. Samsung Keyboard remains selected. There is no APK background listener, IME switch, Accessibility clipboard workaround, cloud account, or paid SDK.

Upstream: https://github.com/Genymobile/scrcpy/tree/v3.3.4

Official server: https://github.com/Genymobile/scrcpy/releases/download/v3.3.4/scrcpy-server-v3.3.4

SHA-256: `8588238c9a5a00aa542906b6ec7e6d5541d9ffb9b5d0f6e1bc0e365e2303079e`

On 2026-09-08, the installed Homebrew 3.3.4 server and separately downloaded official release had that same digest. Production fails closed for other bytes. The protocol is internal and version-specific; upgrades require source review, new pin and protocol tests. The server jar is not added to this repository. Runtime lookup checks the app resource, then Homebrew paths.

Reviewed official source files under that tag:

- `server/src/main/java/com/genymobile/scrcpy/Server.java`: control can run with `video=false audio=false`; process/component/socket cleanup.
- `Options.java`: accepted server options; exact version check.
- `control/Controller.java`: shell clipboard listener and get/set paths, `paste=false`, unconditional ACK even if set fails. With autosync enabled GET does not return the value, so this client uses `clipboard_autosync=false` and GET polling.
- `control/ControlMessageReader.java`, `ControlMessage.java`: GET type 8 with COPY_KEY_NONE; SET type 9, u64 sequence, paste byte, u32 UTF-8 length.
- `control/DeviceMessageWriter.java`: clipboard type 0 + u32 length; ACK type 1 + u64 sequence; UTF-8 truncation.
- `device/DesktopConnection.java`: control-only socket and scid namespace.
- `doc/develop.md`: shell launch and version-specific internal protocol. Its protocol examples describe an older version; implementation follows v3.3.4 source above.

## Runtime behavior

Enable automatic text in the Mac UI after a trusted USB handshake. Each worker owns a random scid, unique remote jar and dynamically allocated forward port. Device commands include the selected serial. Poll interval is 500 ms on Galaxy and 250 ms on Mac. Only clipboard values are transferred; neither GET nor SET injects a key. Mirror clipboard autosync is disabled to keep one owner. Automatic companion text sends/receives are suppressed while this feature is enabled; existing explicit manual image/file/history paths remain.

An initial readable Galaxy value establishes readiness. Socket connection or ACK alone never establishes a successful write. A Mac update temporarily wins over differing incoming values for up to two seconds while readback is pending. Matching readback confirms the value and is suppressed as reflection; latest queued local change replaces an unsent change. A verification mismatch ends the worker and reports failure; toggle off/on retries. Intermediate copies between polling intervals are not guaranteed to be transferred. This is value synchronization, not a clipboard event archive.

The effective adapter limit is **262130 UTF-8 bytes**, below the shared 256 KiB envelope limit because scrcpy reserves 14 bytes. Larger values fail explicitly. Incoming values beyond this limit are rejected, including the upstream truncation boundary. Korean and emoji are decoded strictly as UTF-8. Empty clipboard clearing is not propagated by the existing text-only core contract.

Stop and disconnect cancel the worker. Reconnect starts only when the user still enabled the feature and the new control session's peer has been validated. Every callback is bound to a local generation; old-session sends and non-increasing local sequences are rejected. Recent content and core hashes suppress duplicate/reflected changes. Arbitrary server output is discarded, and clipboard contents are not passed as process arguments or diagnostic messages. Automatic text observation does not add values to history; existing manual history formats are unchanged.

## Permission limits and evidence

The stock server protocol has **no explicit lock/permission-denied result** and ACK is not a success flag. No clipboard response for three seconds therefore reports “lock, permission or empty clipboard needs checking”, not a guessed diagnosis. Recovery resumes when a value is readable. Exact One UI shell authority, background/locked behavior, real ADB disconnection, and Samsung Keyboard retention are **DEVICE_TEST_PENDING**, not a missing production adapter. A pin mismatch is **unsupported**. Runtime process/socket/parser failure is **failed**.

No-device tests run the actual production adapter through a fake executable and real loopback TCP server (`Fixtures/scrcpy/fake-adb.py`). Only the internal expected fixture digest differs; startup, selected serial, push/forward/shell lifecycle, socket I/O, parser, readback, stop and cleanup are production code. Tests never run ADB against a device.

## License and distribution

scrcpy is Copyright (C) 2018 Genymobile and contributors, Apache License 2.0. See `docs/third-party/scrcpy-LICENSE.txt` and upstream source. This client implements the documented wire contract independently; it does not embed Android framework wrappers. If distributing the pinned server, include its license and upstream attribution. The optional packaging input `MTOG_SCRCPY_SERVER` is hash-checked and bundled with its license. Packaging/signing was not executed in this refactor.

While read authority is still unconfirmed, a new user copy on Mac may attempt SET and readback, allowing an initially empty Galaxy clipboard to become readable. The UI continues to show negotiation/permission uncertainty until readback arrives. This does not treat a socket or an ACK as proof of authority.
