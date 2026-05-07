# MtoG

MtoG lets a Mac control, mirror, and share clipboard content with a Galaxy Tab over USB-C.

## Install

Download both files from the latest GitHub release.

<table>
  <tr>
    <td align="center" width="50%">
      <h1>💻</h1>
      <h2>Mac</h2>
      <p><strong>MtoG-macos.dmg</strong></p>
      <p>Install this on your MacBook.</p>
      <p>
        <a href="https://github.com/kanghyunmin-bot/MactoGalaxy/releases/latest/download/MtoG-macos.dmg">
          <strong>Download DMG</strong>
        </a>
      </p>
    </td>
    <td align="center" width="50%">
      <h1>📱</h1>
      <h2>Galaxy Tab</h2>
      <p><strong>MtoG-android-debug.apk</strong></p>
      <p>Install this on your Galaxy Tab.</p>
      <p>
        <a href="https://github.com/kanghyunmin-bot/MactoGalaxy/releases/latest/download/MtoG-android-debug.apk">
          <strong>Download APK</strong>
        </a>
      </p>
    </td>
  </tr>
</table>

## Quick Start

1. Install `MtoG-macos.dmg` on the Mac.
2. Install `MtoG-android-debug.apk` on the Galaxy Tab.
3. Connect the Mac and Galaxy Tab with a USB-C to USB-C cable.
4. Enable Android USB debugging when prompted.
5. Open `MtoG` on both devices.
6. On macOS, allow the required permissions:
   - Accessibility
   - Screen Recording
   - Input Monitoring, if requested
7. In the Mac app, use `Connect USB`, then start the mode you need:
   - `Start USB Mirror` for stable Galaxy screen control in a Mac window.
   - `Start External Display` to use the Galaxy Tab as an experimental Mac second screen.

## Controls

### Mirror Mode

Use this when you want the Galaxy Tab screen shown on the Mac and controlled from the Mac.

- Move the Mac pointer inside the mirror window to control the Galaxy Tab.
- Move the pointer outside the mirror window to return to macOS.
- `Esc` or `Command + Q` exits control mode.

### External Display Mode

Use this when you want the Galaxy Tab to act like a separate Mac display.

- Touch once on the Galaxy Tab: move the Mac cursor.
- Tap twice: left click.
- Press for 1 second: right click.
- Drag: drag on the Mac external display.
- Two-finger move: scroll.

This mode is experimental. It uses a virtual macOS display and streams frames to Android over ADB.

## Clipboard

Clipboard sync is currently manual.

- `Push Mac Clipboard`: send the current Mac clipboard to the Galaxy Tab.
- `Pull Galaxy Clipboard`: bring the current Galaxy Tab clipboard to the Mac.
- `Show History`: view compact clipboard history.

Text is the most reliable. Image and file clipboard behavior depends on Android clipboard and content-provider restrictions.

## Requirements

### Mac

- Apple Silicon Mac or Intel Mac
- macOS with Accessibility and Screen Recording permissions available
- Android platform-tools / `adb`

### Galaxy Tab

- Galaxy Tab S11 / S11 Ultra target device
- Android with USB debugging enabled
- MtoG APK installed

## Important Notes

- This is not Sidecar.
- This is not Apple Universal Control.
- This is not a production-signed release yet.
- USB-C is the physical cable. Current MVP communication uses ADB over USB.
- External Display Mode is experimental and may need restart if the virtual display gets stuck.
- If clicks do not work, re-enable `MtoG` in macOS `System Settings > Privacy & Security > Accessibility`.

## Build From Source

### macOS app

```bash
swift build
./scripts/package-macos-dmg.sh
```

Output:

```text
dist/MtoG.app
dist/MtoG-macos.dmg
```

### Android app

```bash
cd apps/android-companion
./gradlew :app:assembleDebug
```

Output:

```text
apps/android-companion/app/build/outputs/apk/debug/app-debug.apk
```

## Source Layout

```text
.
├── Package.swift
├── Sources/
│   ├── MtoGMac/                    # macOS app
│   └── MtoGExternalDisplayWorker/  # external-display streaming helper
├── apps/
│   └── android-companion/          # Galaxy Tab APK project
├── scripts/
│   ├── package-macos-dmg.sh
│   └── build-aoa-hid-probe.sh
└── tools/
    └── aoa-hid-probe/              # optional Android Open Accessory HID helper
```

The repository intentionally keeps only the files needed to build and package the macOS app, Android APK, and optional HID helper. Design drafts, generated build products, local IDE settings, APKs, DMGs, and temporary previews are excluded from git.
