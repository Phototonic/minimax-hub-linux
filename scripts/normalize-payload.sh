#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

payload_dir="${DEFAULT_PAYLOAD_DIR}"
assembly_dir="${PROJECT_ROOT}/.cache/assembly"
dry_run=0

usage() {
  cat <<USAGE
Usage: $(basename "$0") [options]

Normalizes the assembled MiniMax Hub Linux payload by fixing executable bits,
removing CRLF line endings from packaged text files, checking for forbidden
Windows artifacts, and writing deterministic inventory/checksum reports.

Options:
  --payload-dir DIR   Payload root (default: linux-build/opt/minimax-hub)
  --assembly-dir DIR  Report/cache directory (default: .cache/assembly)
  --dry-run           Print planned operations without changing files
  -h, --help          Show this help text
USAGE
}

log_action() {
  echo "$*"
}

run_or_print() {
  if [[ "${dry_run}" -eq 1 ]]; then
    printf 'DRY-RUN: '
    printf '%q ' "$@"
    printf '\n'
    return 0
  fi
  "$@"
}

relative_path() {
  local base_dir="$1"
  local path="$2"
  case "${path}" in
    "${base_dir}"/*) printf '%s\n' "${path#"${base_dir}/"}" ;;
    *) printf '%s\n' "${path}" ;;
  esac
}

normalize_text_file() {
  local file_path="$1"
  [[ -f "${file_path}" ]] || return 0
  log_action "Normalize line endings: $(relative_path "${PROJECT_ROOT}" "${file_path}")"
  if [[ "${dry_run}" -eq 1 ]]; then
    run_or_print sh -c 'tmp="$(mktemp "${1}.XXXXXX")"; tr -d "\r" < "$1" > "$tmp"; cat "$tmp" > "$1"; rm -f "$tmp"' sh "${file_path}"
    return 0
  fi
  local temp_file
  temp_file="$(mktemp "${file_path}.XXXXXX")"
  tr -d '\r' <"${file_path}" >"${temp_file}"
  cat "${temp_file}" >"${file_path}"
  rm -f "${temp_file}"
}

set_executable() {
  local file_path="$1"
  [[ -e "${file_path}" ]] || return 0
  log_action "Set executable bit: $(relative_path "${PROJECT_ROOT}" "${file_path}")"
  run_or_print chmod 0755 "${file_path}"
}

normalize_payload_text_files() {
  [[ -d "${payload_dir}" ]] || return 0
  local file_path
  while IFS= read -r -d '' file_path; do
    normalize_text_file "${file_path}"
  done < <(find "${payload_dir}" -type f \( \
    -name '*.sh' -o \
    -name '*.desktop' -o \
    -name '*.json' -o \
    -name '*.js' -o \
    -name '*.cjs' -o \
    -name '*.mjs' -o \
    -name '*.yml' -o \
    -name '*.yaml' -o \
    -name '*.config' -o \
    -name '*.conf' \
  \) -print0)
}

normalize_packaging_text_files() {
  normalize_text_file "${PROJECT_ROOT}/linux-build/usr/bin/minimax-hub"
  normalize_text_file "${PROJECT_ROOT}/linux-build/usr/share/applications/minimax-hub.desktop"
  normalize_text_file "${PROJECT_ROOT}/linux-build/DEBIAN/control"
  normalize_text_file "${PROJECT_ROOT}/linux-build/DEBIAN/postinst"
  normalize_text_file "${PROJECT_ROOT}/linux-build/DEBIAN/prerm"
  normalize_text_file "${PROJECT_ROOT}/linux-build/DEBIAN/postrm"
  normalize_text_file "${PROJECT_ROOT}/rpm/minimax-hub.spec"
}

fix_executable_bits() {
  set_executable "${PROJECT_ROOT}/linux-build/usr/bin/minimax-hub"
  set_executable "${PROJECT_ROOT}/linux-build/DEBIAN/postinst"
  set_executable "${PROJECT_ROOT}/linux-build/DEBIAN/prerm"
  set_executable "${PROJECT_ROOT}/linux-build/DEBIAN/postrm"
  set_executable "${payload_dir}/electron"
  set_executable "${payload_dir}/chrome-sandbox"
  set_executable "${payload_dir}/node/bin/node"
  set_executable "${payload_dir}/resources/opencode/opencode"
  set_executable "${payload_dir}/resources/ffmpeg/ffmpeg"
  set_executable "${payload_dir}/resources/ffmpeg/ffprobe"
}

check_crlf_free() {
  local file_path="$1"
  [[ -f "${file_path}" ]] || return 0
  if LC_ALL=C grep -q $'\r' "${file_path}"; then
    die "CRLF line endings remain in packaged text file: ${file_path}"
  fi
}

verify_crlf_free() {
  check_crlf_free "${PROJECT_ROOT}/linux-build/usr/bin/minimax-hub"
  check_crlf_free "${PROJECT_ROOT}/linux-build/usr/share/applications/minimax-hub.desktop"
  check_crlf_free "${PROJECT_ROOT}/linux-build/DEBIAN/control"
  check_crlf_free "${PROJECT_ROOT}/linux-build/DEBIAN/postinst"
  check_crlf_free "${PROJECT_ROOT}/linux-build/DEBIAN/prerm"
  check_crlf_free "${PROJECT_ROOT}/linux-build/DEBIAN/postrm"
  check_crlf_free "${PROJECT_ROOT}/rpm/minimax-hub.spec"

  [[ -d "${payload_dir}" ]] || return 0
  local file_path
  while IFS= read -r -d '' file_path; do
    check_crlf_free "${file_path}"
  done < <(find "${payload_dir}" -type f \( \
    -name '*.sh' -o \
    -name '*.desktop' -o \
    -name '*.json' -o \
    -name '*.js' -o \
    -name '*.cjs' -o \
    -name '*.mjs' -o \
    -name '*.yml' -o \
    -name '*.yaml' -o \
    -name '*.config' -o \
    -name '*.conf' \
  \) -print0)
}

verify_no_forbidden_windows_artifacts() {
  local forbidden
  forbidden="$(find_forbidden_windows_artifacts "${payload_dir}")"
  if [[ -n "${forbidden}" ]]; then
    printf '%s\n' "${forbidden}" >&2
    die "Forbidden Windows artifacts remain in payload: ${payload_dir}"
  fi
}

write_normalization_report() {
  local report_file="${assembly_dir}/normalization-report.txt"
  ensure_dir "${assembly_dir}"
  {
    echo "MiniMax Hub payload normalization report"
    echo "Payload: ${payload_dir}"
    echo
    echo "Executable paths:"
    for path in \
      "${PROJECT_ROOT}/linux-build/usr/bin/minimax-hub" \
      "${payload_dir}/electron" \
      "${payload_dir}/chrome-sandbox" \
      "${payload_dir}/node/bin/node" \
      "${payload_dir}/resources/opencode/opencode" \
      "${payload_dir}/resources/ffmpeg/ffmpeg" \
      "${payload_dir}/resources/ffmpeg/ffprobe"; do
      if [[ -x "${path}" ]]; then
        echo "OK executable: $(relative_path "${PROJECT_ROOT}" "${path}")"
      elif [[ -e "${path}" ]]; then
        echo "NOT executable: $(relative_path "${PROJECT_ROOT}" "${path}")"
      else
        echo "MISSING: $(relative_path "${PROJECT_ROOT}" "${path}")"
      fi
    done
    echo
    if [[ -d "${payload_dir}" ]]; then
      local forbidden
      forbidden="$(find_forbidden_windows_artifacts "${payload_dir}")"
      if [[ -n "${forbidden}" ]]; then
        echo "Forbidden Windows artifacts:"
        printf '%s\n' "${forbidden}"
      else
        echo "Forbidden Windows artifacts: none"
      fi
    else
      echo "Payload directory missing: ${payload_dir}"
    fi
    echo
    echo "Reports:"
    echo "- ${assembly_dir}/inventory.txt"
    echo "- ${assembly_dir}/sha256.txt"
  } >"${report_file}"
  info "Wrote ${report_file}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --payload-dir)
      [[ $# -ge 2 ]] || die "--payload-dir requires a path."
      payload_dir="$2"
      shift 2
      ;;
    --assembly-dir)
      [[ $# -ge 2 ]] || die "--assembly-dir requires a path."
      assembly_dir="$2"
      shift 2
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
done

log_action "Payload normalization plan"
log_action "- payload: ${payload_dir}"
log_action "- reports: ${assembly_dir}"

if [[ ! -d "${payload_dir}" ]]; then
  if [[ "${dry_run}" -eq 1 ]]; then
    log_action "Payload directory is missing; non-dry-run normalization would fail: ${payload_dir}"
    exit 0
  fi
  die "Payload directory is missing: ${payload_dir}. Run scripts/assemble-linux-payload.sh after staging prerequisites."
fi

fix_executable_bits
normalize_packaging_text_files
normalize_payload_text_files

if [[ "${dry_run}" -eq 1 ]]; then
  log_action "DRY-RUN: would verify forbidden Windows artifacts under ${payload_dir}"
  log_action "DRY-RUN: would write ${assembly_dir}/inventory.txt, ${assembly_dir}/sha256.txt, and ${assembly_dir}/normalization-report.txt"
  exit 0
fi

verify_crlf_free
verify_no_forbidden_windows_artifacts
write_sorted_inventory "${payload_dir}" "${assembly_dir}/inventory.txt"
write_sha256_report "${payload_dir}" "${assembly_dir}/sha256.txt"
write_normalization_report

info "Payload normalized at ${payload_dir}"
