# Protocol v2

Protocol v2 separates bounded control and video channels. Both peers reject other versions instead of falling back to v1.

## Shared limits

| Item | Limit |
|---|---:|
| Control JSON payload | 36 MiB |
| Video payload | 8 MiB |
| Automatic text or URL clipboard content | 256 KiB |

`Fixtures/protocol-v2/manifest.json` is the shared machine-readable source checked by Swift and Kotlin tests.

## Control frame

The control header is 12 bytes. Integers use network byte order.

| Offset | Bytes | Field | Value |
|---:|---:|---|---|
| 0 | 4 | Magic | ASCII `MTG2` |
| 4 | 1 | Version | `2` |
| 5 | 1 | Channel | `1`, control |
| 6 | 1 | Frame type | `1`, session envelope |
| 7 | 1 | Flags | Bit field, currently zero |
| 8 | 4 | Payload length | Unsigned byte count, at most 36 MiB |

The payload is canonical UTF-8 JSON. Object keys are sorted, insignificant whitespace is absent, and strings use JSON escaping. The session envelope preserves the existing message names and string payload map. Sequence numbers start at one, timestamps are ISO 8601, and required identity and session fields cannot be empty.

Each connection starts with `hello`. The Mac supplies a random session token and client nonce. Android echoes both values and adds a fresh server nonce in `helloAck`. The Mac must return both nonces in `helloConfirm`, and Android completes the handshake with `helloConfirmed`. Feature messages are rejected before this exchange finishes. `helloConfirmed` echoes the exact random `helloConfirm` message ID. Every later envelope carries the token and both nonces. Each receiver binds session ID, token, both nonces, sequence, and its local socket generation. Tokens and nonces reject recorded stale traffic; they do not encrypt control, video, or input traffic. Clipboard messages require the completed handshake and persisted peer trust on both peers.

Incremental parsers reject invalid magic, version, channel, type, UTF-8, JSON, timestamps, zero sequence numbers, truncation, and lengths above the limit. They inspect the fixed header before allocating payload storage. A version mismatch ends the connection with an explicit status.

`Fixtures/protocol-v2/control/hello.json` and `hello.frame` are the canonical semantic and byte vectors. Swift and Kotlin both encode and decode the same frame.

## Video packet

The video header is 64 bytes. Integers use network byte order.

| Offset | Bytes | Field |
|---:|---:|---|
| 0 | 4 | ASCII `MTGV` |
| 4 | 1 | Version `2` |
| 5 | 1 | Kind: config `1`, access unit `2`, control `3` |
| 6 | 1 | Codec: H.264 `1`, HEVC `2` |
| 7 | 1 | Flags; bit 0 marks a keyframe |
| 8 | 16 | Session UUID |
| 24 | 8 | Sequence |
| 32 | 8 | Presentation timestamp in microseconds |
| 40 | 4 | Width |
| 44 | 4 | Height |
| 48 | 4 | Payload length |
| 52 | 1 | Control code |
| 53 | 11 | Reserved zero bytes |

Access-unit payloads are limited to 8 MiB, codec configuration to 256 KiB, and control payloads to 64 KiB. Dimensions are positive and at most 8192. Payloads are raw Annex-B NAL bytes, not JSON or Base64. Config packets contain codec parameter sets and are distinct from access units. Control codes include keyframe request, stream start, stream stop, and capabilities.

The receiver requires config before decoding and a keyframe after config, reconnect, or any undecoded queue eviction. Recovery clears only when a newer keyframe from the affected session is decoded. It rejects stale sessions and non-increasing sequences. HEVC can fall back to H.264 once. The latest-frame queue has an explicit capacity and marks keyframe recovery after any undecoded frame eviction.

`Fixtures/protocol-v2/video/` contains shared H.264 config, keyframe, and delta semantic and binary vectors. Swift and Kotlin encode and decode the same packet bytes.
