# Protocol v2

Protocol v2 separates bounded control and video channels. Both peers reject other versions instead of falling back to v1.

## Shared limits

| Item | Limit |
|---|---:|
| Control JSON payload | 36 MiB |
| Video payload | 8 MiB |
| Automatic text or URL clipboard content | 256 KiB |

`Fixtures/protocol-v2/manifest.json` is the shared machine-readable source checked by Swift and Kotlin walking tests.

## Planned control frame

The fixed header contains magic, version, channel or message type, flags, and payload length. The payload is canonical UTF-8 JSON. Incremental parsers reject invalid magic, version, type, UTF-8, JSON, truncation, and lengths above the limit before allocating the body.

## Planned video frame

The fixed binary header contains packet kind, codec, session ID, sequence, presentation timestamp, dimensions, flags, and payload length. Codec configuration is distinct from access units. Config, frame, and recovery-control payloads each have explicit limits. Video payloads are raw bytes, not JSON or Base64.

The remaining wire format and canonical fixture bytes are added with slices 2 and 4.
