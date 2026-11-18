#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_ID="${CAPGO_MAESTRO_APP_ID:-app.capgo.photo.library}"
SIMULATOR_ID="${CAPGO_MAESTRO_IOS_SIMULATOR_ID:-}"

if command -v adb >/dev/null 2>&1 && adb get-state >/dev/null 2>&1; then
  "$ROOT_DIR/scripts/maestro/android-memory-pressure.sh" "$APP_ID"
  exit 0
fi

if [[ -n "$SIMULATOR_ID" ]]; then
  "$ROOT_DIR/scripts/maestro/ios-memory-warning.sh" "$SIMULATOR_ID"
  exit 0
fi

echo "No Android device or iOS simulator id for memory pressure." >&2
exit 1