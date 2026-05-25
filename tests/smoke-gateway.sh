#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/testlib.sh"

payload_dir="${1:-${PAYLOAD_DIR}}"
node_bin="${payload_dir}/node/bin/node"
gateway_entry="${payload_dir}/resources/gateway/dist/main.js"

require_payload_not_empty "${payload_dir}"
require_executable "${node_bin}"
require_file "${gateway_entry}"
require_command curl

if ! "${node_bin}" --version >/dev/null 2>&1; then
  fail "Bundled Node runtime cannot execute: ${node_bin}"
fi

log_file="$(mktemp)"
"${node_bin}" "${gateway_entry}" >"${log_file}" 2>&1 &
gateway_pid="$!"
cleanup() {
  if kill -0 "${gateway_pid}" >/dev/null 2>&1; then
    kill "${gateway_pid}" >/dev/null 2>&1 || true
    wait "${gateway_pid}" >/dev/null 2>&1 || true
  fi
  rm -f "${log_file}"
}
trap cleanup EXIT

for url in "http://127.0.0.1:8001/health" "http://127.0.0.1:8001/"; do
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    if curl --fail --silent --max-time 1 "${url}" >/dev/null 2>&1; then
      echo "Gateway smoke verification passed: ${url}"
      exit 0
    fi
    if ! kill -0 "${gateway_pid}" >/dev/null 2>&1; then
      cat "${log_file}" >&2 || true
      fail "Gateway process exited before answering ${url}: ${gateway_entry}"
    fi
    sleep 1
  done
done

cat "${log_file}" >&2 || true
fail "Gateway did not answer http://127.0.0.1:8001/health or / within timeout."

