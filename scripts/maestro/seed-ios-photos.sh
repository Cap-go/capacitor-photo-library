#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURE_DIR="$ROOT_DIR/example-app/maestro-fixtures"
SIMULATOR_ID="${1:-${CAPGO_MAESTRO_IOS_SIMULATOR_ID:-}}"

if [[ -z "$SIMULATOR_ID" ]]; then
  echo "Simulator id is required to seed iOS photos." >&2
  exit 1
fi

for fixture in "$FIXTURE_DIR"/seed-*.jpg; do
  xcrun simctl addmedia "$SIMULATOR_ID" "$fixture" >/dev/null
done