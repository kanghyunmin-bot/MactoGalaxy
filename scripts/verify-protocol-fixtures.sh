#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
MANIFEST="$ROOT_DIR/Fixtures/protocol-v2/manifest.json"

[ -f "$MANIFEST" ] || { echo "missing protocol fixture manifest" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 is required" >&2; exit 1; }

python3 - "$MANIFEST" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as source:
    manifest = json.load(source)
expected = {
    "protocolVersion": 2,
    "controlPayloadBytes": 36 * 1024 * 1024,
    "videoPayloadBytes": 8 * 1024 * 1024,
    "videoConfigBytes": 256 * 1024,
    "videoControlBytes": 64 * 1024,
    "maximumVideoDimension": 8192,
    "automaticClipboardBytes": 256 * 1024,
}
if manifest["protocolVersion"] != expected["protocolVersion"]:
    raise SystemExit("unexpected protocol version")
for key in (
    "controlPayloadBytes", "videoPayloadBytes", "videoConfigBytes",
    "videoControlBytes", "maximumVideoDimension", "automaticClipboardBytes"
):
    if manifest["limits"][key] != expected[key]:
        raise SystemExit(f"unexpected fixture limit: {key}")

root = __import__("pathlib").Path(sys.argv[1]).parent
for fixture in manifest["fixtures"]:
    semantic_path = root / fixture["semanticPath"]
    frame_path = root / fixture["framePath"]
    semantic = json.loads(semantic_path.read_text(encoding="utf-8"))
    frame = frame_path.read_bytes()
    if fixture["category"] == "control":
        if frame[:8] != b"MTG2\x02\x01\x01\x00":
            raise SystemExit(f"invalid control fixture header: {fixture['name']}")
        declared = int.from_bytes(frame[8:12], "big")
        payload = json.dumps(semantic, ensure_ascii=False, separators=(",", ":"), sort_keys=True).encode()
        if declared != len(payload) or frame[12:] != payload:
            raise SystemExit(f"fixture payload mismatch: {fixture['name']}")
    elif fixture["category"] == "video":
        import uuid
        if len(frame) < 64 or frame[:5] != b"MTGV\x02":
            raise SystemExit(f"invalid video fixture header: {fixture['name']}")
        expected_kind = {"config": 1, "accessUnit": 2}[semantic["kind"]]
        expected_codec = {"h264": 1, "hevc": 2}[semantic["codec"]]
        declared = int.from_bytes(frame[48:52], "big")
        payload = bytes.fromhex(semantic["payloadHex"])
        checks = (
            frame[5] == expected_kind,
            frame[6] == expected_codec,
            frame[7] == semantic["flags"],
            frame[8:24] == uuid.UUID(semantic["sessionID"]).bytes,
            int.from_bytes(frame[24:32], "big") == semantic["sequence"],
            int.from_bytes(frame[32:40], "big") == semantic["presentationTimeUs"],
            int.from_bytes(frame[40:44], "big") == semantic["width"],
            int.from_bytes(frame[44:48], "big") == semantic["height"],
            declared == len(payload),
            frame[53:64] == bytes(11),
            frame[64:] == payload,
        )
        if not all(checks):
            raise SystemExit(f"video fixture mismatch: {fixture['name']}")
    else:
        raise SystemExit(f"unknown fixture category: {fixture['category']}")
PY

echo "protocol fixture manifest: PASS"
