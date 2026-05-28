#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/testlib.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

source_dir="${tmp_dir}/MiniMax Hub"
cache_dir="${tmp_dir}/cache"

mkdir -p \
  "${source_dir}/resources/gateway/dist" \
  "${source_dir}/resources/gateway/node_modules/native" \
  "${source_dir}/resources/mcp-tools/dist" \
  "${source_dir}/resources/opencode/config" \
  "${source_dir}/resources/app-resources" \
  "${source_dir}/resources/gateway/node_modules/win32-helper"

printf '%s\n' app >"${source_dir}/resources/app.asar"
printf '%s\n' gateway >"${source_dir}/resources/gateway/dist/main.js"
printf '%s\n' module >"${source_dir}/resources/gateway/node_modules/native/package.json"
printf '%s\n' mcp >"${source_dir}/resources/mcp-tools/dist/main.js"
printf '%s\n' config >"${source_dir}/resources/opencode/config/config.json"
printf '%s\n' icon >"${source_dir}/resources/app-resources/icon.png"
printf '%s\n' bad >"${source_dir}/resources/gateway/node_modules/bad.dll"
printf '%s\n' bad >"${source_dir}/resources/gateway/node_modules/win32-helper/package.json"

output="$(bash "${PROJECT_ROOT}/scripts/extract-windows-payload.sh" \
  --source "${source_dir}" \
  --cache-dir "${cache_dir}" \
  --no-reports 2>&1)"

assert_contains "${output}" "Skipping extraction inventory/checksum/discovery reports" "fast extraction output"
require_file "${cache_dir}/payload/resources/app.asar"
require_file "${cache_dir}/payload/resources/gateway/dist/main.js"
require_file "${cache_dir}/payload/resources/gateway/node_modules/native/package.json"
assert_no_forbidden_windows_artifacts "${cache_dir}/payload"

if [[ -e "${cache_dir}/inventory.txt" || -e "${cache_dir}/sha256.txt" || -e "${cache_dir}/report.txt" ]]; then
  fail "fast extraction must not write inventory, sha256, or discovery reports"
fi

echo "Fast Windows payload extraction verification passed"
