#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURE_DIR="$ROOT_DIR/example-app/maestro-fixtures"
DEVICE_DIR="/sdcard/DCIM/Camera"

if ! command -v adb >/dev/null 2>&1; then
  echo "adb is required to seed Android photos." >&2
  exit 1
fi

adb wait-for-device
adb shell mkdir -p "$DEVICE_DIR" >/dev/null 2>&1 || true

for fixture in "$FIXTURE_DIR"/seed-*.jpg; do
  name="$(basename "$fixture")"
  adb push "$fixture" "$DEVICE_DIR/$name" >/dev/null
  adb shell am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d "file://$DEVICE_DIR/$name" >/dev/null || true
done