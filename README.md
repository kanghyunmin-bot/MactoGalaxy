# MtoG

Mac-to-Galaxy Tab direct-control project.

Current repository state:

- Greenfield scaffold
- Product and contractor spec in [TECHNICAL_SPEC.md](./TECHNICAL_SPEC.md)
- Korean product cut in [PRODUCT_SCOPE_KO.md](./PRODUCT_SCOPE_KO.md)
- Renewed production V1 plan in [V1_RENEWAL_PLAN_KO.md](./V1_RENEWAL_PLAN_KO.md)
- HID-first rebuild notes in [docs/HID_FIRST_REBUILD_KO.md](./docs/HID_FIRST_REBUILD_KO.md)
- Mirror Mode notes in [docs/MIRROR_MODE_KO.md](./docs/MIRROR_MODE_KO.md)
- Applied improvement list in [docs/APPLIED_IMPROVEMENTS_50_KO.md](./docs/APPLIED_IMPROVEMENTS_50_KO.md)
- Shared protocol skeleton in [proto/mtog.proto](./proto/mtog.proto)

Target product shape:

- One universal macOS app for Apple Silicon and supported Intel Macs
- One Android app for Galaxy Tab S11 / S11 Ultra
- USB-C to USB-C primary connection
- 4-digit first-pair UX with persistent trust
- Mac input sharing to Android
- Clipboard sync for text, image, video, and files
- Compact clipboard history on both devices

Planned repository layout:

```text
apps/
  macos-controller/
  android-companion/
proto/
docs/
```

This repository intentionally starts with specification and protocol scaffolding first because transport and Android capability validation are the primary risk items.
