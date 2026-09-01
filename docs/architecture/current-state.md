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

## Legacy implementation

The Mac and Android control channel uses newline-delimited JSON. Android calls `BufferedReader.readLine()` before checking its size. The Mac retries at most eight times with linear delay.

The external-display worker combines private virtual-display calls, image capture, JPEG encoding, sockets, and input in one file. Android decodes those JPEG frames into Bitmap state.

`AppModel` and Android `SessionRuntime` combine connection, pairing, clipboard, input, mirror, display, and discovery state. Some ADB and scrcpy commands do not select a serial. Clipboard automatic observation is not started by either application.

These paths remain until their owning refactor slice replaces them. `docs/refactor-progress.md` lists them as open debt.
