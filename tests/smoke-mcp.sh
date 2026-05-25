#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/testlib.sh"

payload_dir="${1:-${PAYLOAD_DIR}}"
node_bin="${payload_dir}/node/bin/node"
mcp_entry="${payload_dir}/resources/mcp-tools/dist/main.js"

require_payload_not_empty "${payload_dir}"
require_executable "${node_bin}"
require_file "${mcp_entry}"
require_command timeout

if ! "${node_bin}" --version >/dev/null 2>&1; then
  fail "Bundled Node runtime cannot execute: ${node_bin}"
fi

set +e
timeout 3 "${node_bin}" "${mcp_entry}" --help >/tmp/minimax-hub-mcp-smoke.log 2>&1
status="$?"
set -e
if [[ "${status}" -eq 0 || "${status}" -eq 124 ]]; then
  rm -f /tmp/minimax-hub-mcp-smoke.log
  echo "MCP smoke verification passed: ${mcp_entry} starts under packaged Node"
  exit 0
fi
cat /tmp/minimax-hub-mcp-smoke.log >&2 || true
rm -f /tmp/minimax-hub-mcp-smoke.log
fail "MCP tools server failed to start under packaged Node: ${mcp_entry}"

