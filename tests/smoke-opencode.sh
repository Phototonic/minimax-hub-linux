#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/testlib.sh"

payload_dir="${1:-${PAYLOAD_DIR}}"
opencode_bin="${payload_dir}/resources/opencode/opencode"
opencode_config="${payload_dir}/resources/opencode/config"

require_payload_not_empty "${payload_dir}"
require_executable "${opencode_bin}"
require_dir "${opencode_config}"

if ! "${opencode_bin}" --version >/dev/null 2>&1; then
  fail "Bundled OpenCode binary cannot execute --version: ${opencode_bin}"
fi

echo "OpenCode smoke verification passed: ${opencode_bin}"

