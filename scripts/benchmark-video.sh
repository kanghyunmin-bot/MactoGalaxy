#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT_DIR"

printf 'date=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf 'host=%s\n' "$(uname -m)-$(uname -s)-$(uname -r)"
printf 'swift=%s\n' "$(swift --version | head -1)"
printf 'target_resolution=2560x1600\n'
printf 'target_fps=60\n'
printf 'codec=hardware-h264-required,hardware-hevc-if-available\n'
printf 'bitrate=resolution-derived,max_40000000bps\n'
printf 'mode=12-frame-local-batch-not-realtime\n'
printf 'device_latency=NOT_MEASURED\n'
printf 'device_drop_rate=NOT_MEASURED\n'

swift run -c release MtoGVideoBenchmark
