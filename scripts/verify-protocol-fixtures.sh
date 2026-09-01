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
    "automaticClipboardBytes": 256 * 1024,
}
if manifest["protocolVersion"] != expected["protocolVersion"]:
    raise SystemExit("unexpected protocol version")
for key in ("controlPayloadBytes", "videoPayloadBytes", "automaticClipboardBytes"):
    if manifest["limits"][key] != expected[key]:
        raise SystemExit(f"unexpected fixture limit: {key}")

root = __import__("pathlib").Path(sys.argv[1]).parent
for fixture in manifest["fixtures"]:
    semantic_path = root / fixture["semanticPath"]
    frame_path = root / fixture["framePath"]
    semantic = json.loads(semantic_path.read_text(encoding="utf-8"))
    frame = frame_path.read_bytes()
    if frame[:8] != b"MTG2\x02\x01\x01\x00":
        raise SystemExit(f"invalid control fixture header: {fixture['name']}")
    declared = int.from_bytes(frame[8:12], "big")
    payload = json.dumps(semantic, ensure_ascii=False, separators=(",", ":"), sort_keys=True).encode()
    if declared != len(payload) or frame[12:] != payload:
        raise SystemExit(f"fixture payload mismatch: {fixture['name']}")
PY

echo "protocol fixture manifest: PASS"
