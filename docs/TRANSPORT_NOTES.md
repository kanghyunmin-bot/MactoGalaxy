# Transport Notes

## Important distinction

- `Thunderbolt 4` and `USB-C` describe the physical cable and bus capabilities.
- They do not automatically create a UDP socket path between a Mac and an Android tablet.
- For this project, transport adapters must be treated separately:
  - `USB direct adapter`
  - `UDP/IP adapter`

## What is realistic

### USB direct

Use one of:

- `ADB-over-USB` for MVP
- `AOA` or equivalent direct USB accessory transport for production, if validated

This is the primary path for a cable-first product.

### UDP

Use UDP only when there is an actual IP path, for example:

- Wi-Fi fallback
- a future validated USB/IP path that both platforms expose

UDP is not the first implementation target for direct Mac-to-Galaxy-Tab cable transport.

## Throughput guidance

- Do not send clipboard media as one giant datagram.
- Use chunking, bounded buffers, and backpressure.
- Keep pointer and scroll messages small and coalesced.
- Keep clipboard/resource transfer separate from latency-sensitive control messages.

## Recommended implementation order

1. USB direct MVP
2. Secure session and control protocol
3. Clipboard transfer with chunking
4. UDP adapter as a secondary transport
