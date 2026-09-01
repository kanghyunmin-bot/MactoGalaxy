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

## Video frame

The fixed binary video header will contain packet kind, codec, session ID, sequence, presentation timestamp, dimensions, flags, and payload length. Codec configuration is distinct from access units. Config, frame, and recovery-control payloads each have explicit limits. Video payloads are raw bytes, not JSON or Base64.

The video wire format and canonical fixture bytes are added in slice 4.
