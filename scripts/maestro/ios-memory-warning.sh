#!/usr/bin/env bash
set -euo pipefail

SIMULATOR_ID="${1:-${CAPGO_MAESTRO_IOS_SIMULATOR_ID:-}}"

if [[ -z "$SIMULATOR_ID" ]]; then
  echo "Simulator id is required for iOS memory warning." >&2
  exit 1
fi

ok=0
if xcrun simctl help 2>/dev/null | grep -q 'memorywarning'; then
  if xcrun simctl memorywarning "$SIMULATOR_ID" >/dev/null 2>&1; then
    ok=1
  fi
fi
if [[ "$ok" -ne 1 ]]; then
  if xcrun simctl spawn "$SIMULATOR_ID" notifyutil -p com.apple.system.lowmemory >/dev/null 2>&1; then
    ok=1
  fi
fi

if [[ "$ok" -ne 1 ]]; then
  echo "iOS memory warning did not succeed." >&2
  exit 1
fi