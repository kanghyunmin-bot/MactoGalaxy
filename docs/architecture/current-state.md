# Current state

## Baseline on 2026-09-01

The baseline ran on branch `main` before creating `khm/mtog-harness-refactor`. The tracked worktree was clean. Ignored local paths included Swift and Android build output, signing environment files, `dist/`, and `secrets/`.

| Check | Result |
|---|---|
| Swift | `6.3.3`, debug build passed |
| Java default lookup | Failed because macOS had no registered runtime |
| Existing JDK | Homebrew OpenJDK `17.0.19` found and used through `JAVA_HOME` |
| Gradle | `8.10.2`; `:app:assembleDebug` passed |
| ADB | `37.0.0`; no attached devices |
| scrcpy | `3.3.4`; help exposes clipboard autosync but no standalone clipboard authority |
| Emulator | Command unavailable; no emulator gate registered |

## Baseline legacy implementation

At baseline, the Mac and Android control channel used newline-delimited JSON. Android called `BufferedReader.readLine()` before checking its size. The Mac retried at most eight times with linear delay.

Slice 2 replaced that path on both platforms with the bounded binary-header control parser, canonical JSON payloads, connection-bound replay state, and exponential retry delays.

At baseline, the external-display worker combined private virtual-display calls, image capture, JPEG encoding, sockets, and input in one file. Slice 5 split the worker and replaced Mac capture/send with ScreenCaptureKit, hardware VideoToolbox, and MTGV packets. Android still decodes the legacy JPEG stream until slice 6 replaces its receiver.

`AppModel` and Android `SessionRuntime` combine connection, pairing, clipboard, input, mirror, display, and discovery state. Some ADB and scrcpy commands do not select a serial. Automatic clipboard production authority is blocked rather than using an Android listener or permission workaround.

The Android external-display receiver, serial-selection, and combined-state paths remain until their owning slices replace them. Automatic clipboard has tested pure and fake paths, but production shell authority is `BLOCKED`; manual clipboard and history remain available. `docs/refactor-progress.md` lists them as open debt.
