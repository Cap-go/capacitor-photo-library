#!/usr/bin/env bash
# Run a CI iOS Maestro shard (several flows) on one booted simulator.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=scripts/maestro/disable-device-animations.sh
source "$ROOT_DIR/scripts/maestro/disable-device-animations.sh"

SHARD="${CAPGO_MAESTRO_IOS_SHARD:-all}"
case "$SHARD" in
  a)
    FLOWS=(permission-check permission-denied)
    ;;
  b)
    FLOWS=(permission-grant-library pick-media-cancel)
    ;;
  c)
    FLOWS=(kill-relaunch-mid-library low-memory-mid-library)
    ;;
  all)
    FLOWS=(
      permission-check
      permission-denied
      permission-grant-library
      pick-media-cancel
      kill-relaunch-mid-library
      low-memory-mid-library
    )
    ;;
  *)
    echo "Unknown iOS shard ${SHARD}" >&2
    exit 1
    ;;
esac

APP_ID="app.capgo.photo.library"
APP_PATH="${CAPGO_MAESTRO_IOS_APP_PATH:-$ROOT_DIR/maestro-ios-app/App.app}"
MAESTRO_TEST_RETRIES="${CAPGO_MAESTRO_TEST_RETRIES:-2}"
LIGHT_RETRY_SLEEP_SECONDS="${CAPGO_MAESTRO_LIGHT_RETRY_SLEEP_SECONDS:-2}"
SHARD_BUDGET_SECONDS="${CAPGO_MAESTRO_IOS_SHARD_BUDGET_SECONDS:-540}"

if [[ "$APP_PATH" != /* ]]; then
  APP_PATH="$(cd "$(dirname "$APP_PATH")" && pwd)/$(basename "$APP_PATH")"
fi
if [[ ! -d "$APP_PATH" ]]; then
  echo "Missing iOS app at $APP_PATH" >&2
  exit 1
fi

echo "Selecting iOS simulator for shard ${SHARD}..."
SIMULATOR_ID="$("$ROOT_DIR/scripts/maestro/select-ios-simulator.sh")"
echo "Simulator: ${SIMULATOR_ID}"

booted="false"
if xcrun simctl list devices booted -j 2>/dev/null | grep -q "$SIMULATOR_ID"; then
  booted="true"
fi
if [[ "$booted" != "true" ]]; then
  xcrun simctl boot "$SIMULATOR_ID" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$SIMULATOR_ID" -b
fi

disable_ios_simulator_animations "$SIMULATOR_ID"
xcrun simctl uninstall "$SIMULATOR_ID" "$APP_ID" >/dev/null 2>&1 || true
xcrun simctl install "$SIMULATOR_ID" "$APP_PATH"
bash "$ROOT_DIR/scripts/maestro/seed-ios-photos.sh" "$SIMULATOR_ID"

export CAPGO_MAESTRO_IOS_SIMULATOR_ID="$SIMULATOR_ID"
export CAPGO_MAESTRO_IOS_APP_PATH="$APP_PATH"
export CAPGO_MAESTRO_TEST_RETRIES="$MAESTRO_TEST_RETRIES"
export CAPGO_MAESTRO_LIGHT_RETRY_SLEEP_SECONDS="$LIGHT_RETRY_SLEEP_SECONDS"
export CAPGO_MAESTRO_IOS_SKIP_DEVICE_PREP=1

SHARD_START=$SECONDS
FAILED=0
for flow in "${FLOWS[@]}"; do
  elapsed=$((SECONDS - SHARD_START))
  remaining=$((SHARD_BUDGET_SECONDS - elapsed - 15))
  if (( remaining < 90 )); then
    echo "Shard ${SHARD} out of time before flow ${flow} (${elapsed}s elapsed, ${remaining}s left)." >&2
    FAILED=1
    break
  fi
  export CAPGO_MAESTRO_TIMEOUT_SECONDS="$remaining"
  echo "Running iOS Maestro flow ${flow} (shard ${SHARD}, ${remaining}s budget)..."
  xcrun simctl terminate "$SIMULATOR_ID" "$APP_ID" >/dev/null 2>&1 || true
  bash "$ROOT_DIR/scripts/maestro/prepare-ios-permissions.sh" "$APP_ID" "$SIMULATOR_ID" "$flow"
  export CAPGO_MAESTRO_FLOW="$flow"
  export CAPGO_MAESTRO_RESULTS_DIR="$ROOT_DIR/maestro-results-ios-${flow}"
  if ! "$ROOT_DIR/scripts/test-maestro-photo-library-ios.sh"; then
    echo "Flow ${flow} failed." >&2
    FAILED=1
  fi
done

if (( FAILED != 0 )); then
  exit 1
fi