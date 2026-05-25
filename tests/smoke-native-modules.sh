#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/testlib.sh"

payload_dir="${1:-${PAYLOAD_DIR}}"
node_bin="${payload_dir}/node/bin/node"
gateway_modules="${payload_dir}/resources/gateway/node_modules"

require_payload_not_empty "${payload_dir}"
require_executable "${node_bin}"
require_dir "${gateway_modules}"
assert_no_forbidden_windows_artifacts "${gateway_modules}"

for module_name in better-sqlite3 sharp @node-rs/xxhash; do
  if ! NODE_PATH="${gateway_modules}" "${node_bin}" -e "require('${module_name}');" >/dev/null 2>&1; then
    fail "Bundled native module cannot be required with packaged Node: ${module_name}"
  fi
done

echo "Native module smoke verification passed: ${gateway_modules}"

