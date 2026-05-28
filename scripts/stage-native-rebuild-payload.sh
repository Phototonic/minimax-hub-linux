#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

source_payload="${WINDOWS_PAYLOAD_CACHE}/payload"
payload_dir="${DEFAULT_PAYLOAD_DIR}"
dry_run=0

usage() {
  cat <<USAGE
Usage: $(basename "$0") [options]

Stages only the gateway files required by scripts/rebuild-native-modules.sh.
This avoids a full app payload assembly before native modules are rebuilt.

Options:
  --source-payload DIR  Staged Windows app-resource payload (default: .cache/windows-payload/payload)
  --payload-dir DIR     Payload root (default: linux-build/opt/minimax-hub)
  --dry-run             Print planned operations without changing files
  -h, --help            Show this help text
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

copy_dir_to() {
  local source_dir="$1"
  local target_dir="$2"
  [[ -d "${source_dir}" ]] || die "Required source directory is missing: ${source_dir}"
  log_action "Copy $(relative_path "${PROJECT_ROOT}" "${source_dir}") -> $(relative_path "${PROJECT_ROOT}" "${target_dir}")"
  if [[ "${dry_run}" -eq 1 ]]; then
    run_or_print mkdir -p "${target_dir}"
    run_or_print cp -a "${source_dir}/." "${target_dir}/"
    return 0
  fi
  rm -rf "${target_dir}"
  ensure_dir "${target_dir}"
  cp -a "${source_dir}/." "${target_dir}/"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source-payload)
      [[ $# -ge 2 ]] || die "--source-payload requires a path."
      source_payload="$2"
      shift 2
      ;;
    --payload-dir)
      [[ $# -ge 2 ]] || die "--payload-dir requires a path."
      payload_dir="$2"
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

source_gateway="${source_payload}/resources/gateway"
target_gateway="${payload_dir}/resources/gateway"

log_action "Native rebuild staging plan"
log_action "- source payload: ${source_payload}"
log_action "- gateway source: ${source_gateway}"
log_action "- gateway target: ${target_gateway}"

[[ -s "${source_gateway}/package.json" || -d "${source_gateway}/node_modules" ]] || die "Gateway source lacks package.json or node_modules: ${source_gateway}"
[[ -d "${source_gateway}/node_modules" ]] || die "Gateway node_modules is required for native rebuild staging: ${source_gateway}/node_modules"

copy_dir_to "${source_gateway}" "${target_gateway}"

if [[ "${dry_run}" -eq 0 ]]; then
  info "Native rebuild gateway staged at ${target_gateway}"
fi
