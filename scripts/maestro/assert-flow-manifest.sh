#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORKFLOW="${ROOT_DIR}/.github/workflows/test.yml"

manifest="$(grep -E "^  '" "${ROOT_DIR}/scripts/maestro/flows.mjs" | sed -E "s/^  '([^']+)',$/\1/" | sort)"
matrix="$(
  awk '
    /^  maestro_e2e_android:$/ { android = 1; next }
    android && /^  maestro_e2e_ios:$/ { exit }
    android && /^          - / { print $2 }
  ' "$WORKFLOW" | sort -u
)"

if [[ "$manifest" != "$matrix" ]]; then
  echo "Maestro flow matrix does not match scripts/maestro/flows.mjs" >&2
  echo "manifest:" >&2
  echo "$manifest" >&2
  echo "matrix:" >&2
  echo "$matrix" >&2
  exit 1
fi