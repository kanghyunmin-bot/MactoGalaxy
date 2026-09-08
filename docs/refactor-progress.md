# MtoG 0.2.0

## Product scope

Mac extended display on Galaxy Tab with touch; automatic USB text clipboard; manual photo/file sharing. Removed Galaxy mirroring, edge switching, AOA/HID and custom Android IME/accessibility input services. Existing identity, trust and clipboard-history formats are preserved.

## Implementation

- Shared protocol v2, geometry/gesture fixtures and isolated platform transports.
- ScreenCaptureKit → VideoToolbox HEVC/H.264 → bounded USB stream → Android MediaCodec Surface.
- 2560×1600 or 1920×1200, target 60Hz; immersive tablet display.
- Bounded startup retries, capture lifecycle cleanup and Surface session replacement.
- Mac window appears before keychain identity load; actionable capture/accessibility permission status.
- Original file bytes/MIME/name retained, 24MiB binary limit; automatic text max 262130 UTF-8 bytes.
- Generated icon included in Android launcher and Mac bundles; explicit helper/app signing and strict verification.

## Qualification

See [device results](device-runs/2026-09-08/README.md) and [verification matrix](verification-matrix.md). Hardware tests and no-device tests are separate. Mac uses private virtual-display APIs. Development-signed macOS distribution is not Apple notarized. End-to-end binary sharing and broader device/performance qualification remain DEVICE_TEST_PENDING.

## Release preparation

Branch khm/release-0.2.0; app version 0.2.0/build 6. Source cleanup retains runtime code, regression tests, fixtures, licenses and focused documentation. Raw local build output and device identifiers are excluded. GitHub upload and installed release smoke checks are in progress.

Release validation: no-device suite PASS (46 Swift tests, Android tests/build/lint and repository checks). Universal Mac DMG built, strict app signature and DMG checksum verified; both arm64/x86_64 slices present. Release APK signature verified and matches v0.1.3 signer. Both installed apps updated to 0.2.0/build 6 with icons; tablet retains debug signer and data. Installed Mac dashboard and trusted USB connection work; capture/accessibility require user regrant after the release signature changed. Release-package hardware display validation remains pending that grant. GitHub publication follows these checks.

## Publication complete

Published [v0.2.0](https://github.com/kanghyunmin-bot/MactoGalaxy/releases/tag/v0.2.0) as a prerelease with universal DMG, release APK and SHA256SUMS.txt. GitHub asset digests match local files. PR #1 squash-merged to main (06e784a); source tree matches the validated build tree.

After standard macOS permission re-registration, the installed release reports capture and accessibility granted, reconnects to the trusted Galaxy, and starts HEVC 2560×1600. The tablet UI shows only its fullscreen 2960×1848 video Surface with no pending/error overlay. This smoke check does not expand the earlier latency, physical touch or binary-transfer qualification. Tablet uses the corresponding 0.2.0 debug build to preserve existing data; distributable APK uses the existing v0.1.3 release certificate.
