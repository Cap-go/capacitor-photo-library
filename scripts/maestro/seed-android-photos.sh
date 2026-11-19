#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURE_DIR="$ROOT_DIR/example-app/maestro-fixtures"
ANDROID_SERIAL="${ANDROID_SERIAL:-}"

adb_device() {
  if [[ -n "$ANDROID_SERIAL" ]]; then
    adb -s "$ANDROID_SERIAL" "$@"
  else
    adb "$@"
  fi
}

if ! command -v adb >/dev/null 2>&1; then
  echo "adb is required to seed Android photos." >&2
  exit 1
fi

adb_device wait-for-device

push_and_scan() {
  local fixture="$1"
  local name="$2"
  local target
  for target in "/sdcard/DCIM/Camera/$name" "/sdcard/Download/$name" "/data/local/tmp/$name"; do
    if adb_device push "$fixture" "$target" >/dev/null 2>&1; then
      adb_device shell am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d "file://$target" >/dev/null 2>&1 || true
      return 0
    fi
  done
  echo "Unable to seed $name on device." >&2
  return 1
}

adb_device shell mkdir -p /sdcard/DCIM/Camera /sdcard/Download >/dev/null 2>&1 || true

seeded=0
for fixture in "$FIXTURE_DIR"/seed-*.jpg; do
  name="$(basename "$fixture")"
  if push_and_scan "$fixture" "$name"; then
    seeded=$((seeded + 1))
  fi
done

if [[ "$seeded" -lt 1 ]]; then
  echo "No Android photo fixtures were seeded." >&2
  exit 1
fi