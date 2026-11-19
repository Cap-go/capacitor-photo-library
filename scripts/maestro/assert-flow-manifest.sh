#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORKFLOW="${ROOT_DIR}/.github/workflows/test.yml"

manifest="$(grep -E "^  '" "${ROOT_DIR}/scripts/maestro/flows.mjs" | sed -E "s/^  '([^']+)',$/\1/" | sort)"
android_matrix="$(
  awk '
    /^  maestro_e2e_android:$/ { android = 1; next }
    android && /^  maestro_e2e_ios:$/ { exit }
    android && /^          - / { print $2 }
  ' "$WORKFLOW" | sort -u
)"
ios_shards="$(
  awk '
    /^  all\)$/ { capture = 1; next }
    capture && /^\)$/ { exit }
    capture && /^      [a-z0-9-]+$/ { gsub(/^      /, ""); print }
  ' "${ROOT_DIR}/scripts/maestro/run-ios-parallel-shards.sh" | sort -u
)"

if [[ "$manifest" != "$android_matrix" ]]; then
  echo "Android Maestro matrix does not match scripts/maestro/flows.mjs" >&2
  echo "manifest:" >&2
  echo "$manifest" >&2
  echo "matrix:" >&2
  echo "$android_matrix" >&2
  exit 1
fi

if [[ "$manifest" != "$ios_shards" ]]; then
  echo "iOS Maestro shards do not match scripts/maestro/flows.mjs" >&2
  echo "manifest:" >&2
  echo "$manifest" >&2
  echo "shards:" >&2
  echo "$ios_shards" >&2
  exit 1
fi