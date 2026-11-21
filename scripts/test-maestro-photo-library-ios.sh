#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/maestro/disable-device-animations.sh
source "$ROOT_DIR/scripts/maestro/disable-device-animations.sh"

# CAPGO_MAESTRO_FLOW selects the matrix shard flow under test.
FLOW_ID="${CAPGO_MAESTRO_FLOW:-permission-check}"
FLOW_PATH="$ROOT_DIR/.maestro/flows/${FLOW_ID}.ios.yaml"
if [[ ! -f "$FLOW_PATH" ]]; then
  FLOW_PATH="$ROOT_DIR/.maestro/flows/${FLOW_ID}.yaml"
fi
RESULTS_DIR="${CAPGO_MAESTRO_RESULTS_DIR:-$ROOT_DIR/maestro-results-ios}"
MAESTRO_TIMEOUT_SECONDS="${CAPGO_MAESTRO_TIMEOUT_SECONDS:-300}"
MAESTRO_TEST_RETRIES="${CAPGO_MAESTRO_TEST_RETRIES:-2}"
LIGHT_RETRY_SLEEP_SECONDS="${CAPGO_MAESTRO_LIGHT_RETRY_SLEEP_SECONDS:-3}"

maestro_junit_reports() {
  case "$FLOW_ID" in
    kill-relaunch-mid-library)
      printf '%s\n' kill-relaunch-mid-library-pre.xml kill-relaunch-mid-library-post.xml
      ;;
    low-memory-mid-library)
      printf '%s\n' low-memory-mid-library-pre.xml low-memory-mid-library-post.xml
      ;;
    *)
      printf '%s\n' junit.xml
      ;;
  esac
}

maestro_reports_passed() {
  local reports=()
  local report=""
  while IFS= read -r report; do
    reports+=("$RESULTS_DIR/$report")
  done < <(maestro_junit_reports)
  python3 "$ROOT_DIR/scripts/maestro/junit-outcome.py" "${reports[@]}"
}
APP_ID="app.capgo.photo.library"
LOCAL_APP_PATH="$ROOT_DIR/.maestro-ios-derived-data/Build/Products/Debug-iphonesimulator/App.app"
STAGED_APP_PATH="$ROOT_DIR/maestro-ios-app/App.app"
STAGED_APP_ROOT="$ROOT_DIR/maestro-ios-app"

resolve_app_path() {
  local candidate="${CAPGO_MAESTRO_IOS_APP_PATH:-}"
  if [[ -z "$candidate" ]]; then
    if [[ -d "$STAGED_APP_PATH" ]]; then
      printf '%s' "$STAGED_APP_PATH"
      return 0
    fi
    if [[ -f "$STAGED_APP_ROOT/Info.plist" ]]; then
      printf '%s' "$STAGED_APP_ROOT"
      return 0
    fi
    if [[ -d "$LOCAL_APP_PATH" ]]; then
      printf '%s' "$LOCAL_APP_PATH"
      return 0
    fi
    printf '%s' "$STAGED_APP_PATH"
    return 0
  fi
  if [[ "$candidate" != /* ]]; then
  candidate="$(cd "$(dirname "$candidate")" 2>/dev/null && pwd)/$(basename "$candidate")" || candidate="$ROOT_DIR/$candidate"
  fi
  if [[ ! -d "$candidate" && -f "$(dirname "$candidate")/Info.plist" ]]; then
    candidate="$(dirname "$candidate")"
  fi
  printf '%s' "$candidate"
}

SIMULATOR_ID="${CAPGO_MAESTRO_IOS_SIMULATOR_ID:-$("$ROOT_DIR/scripts/maestro/select-ios-simulator.sh")}"
APP_PATH="$(resolve_app_path)"

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

if [[ "${CAPGO_MAESTRO_IOS_SKIP_DEVICE_PREP:-}" != "1" ]]; then
  booted="false"
  if xcrun simctl list devices booted -j 2>/dev/null | grep -q "$SIMULATOR_ID"; then
    booted="true"
  fi
  if [[ "$booted" != "true" ]]; then
    xcrun simctl boot "$SIMULATOR_ID" >/dev/null 2>&1 || true
    xcrun simctl bootstatus "$SIMULATOR_ID" -b
  fi
  disable_ios_simulator_animations "$SIMULATOR_ID"
  if ! xcrun simctl install "$SIMULATOR_ID" "$APP_PATH" >/dev/null 2>&1; then
    xcrun simctl uninstall "$SIMULATOR_ID" "$APP_ID" >/dev/null 2>&1 || true
    xcrun simctl install "$SIMULATOR_ID" "$APP_PATH"
  fi
  case "$FLOW_ID" in
    permission-check | permission-denied) ;;
    *)
      bash "$ROOT_DIR/scripts/maestro/seed-ios-photos.sh" "$SIMULATOR_ID"
      ;;
  esac
  bash "$ROOT_DIR/scripts/maestro/prepare-ios-permissions.sh" "$APP_ID" "$SIMULATOR_ID" "$FLOW_ID"
fi

rm -rf "$RESULTS_DIR"
mkdir -p "$RESULTS_DIR"

SUITE_DEADLINE=$((SECONDS + MAESTRO_TIMEOUT_SECONDS))

ios_maestro_logs_allow_retry() {
  local results_dir="$1"
  local pattern='IOSDriverTimeoutException|iOS driver not ready in time|xcTestDriverStatusCheck: \[Failed\]|Failed to connect to /127\.0\.0\.1:7001'
  find "$results_dir/debug" -type f -print0 2>/dev/null \
    | xargs -0 grep -E -q "$pattern" 2>/dev/null
}

attempt=1
while (( attempt <= MAESTRO_TEST_RETRIES )); do
  remaining=$((SUITE_DEADLINE - SECONDS - 10))
  if (( remaining < 60 )); then
    echo "Insufficient suite budget for attempt ${attempt}/${MAESTRO_TEST_RETRIES}" >&2
    break
  fi
  echo "Maestro iOS flow ${FLOW_ID} attempt ${attempt}/${MAESTRO_TEST_RETRIES} (${remaining}s budget)"
  if (( attempt > 1 )); then
    sleep "$LIGHT_RETRY_SLEEP_SECONDS"
  fi
  rm -rf "$RESULTS_DIR/debug"
  rm -f "$RESULTS_DIR/junit.xml"
  set +e
  python3 "$ROOT_DIR/scripts/maestro/run-maestro.py" \
    "$remaining" \
    "$FLOW_ID" \
    "$SIMULATOR_ID" \
    ios \
    "$RESULTS_DIR"
  flow_status=$?
  set -e
  if (( flow_status == 0 )); then
    exit 0
  fi
  for _ in 1 2 3 4 5; do
    if maestro_reports_passed; then
      exit 0
    fi
    sleep 1
  done
  if ! ios_maestro_logs_allow_retry "$RESULTS_DIR"; then
    echo "Maestro flow failed without a retryable iOS driver or boot log marker; not retrying." >&2
    exit 1
  fi
  if (( attempt >= MAESTRO_TEST_RETRIES )); then
    break
  fi
  pkill -TERM -f maestro.cli.AppKt >/dev/null 2>&1 || true
  attempt=$((attempt + 1))
  sleep "$LIGHT_RETRY_SLEEP_SECONDS"
done

exit 1