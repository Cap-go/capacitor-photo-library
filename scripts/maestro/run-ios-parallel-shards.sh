#!/usr/bin/env bash
# Run all iOS Maestro flows on one macOS runner using simulator clones in parallel.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=scripts/maestro/disable-device-animations.sh
source "$ROOT_DIR/scripts/maestro/disable-device-animations.sh"

FLOWS=(
  permission-check
  permission-grant-library
  permission-denied
  pick-media-cancel
  kill-relaunch-mid-library
  low-memory-mid-library
)

APP_PATH="${CAPGO_MAESTRO_IOS_APP_PATH:-$ROOT_DIR/maestro-ios-app/App.app}"
MAX_PARALLEL="${CAPGO_MAESTRO_IOS_SHARD_PARALLEL:-3}"
MAESTRO_TIMEOUT_SECONDS="${CAPGO_MAESTRO_TIMEOUT_SECONDS:-360}"
MAESTRO_TEST_RETRIES="${CAPGO_MAESTRO_TEST_RETRIES:-2}"
LIGHT_RETRY_SLEEP_SECONDS="${CAPGO_MAESTRO_LIGHT_RETRY_SLEEP_SECONDS:-2}"
APP_ID="app.capgo.photo.library"

if [[ "$APP_PATH" != /* ]]; then
  APP_PATH="$(cd "$(dirname "$APP_PATH")" && pwd)/$(basename "$APP_PATH")"
fi
if [[ ! -d "$APP_PATH" ]]; then
  echo "Missing iOS app at $APP_PATH" >&2
  exit 1
fi

CLONE_IDS=()
cleanup() {
  local sim_id=""
  for sim_id in "${CLONE_IDS[@]}"; do
    xcrun simctl shutdown "$sim_id" >/dev/null 2>&1 || true
    xcrun simctl delete "$sim_id" >/dev/null 2>&1 || true
  done
}
trap cleanup EXIT

prepare_clone() {
  local flow="$1"
  local base_id="$2"
  local clone_name="Capgo Maestro shard ${flow}-$$"
  xcrun simctl clone "$base_id" "$clone_name"
}

run_shard() {
  local flow="$1"
  local base_id="$2"
  local sim_id
  local log_file="$ROOT_DIR/maestro-results-ios-shard-${flow}.log"

  sim_id="$(prepare_clone "$flow" "$base_id")"
  CLONE_IDS+=("$sim_id")

  xcrun simctl boot "$sim_id" >/dev/null 2>&1 || true
  if ! xcrun simctl list devices booted -j 2>/dev/null | grep -q "$sim_id"; then
    xcrun simctl bootstatus "$sim_id" -b
  fi
  export CAPGO_MAESTRO_SKIP_IOS_ANIMATIONS=1
  xcrun simctl uninstall "$sim_id" "$APP_ID" >/dev/null 2>&1 || true
  xcrun simctl install "$sim_id" "$APP_PATH"
  bash "$ROOT_DIR/scripts/maestro/seed-ios-photos.sh" "$sim_id"
  bash "$ROOT_DIR/scripts/maestro/prepare-ios-permissions.sh" "$APP_ID" "$sim_id" "$flow"

  export CAPGO_MAESTRO_IOS_SIMULATOR_ID="$sim_id"
  export CAPGO_MAESTRO_FLOW="$flow"
  export CAPGO_MAESTRO_IOS_APP_PATH="$APP_PATH"
  export CAPGO_MAESTRO_RESULTS_DIR="$ROOT_DIR/maestro-results-ios-${flow}"
  export CAPGO_MAESTRO_TIMEOUT_SECONDS="$MAESTRO_TIMEOUT_SECONDS"
  export CAPGO_MAESTRO_TEST_RETRIES="$MAESTRO_TEST_RETRIES"
  export CAPGO_MAESTRO_LIGHT_RETRY_SLEEP_SECONDS="$LIGHT_RETRY_SLEEP_SECONDS"
  export CAPGO_MAESTRO_IOS_SKIP_DEVICE_PREP=1

  if "$ROOT_DIR/scripts/test-maestro-photo-library-ios.sh" >"$log_file" 2>&1; then
    echo "Shard ${flow}: success"
    return 0
  fi
  echo "Shard ${flow}: failed (see $log_file)" >&2
  tail -n 40 "$log_file" >&2 || true
  return 1
}

echo "Selecting base iOS simulator..."
BASE_ID="$("$ROOT_DIR/scripts/maestro/select-ios-simulator.sh")"
echo "Base simulator: $BASE_ID"
xcrun simctl shutdown "$BASE_ID" >/dev/null 2>&1 || true

FAILED=0
RUNNING=0
PIDS=()
for flow in "${FLOWS[@]}"; do
  while (( RUNNING >= MAX_PARALLEL )); do
    if ! wait "${PIDS[0]}"; then
      FAILED=1
    fi
    PIDS=("${PIDS[@]:1}")
    RUNNING=$((RUNNING - 1))
  done
  run_shard "$flow" "$BASE_ID" &
  PIDS+=("$!")
  RUNNING=$((RUNNING + 1))
done

for pid in "${PIDS[@]}"; do
  if ! wait "$pid"; then
    FAILED=1
  fi
done

if (( FAILED != 0 )); then
  exit 1
fi