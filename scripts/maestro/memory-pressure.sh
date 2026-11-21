#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PLATFORM="${1:-}"
DEVICE="${2:-}"
APP_ID="${CAPGO_MAESTRO_APP_ID:-app.capgo.photo.library}"

if [[ "$PLATFORM" == "android" ]]; then
  if [[ -z "$DEVICE" ]]; then
    echo "Android serial is required for memory pressure." >&2
    exit 1
  fi
  export ANDROID_SERIAL="$DEVICE"
  exec "$ROOT_DIR/scripts/maestro/android-memory-pressure.sh" "$APP_ID"
fi

if [[ "$PLATFORM" == "ios" ]]; then
  if [[ -z "$DEVICE" ]]; then
    echo "iOS simulator id is required for memory pressure." >&2
    exit 1
  fi
  exec "$ROOT_DIR/scripts/maestro/ios-memory-warning.sh" "$DEVICE"
fi

# Backward-compatible fallback when called without explicit platform.
SIMULATOR_ID="${CAPGO_MAESTRO_IOS_SIMULATOR_ID:-}"
if [[ -n "$SIMULATOR_ID" ]]; then
  exec "$ROOT_DIR/scripts/maestro/ios-memory-warning.sh" "$SIMULATOR_ID"
fi

if command -v adb >/dev/null 2>&1 && adb get-state >/dev/null 2>&1; then
  exec "$ROOT_DIR/scripts/maestro/android-memory-pressure.sh" "$APP_ID"
fi

echo "No Android device or iOS simulator id for memory pressure." >&2
exit 1