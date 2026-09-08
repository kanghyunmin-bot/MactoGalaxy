# Synthetic local batch benchmark — 2026-09-08

Command: `./scripts/benchmark-video.sh` (release SwiftPM executable, no device operations).

Environment: Apple M5, arm64, macOS 26.5.2 (25F84), Darwin 25.5.0, Swift 6.3.3.

Input: twelve synthetic moving-square BGRA frames, 2560x1600. Encoder configured with target 60 fps, hardware required. Frames are generated before timing; encode, then local decode run as a batch. No capture, private virtual display, socket/USB, Android or Surface is involved. These are short batch throughputs, **not sustained realtime display FPS**.

| Codec | Status | Encoded / decoded | Encode batch s | Decode batch s | Total batch s | Batch throughput frames/s | Missing decoded frames |
|---|---|---:|---:|---:|---:|---:|---:|
| H.264 | PASS | 12 / 12 | 0.1660 | 0.1695 | 0.3355 | 35.77 | 0 |
| HEVC | PASS | 12 / 12 | 0.1191 | 0.0698 | 0.1889 | 63.54 | 0 |

Per-frame latency: NOT_MEASURED. USB/device latency and drop rate: NOT_MEASURED. Thermal and ten-minute stability: DEVICE_TEST_PENDING. The harness now reports CAPABILITY_UNAVAILABLE separately when the hardware encoder is unavailable; it must not be counted as an executed codec pass. Unit round trips remain separate 64x48 tests.
