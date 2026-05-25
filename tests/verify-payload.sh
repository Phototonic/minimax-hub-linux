#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/testlib.sh"

payload_dir="${1:-${PAYLOAD_DIR}}"

require_payload_not_empty "${payload_dir}"
require_file "${payload_dir}/resources/app.asar"
require_file "${payload_dir}/resources/gateway/dist/main.js"
require_file "${payload_dir}/resources/mcp-tools/dist/main.js"
require_dir "${payload_dir}/resources/opencode/config"
require_executable "${payload_dir}/electron"
require_executable "${payload_dir}/node/bin/node"
require_executable "${payload_dir}/resources/opencode/opencode"
require_executable "${payload_dir}/resources/ffmpeg/ffmpeg"
require_executable "${payload_dir}/resources/ffmpeg/ffprobe"
require_file "${PROJECT_ROOT}/linux-build/usr/share/applications/minimax-hub.desktop"
require_executable "${PROJECT_ROOT}/linux-build/usr/bin/minimax-hub"

assert_no_forbidden_windows_artifacts "${payload_dir}"
assert_no_crlf "${PROJECT_ROOT}/linux-build/usr/bin/minimax-hub"
assert_no_crlf "${PROJECT_ROOT}/linux-build/usr/share/applications/minimax-hub.desktop"
assert_no_crlf "${PROJECT_ROOT}/linux-build/DEBIAN/control"
assert_no_crlf "${PROJECT_ROOT}/rpm/minimax-hub.spec"
if [[ -d "${payload_dir}/resources" ]]; then
  assert_no_crlf_in_tree "${payload_dir}/resources" -name '*.sh' -o -name '*.desktop' -o -name '*.json' -o -name '*.js'
fi

validate_desktop_file "${PROJECT_ROOT}/linux-build/usr/share/applications/minimax-hub.desktop"

echo "Payload verification passed: ${payload_dir}"

