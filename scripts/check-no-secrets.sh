#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT_DIR"

tracked_secret_paths=$(git ls-files | grep -E '(^|/)(secrets?|credentials?)/|(^|/)\.env($|\.)|\.(jks|keystore|p12|mobileprovision)$' || true)
if [ -n "$tracked_secret_paths" ]; then
    echo "tracked secret or signing paths:" >&2
    echo "$tracked_secret_paths" >&2
    exit 1
fi

echo "tracked secret path check: PASS"
