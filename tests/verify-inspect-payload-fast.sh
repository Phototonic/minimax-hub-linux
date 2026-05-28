#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/testlib.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

payload_dir="${tmp_dir}/payload"
cache_dir="${tmp_dir}/cache"

mkdir -p \
  "${payload_dir}/resources/gateway/dist" \
  "${payload_dir}/resources/mcp-tools/dist" \
  "${payload_dir}/resources/opencode/config" \
  "${payload_dir}/resources/app-resources"

printf '%s\n' app >"${payload_dir}/resources/app.asar"
printf '%s\n' gateway >"${payload_dir}/resources/gateway/dist/main.js"
printf '%s\n' mcp >"${payload_dir}/resources/mcp-tools/dist/main.js"
printf '%s\n' icon >"${payload_dir}/resources/app-resources/icon.png"

output="$(bash "${PROJECT_ROOT}/scripts/inspect-payload.sh" \
  --payload "${payload_dir}" \
  --cache-dir "${cache_dir}" \
  --fast)"

assert_contains "${output}" "OK file: resources/app.asar" "fast inspect output"
assert_contains "${output}" "Forbidden Windows artifacts: none" "fast inspect output"
assert_contains "${output}" "Discovery reports: skipped (--fast)" "fast inspect output"
require_file "${cache_dir}/inspection-report.txt"

if [[ -e "${cache_dir}/inventory.txt" || -e "${cache_dir}/sha256.txt" ]]; then
  fail "fast inspect must not write inventory or sha256 reports"
fi

echo "Fast payload inspection verification passed"
