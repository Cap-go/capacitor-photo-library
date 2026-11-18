#!/usr/bin/env bash
set -euo pipefail

APP_ID="${1:-app.capgo.photo.library}"

if ! command -v adb >/dev/null 2>&1; then
  echo "adb is required for Android memory pressure." >&2
  exit 1
fi

adb shell am send-trim-memory "$APP_ID" RUNNING_CRITICAL >/dev/null 2>&1 || true
adb shell am send-trim-memory "$APP_ID" COMPLETE >/dev/null 2>&1 || true