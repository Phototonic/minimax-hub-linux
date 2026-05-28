#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/testlib.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

source_payload="${tmp_dir}/source-payload"
payload_dir="${tmp_dir}/payload"

mkdir -p \
  "${source_payload}/resources/gateway/node_modules/better-sqlite3" \
  "${source_payload}/resources/gateway/dist" \
  "${source_payload}/resources/mcp-tools/dist" \
  "${source_payload}/resources/opencode/config" \
  "${payload_dir}/electron-parent-marker"

printf '%s\n' '{"dependencies":{"better-sqlite3":"12.9.0"}}' >"${source_payload}/resources/gateway/package.json"
printf '%s\n' 'module' >"${source_payload}/resources/gateway/node_modules/better-sqlite3/package.json"
printf '%s\n' 'gateway' >"${source_payload}/resources/gateway/dist/main.js"

bash "${PROJECT_ROOT}/scripts/stage-native-rebuild-payload.sh" \
  --source-payload "${source_payload}" \
  --payload-dir "${payload_dir}" >/dev/null

require_file "${payload_dir}/resources/gateway/package.json"
require_file "${payload_dir}/resources/gateway/node_modules/better-sqlite3/package.json"
require_file "${payload_dir}/resources/gateway/dist/main.js"

if [[ -e "${payload_dir}/resources/mcp-tools" ]]; then
  fail "native rebuild staging must not copy unrelated mcp-tools payload"
fi

echo "Native rebuild payload staging verification passed"
