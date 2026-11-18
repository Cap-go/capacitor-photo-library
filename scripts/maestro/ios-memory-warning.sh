#!/usr/bin/env bash
set -euo pipefail

SIMULATOR_ID="${1:-${CAPGO_MAESTRO_IOS_SIMULATOR_ID:-}}"

if [[ -z "$SIMULATOR_ID" ]]; then
  echo "Simulator id is required for iOS memory warning." >&2
  exit 1
fi

if xcrun simctl help 2>/dev/null | grep -q 'memorywarning'; then
  xcrun simctl memorywarning "$SIMULATOR_ID" >/dev/null 2>&1 || true
else
  xcrun simctl spawn "$SIMULATOR_ID" notifyutil -p com.apple.system.lowmemory >/dev/null 2>&1 || true
fi