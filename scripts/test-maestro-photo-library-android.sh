#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/maestro/disable-device-animations.sh
source "$ROOT_DIR/scripts/maestro/disable-device-animations.sh"

FLOW_ID="${CAPGO_MAESTRO_FLOW:-permission-check}"
APK_PATH="$ROOT_DIR/example-app/android/app/build/outputs/apk/debug/app-debug.apk"
RESULTS_DIR="$ROOT_DIR/maestro-results"
MAESTRO_TIMEOUT_SECONDS="${CAPGO_MAESTRO_TIMEOUT_SECONDS:-360}"
MAESTRO_TEST_RETRIES="${CAPGO_MAESTRO_TEST_RETRIES:-2}"
APP_ID="app.capgo.photo.library"
EMULATOR_BOOT_TIMEOUT_SECONDS="${CAPGO_MAESTRO_EMULATOR_BOOT_TIMEOUT_SECONDS:-180}"

cleanup() {
  restore_android_animation_settings
}

trap cleanup EXIT

wait_for_emulator_boot() {
  timeout "${EMULATOR_BOOT_TIMEOUT_SECONDS}s" adb wait-for-device
  local deadline=$((SECONDS + EMULATOR_BOOT_TIMEOUT_SECONDS))
  while (( SECONDS < deadline )); do
    local booted
    booted="$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r' || true)"
    if [[ "$booted" == "1" ]]; then
      return 0
    fi
    sleep 2
  done
  echo "Emulator boot timed out" >&2
  return 1
}

if ! command -v adb >/dev/null 2>&1 || ! command -v maestro >/dev/null 2>&1; then
  echo "adb and maestro are required." >&2
  exit 1
fi

cd "$ROOT_DIR"

wait_for_emulator_boot
export ANDROID_SERIAL="${CAPGO_MAESTRO_ANDROID_DEVICE_ID:-$(adb get-serialno | tr -d '\r')}"
disable_android_emulator_animations

if [[ ! -f "$APK_PATH" ]]; then
  echo "Missing APK at $APK_PATH" >&2
  exit 1
fi

adb uninstall "$APP_ID" >/dev/null 2>&1 || true
adb install -r "$APK_PATH" >/dev/null
bash "$ROOT_DIR/scripts/maestro/seed-android-photos.sh"
bash "$ROOT_DIR/scripts/maestro/prepare-android-permissions.sh" "$APP_ID" "$FLOW_ID"

rm -rf "$RESULTS_DIR"
mkdir -p "$RESULTS_DIR"

attempt=1
while (( attempt <= MAESTRO_TEST_RETRIES )); do
  echo "Maestro Android flow ${FLOW_ID} attempt ${attempt}/${MAESTRO_TEST_RETRIES}"
  if python3 "$ROOT_DIR/scripts/maestro/run-maestro.py" "$MAESTRO_TIMEOUT_SECONDS" "$FLOW_ID" "$ANDROID_SERIAL"; then
    exit 0
  fi
  attempt=$((attempt + 1))
  sleep 5
done

exit 1