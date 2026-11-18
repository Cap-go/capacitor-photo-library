#!/usr/bin/env bash
set -euo pipefail

APP_ID="${1:-app.capgo.photo.library}"
FLOW_ID="${2:-${CAPGO_MAESTRO_FLOW:-}}"
ANDROID_SERIAL="${ANDROID_SERIAL:-}"

adb_device() {
  if [[ -n "$ANDROID_SERIAL" ]]; then
    adb -s "$ANDROID_SERIAL" "$@"
  else
    adb "$@"
  fi
}

if ! command -v adb >/dev/null 2>&1; then
  echo "adb is required." >&2
  exit 1
fi

if ! adb_device get-state >/dev/null 2>&1; then
  echo "adb device unavailable." >&2
  exit 1
fi

if [[ "$FLOW_ID" == "permission-denied" ]]; then
  adb_device shell pm revoke "$APP_ID" android.permission.READ_MEDIA_IMAGES >/dev/null 2>&1 || true
  adb_device shell pm revoke "$APP_ID" android.permission.READ_MEDIA_VIDEO >/dev/null 2>&1 || true
  adb_device shell pm revoke "$APP_ID" android.permission.READ_EXTERNAL_STORAGE >/dev/null 2>&1 || true
  adb_device shell pm revoke "$APP_ID" android.permission.READ_MEDIA_VISUAL_USER_SELECTED >/dev/null 2>&1 || true
  adb_device shell appops set "$APP_ID" READ_EXTERNAL_STORAGE deny >/dev/null 2>&1 || true
  adb_device shell appops set "$APP_ID" READ_MEDIA_IMAGES deny >/dev/null 2>&1 || true
  adb_device shell appops set "$APP_ID" READ_MEDIA_VIDEO deny >/dev/null 2>&1 || true
  adb_device shell appops set "$APP_ID" READ_MEDIA_VISUAL_USER_SELECTED deny >/dev/null 2>&1 || true
  images_op="$(adb_device shell appops get "$APP_ID" READ_MEDIA_IMAGES 2>/dev/null | tr -d '\r' || true)"
  if [[ "$images_op" != *deny* && "$images_op" != *ignore* ]]; then
    echo "READ_MEDIA_IMAGES app-op not denied (got: ${images_op:-empty})." >&2
    exit 1
  fi
  exit 0
fi

if [[ "$FLOW_ID" == "permission-grant-library" || "$FLOW_ID" == "permission-check" ]]; then
  adb_device shell pm revoke "$APP_ID" android.permission.READ_MEDIA_IMAGES >/dev/null 2>&1 || true
  adb_device shell pm revoke "$APP_ID" android.permission.READ_MEDIA_VIDEO >/dev/null 2>&1 || true
  exit 0
fi

sdk_raw="$(adb_device shell getprop ro.build.version.sdk 2>/dev/null | tr -d '\r' || true)"
if [[ ! "$sdk_raw" =~ ^[0-9]+$ ]]; then
  echo "Unable to read Android SDK version (got: ${sdk_raw:-empty})." >&2
  exit 1
fi
sdk="$sdk_raw"
if [[ "$sdk" -le 32 ]]; then
  adb_device shell pm grant "$APP_ID" android.permission.READ_EXTERNAL_STORAGE >/dev/null 2>&1 || true
fi
adb_device shell pm grant "$APP_ID" android.permission.READ_MEDIA_IMAGES >/dev/null 2>&1 || true
adb_device shell pm grant "$APP_ID" android.permission.READ_MEDIA_VIDEO >/dev/null 2>&1 || true