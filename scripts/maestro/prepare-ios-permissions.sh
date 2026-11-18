#!/usr/bin/env bash
set -euo pipefail

APP_ID="${1:-app.capgo.photo.library}"
SIMULATOR_ID="${2:-${CAPGO_MAESTRO_IOS_SIMULATOR_ID:-}}"
FLOW_ID="${3:-}"

if [[ -z "$SIMULATOR_ID" ]]; then
  echo "Simulator id is required." >&2
  exit 1
fi

xcrun simctl privacy "$SIMULATOR_ID" reset photos "$APP_ID" >/dev/null 2>&1 || true

if [[ "$FLOW_ID" == "permission-denied" ]]; then
  xcrun simctl privacy "$SIMULATOR_ID" grant photos "$APP_ID" >/dev/null 2>&1 || true
  xcrun simctl privacy "$SIMULATOR_ID" revoke photos "$APP_ID" >/dev/null 2>&1 || true
fi