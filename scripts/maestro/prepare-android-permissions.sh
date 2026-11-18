#!/usr/bin/env bash
set -euo pipefail

APP_ID="${1:-app.capgo.photo.library}"
FLOW_ID="${2:-${CAPGO_MAESTRO_FLOW:-}}"

if ! command -v adb >/dev/null 2>&1; then
  echo "adb is required." >&2
  exit 1
fi

if [[ "$FLOW_ID" == "permission-denied" ]]; then
  adb shell pm revoke "$APP_ID" android.permission.READ_MEDIA_IMAGES >/dev/null 2>&1 || true
  adb shell pm revoke "$APP_ID" android.permission.READ_MEDIA_VIDEO >/dev/null 2>&1 || true
  adb shell pm revoke "$APP_ID" android.permission.READ_EXTERNAL_STORAGE >/dev/null 2>&1 || true
  adb shell appops set "$APP_ID" READ_EXTERNAL_STORAGE deny >/dev/null 2>&1 || true
  adb shell appops set "$APP_ID" READ_MEDIA_IMAGES deny >/dev/null 2>&1 || true
  adb shell appops set "$APP_ID" READ_MEDIA_VIDEO deny >/dev/null 2>&1 || true
  adb shell appops set "$APP_ID" READ_MEDIA_VISUAL_USER_SELECTED deny >/dev/null 2>&1 || true
  exit 0
fi

if [[ "$FLOW_ID" == "permission-grant-library" || "$FLOW_ID" == "permission-check" ]]; then
  adb shell pm revoke "$APP_ID" android.permission.READ_MEDIA_IMAGES >/dev/null 2>&1 || true
  adb shell pm revoke "$APP_ID" android.permission.READ_MEDIA_VIDEO >/dev/null 2>&1 || true
  exit 0
fi

adb shell pm grant "$APP_ID" android.permission.READ_EXTERNAL_STORAGE >/dev/null 2>&1 || true
adb shell pm grant "$APP_ID" android.permission.READ_MEDIA_IMAGES >/dev/null 2>&1 || true
adb shell pm grant "$APP_ID" android.permission.READ_MEDIA_VIDEO >/dev/null 2>&1 || true