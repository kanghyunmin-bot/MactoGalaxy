#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIBUSB_PREFIX="${LIBUSB_PREFIX:-/opt/homebrew/opt/libusb}"
OUT_DIR="$ROOT_DIR/.build/tools"
SRC="$ROOT_DIR/tools/aoa-hid-probe/aoa_hid_probe.c"
OUT="$OUT_DIR/aoa-hid-probe"

if [[ ! -f "$LIBUSB_PREFIX/include/libusb-1.0/libusb.h" ]]; then
  echo "libusb not found at $LIBUSB_PREFIX" >&2
  echo "Install it with: brew install libusb" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

clang \
  -Wall \
  -Wextra \
  -Werror \
  -std=c17 \
  -I"$LIBUSB_PREFIX/include" \
  "$SRC" \
  -L"$LIBUSB_PREFIX/lib" \
  -lusb-1.0 \
  -Wl,-rpath,"$LIBUSB_PREFIX/lib" \
  -o "$OUT"

echo "$OUT"

