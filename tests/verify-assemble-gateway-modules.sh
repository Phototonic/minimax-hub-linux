#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/testlib.sh"

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "${tmp_dir}"
}
trap cleanup EXIT

source_payload="${tmp_dir}/source"
payload_dir="${tmp_dir}/payload"
runtime_dir="${tmp_dir}/runtime"
assembly_dir="${tmp_dir}/assembly"

mkdir -p \
  "${source_payload}/resources/gateway/dist" \
  "${source_payload}/resources/gateway/node_modules/undici" \
  "${source_payload}/resources/gateway/node_modules/@scope/new-js-package" \
  "${source_payload}/resources/mcp-tools/dist" \
  "${source_payload}/resources/opencode/config" \
  "${source_payload}/resources/icons" \
  "${payload_dir}/resources/gateway/node_modules/better-sqlite3" \
  "${payload_dir}/resources/gateway/node_modules/@scope/linux-native-package" \
  "${runtime_dir}/node/bin" \
  "${runtime_dir}/resources/opencode" \
  "${runtime_dir}/resources/ffmpeg"

printf 'asar\n' >"${source_payload}/resources/app.asar"
printf 'gateway\n' >"${source_payload}/resources/gateway/dist/main.js"
printf 'mcp\n' >"${source_payload}/resources/mcp-tools/dist/main.js"
printf '{"name":"undici"}\n' >"${source_payload}/resources/gateway/node_modules/undici/package.json"
printf '{"name":"@scope/new-js-package"}\n' >"${source_payload}/resources/gateway/node_modules/@scope/new-js-package/package.json"
printf 'png\n' >"${source_payload}/resources/icons/minimax-hub.png"

printf 'linux native module\n' >"${payload_dir}/resources/gateway/node_modules/better-sqlite3/linux-native.marker"
printf 'linux scoped native module\n' >"${payload_dir}/resources/gateway/node_modules/@scope/linux-native-package/linux-native.marker"

for executable in \
  "${runtime_dir}/electron" \
  "${runtime_dir}/node/bin/node" \
  "${runtime_dir}/resources/opencode/opencode" \
  "${runtime_dir}/resources/ffmpeg/ffmpeg" \
  "${runtime_dir}/resources/ffmpeg/ffprobe"; do
  printf '#!/usr/bin/env sh\nexit 0\n' >"${executable}"
  chmod +x "${executable}"
done

bash "${PROJECT_ROOT}/scripts/assemble-linux-payload.sh" \
  --source-payload "${source_payload}" \
  --payload-dir "${payload_dir}" \
  --runtime-dir "${runtime_dir}" \
  --assembly-dir "${assembly_dir}" \
  --no-normalize >/dev/null

require_file "${payload_dir}/resources/gateway/node_modules/undici/package.json"
require_file "${payload_dir}/resources/gateway/node_modules/@scope/new-js-package/package.json"
require_file "${payload_dir}/resources/gateway/node_modules/better-sqlite3/linux-native.marker"
require_file "${payload_dir}/resources/gateway/node_modules/@scope/linux-native-package/linux-native.marker"

echo "Gateway module assembly verification passed"
