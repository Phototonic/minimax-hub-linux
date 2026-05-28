#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/testlib.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

root_dir="${tmp_dir}/root"
report_file="${tmp_dir}/sha256.txt"

mkdir -p "${root_dir}/b" "${root_dir}/a"
printf '%s\n' alpha >"${root_dir}/a/file.txt"
printf '%s\n' beta >"${root_dir}/b/file.txt"
printf '%s\n' gamma >"${root_dir}/root.txt"

source "${PROJECT_ROOT}/scripts/common.sh"
MINIMAX_HUB_CHECKSUM_JOBS=2 write_sha256_report "${root_dir}" "${report_file}"

require_file "${report_file}"
assert_file_contains "${report_file}" "a/file.txt"
assert_file_contains "${report_file}" "b/file.txt"
assert_file_contains "${report_file}" "root.txt"

line_count="$(wc -l <"${report_file}" | tr -d '[:space:]')"
[[ "${line_count}" == "3" ]] || fail "Expected 3 checksum lines, got ${line_count}"

echo "SHA256 report verification passed"
