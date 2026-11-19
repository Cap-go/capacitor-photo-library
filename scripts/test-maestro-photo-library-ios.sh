#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

FLOW_ID="${CAPGO_MAESTRO_FLOW:-permission-check}"
FLOW_PATH="$ROOT_DIR/.maestro/flows/${FLOW_ID}.ios.yaml"
if [[ ! -f "$FLOW_PATH" ]]; then
  FLOW_PATH="$ROOT_DIR/.maestro/flows/${FLOW_ID}.yaml"
fi
RESULTS_DIR="${CAPGO_MAESTRO_RESULTS_DIR:-$ROOT_DIR/maestro-results-ios}"
MAESTRO_TIMEOUT_SECONDS="${CAPGO_MAESTRO_TIMEOUT_SECONDS:-300}"
MAESTRO_TEST_RETRIES="${CAPGO_MAESTRO_TEST_RETRIES:-2}"
LIGHT_RETRY_SLEEP_SECONDS="${CAPGO_MAESTRO_LIGHT_RETRY_SLEEP_SECONDS:-3}"
APP_ID="app.capgo.photo.library"
SIMULATOR_ID="${CAPGO_MAESTRO_IOS_SIMULATOR_ID:-$("$ROOT_DIR/scripts/maestro/select-ios-simulator.sh")}"
APP_PATH="${CAPGO_MAESTRO_IOS_APP_PATH:-$ROOT_DIR/maestro-ios-app/App.app}"

if ! command -v maestro >/dev/null 2>&1; then
  echo "maestro is required." >&2
  exit 1
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "Missing iOS app at $APP_PATH" >&2
  exit 1
fi

if [[ ! -f "$FLOW_PATH" ]]; then
  case "$FLOW_ID" in
    low-memory-mid-library|kill-relaunch-mid-library|pick-media-cancel)
      ;;
    *)
      echo "Missing flow at $FLOW_PATH" >&2
      exit 1
      ;;
  esac
fi

cd "$ROOT_DIR"
export CAPGO_MAESTRO_IOS_SIMULATOR_ID="$SIMULATOR_ID"
export CAPGO_MAESTRO_APP_ID="$APP_ID"

if [[ -z "${CAPGO_MAESTRO_IOS_SIMULATOR_ID:-}" ]]; then
  xcrun simctl boot "$SIMULATOR_ID" >/dev/null 2>&1 || true
fi
xcrun simctl bootstatus "$SIMULATOR_ID" -b
xcrun simctl uninstall "$SIMULATOR_ID" "$APP_ID" >/dev/null 2>&1 || true
xcrun simctl install "$SIMULATOR_ID" "$APP_PATH"
bash "$ROOT_DIR/scripts/maestro/seed-ios-photos.sh" "$SIMULATOR_ID"
bash "$ROOT_DIR/scripts/maestro/prepare-ios-permissions.sh" "$APP_ID" "$SIMULATOR_ID" "$FLOW_ID"

rm -rf "$RESULTS_DIR"
mkdir -p "$RESULTS_DIR"

attempt=1
while (( attempt <= MAESTRO_TEST_RETRIES )); do
  echo "Maestro iOS flow ${FLOW_ID} attempt ${attempt}/${MAESTRO_TEST_RETRIES}"
  if (( attempt > 1 )); then
    xcrun simctl uninstall "$SIMULATOR_ID" "$APP_ID" >/dev/null 2>&1 || true
    xcrun simctl install "$SIMULATOR_ID" "$APP_PATH"
    bash "$ROOT_DIR/scripts/maestro/prepare-ios-permissions.sh" "$APP_ID" "$SIMULATOR_ID" "$FLOW_ID"
    sleep "$LIGHT_RETRY_SLEEP_SECONDS"
  fi
  if python3 "$ROOT_DIR/scripts/maestro/run-maestro.py" \
    "$MAESTRO_TIMEOUT_SECONDS" \
    "$FLOW_ID" \
    "$SIMULATOR_ID" \
    ios \
    "$RESULTS_DIR"; then
    exit 0
  fi
  if find "$RESULTS_DIR/debug" -type f -print0 2>/dev/null | xargs -0 grep -q 'IOSDriverTimeoutException' 2>/dev/null; then
    xcrun simctl shutdown "$SIMULATOR_ID" >/dev/null 2>&1 || true
    xcrun simctl boot "$SIMULATOR_ID" >/dev/null 2>&1 || true
    xcrun simctl bootstatus "$SIMULATOR_ID" -b
  fi
  attempt=$((attempt + 1))
  sleep "$LIGHT_RETRY_SLEEP_SECONDS"
done

exit 1