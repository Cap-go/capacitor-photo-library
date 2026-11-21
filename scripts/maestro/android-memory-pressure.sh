#!/usr/bin/env bash
set -euo pipefail

APP_ID="${1:-app.capgo.photo.library}"
ANDROID_SERIAL="${ANDROID_SERIAL:-}"

adb_device() {
  if [[ -n "$ANDROID_SERIAL" ]]; then
    adb -s "$ANDROID_SERIAL" "$@"
  else
    adb "$@"
  fi
}

if ! command -v adb >/dev/null 2>&1; then
  echo "adb is required for Android memory pressure." >&2
  exit 1
fi

if ! adb_device get-state >/dev/null 2>&1; then
  echo "adb device unavailable for memory pressure." >&2
  exit 1
fi

ok=0
if adb_device shell am send-trim-memory "$APP_ID" RUNNING_CRITICAL >/dev/null 2>&1; then
  ok=1
fi
if adb_device shell am send-trim-memory "$APP_ID" COMPLETE >/dev/null 2>&1; then
  ok=1
fi

if [[ "$ok" -ne 1 ]]; then
  echo "Android memory pressure commands did not succeed." >&2
  exit 1
fi