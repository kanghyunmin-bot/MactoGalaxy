# Device validation

[Latest measured results](device-runs/2026-09-08/README.md).

Before each new hardware qualification, identify the authorized tablet, OS, USB speed and installed build; preserve pairing, history and keyboard configuration.

Remaining DEVICE_TEST_PENDING:

- Repeat physical unplug/replug and sleep/wake with active video and clipboard.
- Exercise lock/background copy, simultaneous changes and permission denial/regrant.
- Verify photos and files in both directions by matching bytes and filenames.
- Measure scroll, edge coordinates, rotation and pen behavior.
- Measure sustained high-resolution FPS, presentation latency, drops and thermal behavior.
- Test additional Galaxy models and Mac architectures.

Use generated test content and restore clipboard contents after testing. No-device tests are not proof of hardware performance. Do not treat host encoder counters as tablet presentation timestamps.
