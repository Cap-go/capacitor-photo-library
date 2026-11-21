#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${ANDROID_HOME:-}" ]]; then
  echo "ANDROID_HOME is not set; skipping Android SDK temp cleanup." >&2
  exit 0
fi

temp_dir="${ANDROID_HOME}/.temp"
if rm -rf "$temp_dir" 2>/dev/null; then
  echo "Cleared Android SDK temp cache under ${temp_dir}."
else
  echo "Warning: could not remove ${temp_dir}; continuing with existing SDK temp cache." >&2
fi