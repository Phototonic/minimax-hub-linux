#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/testlib.sh"

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "${tmp_dir}"
}
trap cleanup EXIT

payload_dir="${tmp_dir}/payload"
gateway_dir="${payload_dir}/resources/gateway"
node_dir="${payload_dir}/node/bin"
fake_bin="${tmp_dir}/fake-bin"
cache_dir="${tmp_dir}/cache"

mkdir -p \
  "${gateway_dir}/node_modules/better-sqlite3/lib" \
  "${node_dir}" \
  "${fake_bin}" \
  "${cache_dir}"

cat >"${gateway_dir}/node_modules/better-sqlite3/package.json" <<'JSON'
{"name":"better-sqlite3","version":"12.4.1"}
JSON

cat >"${gateway_dir}/node_modules/better-sqlite3/lib/database.js" <<'JS'
// hilo-agent-opencode patch: dual-ABI binding loader.
function loadAddon() {}
module.exports = function Database() {};
JS

cat >"${node_dir}/node" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "-p" && "${2:-}" == "process.versions.modules" ]]; then
  echo 127
  exit 0
fi
if [[ "${1:-}" == "-e" ]]; then
  modules_dir="${NODE_PATH:-}"
  [[ -f "${modules_dir}/.fake-node-ready" ]] || exit 1
  exit 0
fi
exit 0
SH
chmod +x "${node_dir}/node"

cat >"${payload_dir}/electron" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${ELECTRON_RUN_AS_NODE:-}" == "1" && "${1:-}" == "-p" && "${2:-}" == "process.versions.modules" ]]; then
  echo 139
  exit 0
fi
if [[ "${ELECTRON_RUN_AS_NODE:-}" == "1" && "${1:-}" == "-p" && "${2:-}" == "process.versions.electron" ]]; then
  echo 38.8.6
  exit 0
fi
if [[ "${ELECTRON_RUN_AS_NODE:-}" == "1" && "${1:-}" == "-e" ]]; then
  modules_dir="${NODE_PATH:-}"
  [[ -f "${modules_dir}/better-sqlite3/build/Release-abi-139/better_sqlite3.node" ]] || exit 1
  exit 0
fi
exit 0
SH
chmod +x "${payload_dir}/electron"

cat >"${node_dir}/npm" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
prefix=""
runtime="node"
target=""
prev=""
for arg in "$@"; do
  if [[ "${prev}" == "--prefix" ]]; then
    prefix="${arg}"
  fi
  case "${arg}" in
    --runtime=*) runtime="${arg#--runtime=}" ;;
    --target=*) target="${arg#--target=}" ;;
  esac
  prev="${arg}"
done
[[ -n "${prefix}" ]] || { echo "missing --prefix" >&2; exit 1; }
modules="${prefix}/node_modules"
mkdir -p \
  "${modules}/better-sqlite3/build/Release" \
  "${modules}/better-sqlite3/lib" \
  "${modules}/sharp" \
  "${modules}/@node-rs/xxhash"
printf '{"name":"better-sqlite3","version":"12.4.1"}\n' >"${modules}/better-sqlite3/package.json"
printf 'module.exports = function Database() {};\n' >"${modules}/better-sqlite3/lib/database.js"
printf '%s:%s\n' "${runtime}" "${target}" >"${modules}/better-sqlite3/build/Release/better_sqlite3.node"
touch "${modules}/.fake-node-ready"
SH
chmod +x "${node_dir}/npm"

cat >"${fake_bin}/python3" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
script="$(cat)"
package_json="${2:-}"
dependency_name="${3:-}"
if [[ "${script}" == *"data.get(\"version\")"* ]]; then
  sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "${package_json}" | head -n 1
elif [[ "${script}" == *"dependency_name = sys.argv[2]"* ]]; then
  sed -n "s/.*\"${dependency_name}\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" "${package_json}" | head -n 1
else
  exit 1
fi
SH
chmod +x "${fake_bin}/python3"

PATH="${fake_bin}:${PATH}" bash "${PROJECT_ROOT}/scripts/rebuild-native-modules.sh" \
  --payload-dir "${payload_dir}" \
  --cache-dir "${cache_dir}" \
  --electron-version 38.8.6 >/dev/null

require_file "${gateway_dir}/node_modules/better-sqlite3/build/Release-abi-127/better_sqlite3.node"
require_file "${gateway_dir}/node_modules/better-sqlite3/build/Release-abi-139/better_sqlite3.node"
assert_file_contains "${gateway_dir}/node_modules/better-sqlite3/build/Release-abi-127/better_sqlite3.node" "node:"
assert_file_contains "${gateway_dir}/node_modules/better-sqlite3/build/Release-abi-139/better_sqlite3.node" "electron:38.8.6"
assert_file_contains "${gateway_dir}/node_modules/better-sqlite3/lib/database.js" "hilo-agent-opencode patch: dual-ABI binding loader"

second_output="$(PATH="${fake_bin}:${PATH}" bash "${PROJECT_ROOT}/scripts/rebuild-native-modules.sh" \
  --payload-dir "${payload_dir}" \
  --cache-dir "${cache_dir}" \
  --electron-version 38.8.6)"
assert_contains "${second_output}" "skipping npm install and rebuild" "second native rebuild output"

echo "Electron ABI native module rebuild verification passed"
