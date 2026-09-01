#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT_DIR"

tracked_artifacts=$(git ls-files | grep -E '(^|/)(\.build[^/]*|\.swiftpm|\.gradle|build|dist)/|\.(apk|aab|dmg|xcarchive|class)$' || true)
if [ -n "$tracked_artifacts" ]; then
    echo "tracked generated artifacts:" >&2
    echo "$tracked_artifacts" >&2
    exit 1
fi

echo "repository artifact policy: PASS"
