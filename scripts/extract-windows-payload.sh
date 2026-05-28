#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

cache_dir="${WINDOWS_PAYLOAD_CACHE}"
source_path=""
write_reports="${MINIMAX_HUB_PAYLOAD_REPORTS:-1}"

usage() {
  cat <<USAGE
Usage: $(basename "$0") [--source PATH] [--cache-dir PATH] [--no-reports]

Stages MiniMax Hub Windows application resources into an ignored cache.

Options:
  --source PATH     MiniMax Hub install root. Defaults to package-manifest.json sourceInstallPath.
  --cache-dir PATH  Output cache directory. Defaults to .cache/windows-payload.
  --no-reports      Skip inventory/checksum/discovery reports; keep required safety checks.
  -h, --help        Show this help text.

The staged Linux-source payload is written to CACHE_DIR/payload and reports are
written to CACHE_DIR/inventory.txt, CACHE_DIR/sha256.txt, and CACHE_DIR/report.txt.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source)
      [[ $# -ge 2 ]] || die "--source requires a path."
      source_path="$2"
      shift 2
      ;;
    --cache-dir)
      [[ $# -ge 2 ]] || die "--cache-dir requires a path."
      cache_dir="$2"
      shift 2
      ;;
    --no-reports)
      write_reports=0
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

copy_path_if_present() {
  local relative_path="$1"
  local source_root="$2"
  local target_root="$3"
  local source_item="${source_root}/${relative_path}"
  local target_item="${target_root}/${relative_path}"

  [[ -e "${source_item}" ]] || return 0
  ensure_dir "$(dirname "${target_item}")"
  cp -a "${source_item}" "${target_item}"
}

copy_matching_top_level_files() {
  local source_root="$1"
  local target_root="$2"
  local file_name lower_name target_item

  while IFS= read -r -d '' file_name; do
    lower_name="$(basename "${file_name}" | tr '[:upper:]' '[:lower:]')"
    case "${lower_name}" in
      *.json|*.pak|*.dat|*.bin|*.ico|*.png|*.icns|*.desktop|*.yml|*.yaml|license*|credits*)
        target_item="${target_root}/$(basename "${file_name}")"
        cp -a "${file_name}" "${target_item}"
        ;;
    esac
  done < <(find "${source_root}" -maxdepth 1 -type f -print0)
}

remove_forbidden_windows_artifacts() {
  local target_root="$1"

  while IFS= read -r -d '' artifact; do
    rm -f "${artifact}"
  done < <(find "${target_root}" -type f \( -iname '*.exe' -o -iname '*.dll' -o -iname '*.bat' -o -iname '*.cmd' \) -print0)

  while IFS= read -r -d '' artifact_dir; do
    rm -rf "${artifact_dir}"
  done < <(find "${target_root}" -depth -type d \( -iname '*win32*' -o -iname '*windows*' -o -iname '*msvc*' \) -print0)
}

write_extraction_report() {
  local payload_dir="$1"
  local report_file="$2"
  local source_root="$3"
  local native_modules protocol_candidates

  native_modules="$(find "${payload_dir}" -type f -name '*.node' -printf '%P\n' | LC_ALL=C sort || true)"
  protocol_candidates="$(find "${payload_dir}" -type f \( -iname '*.desktop' -o -iname '*.json' -o -iname '*.plist' -o -iname '*.yml' -o -iname '*.yaml' \) -print0 | xargs -0 grep -Eho 'x-scheme-handler/[A-Za-z0-9.+-]+|[A-Za-z][A-Za-z0-9.+-]+://' 2>/dev/null | LC_ALL=C sort -u || true)"

  {
    echo "MiniMax Hub Windows payload extraction report"
    echo "Source: ${source_root}"
    echo "Payload: ${payload_dir}"
    echo
    echo "Included components:"
    [[ -f "${payload_dir}/resources/app.asar" ]] && echo "- resources/app.asar"
    [[ -d "${payload_dir}/resources/app.asar.unpacked" ]] && echo "- resources/app.asar.unpacked"
    [[ -d "${payload_dir}/resources/gateway" ]] && echo "- resources/gateway"
    [[ -d "${payload_dir}/resources/mcp-tools" ]] && echo "- resources/mcp-tools"
    [[ -d "${payload_dir}/resources/opencode/config" ]] && echo "- resources/opencode/config"
    [[ -d "${payload_dir}/resources/opencode/plugins" ]] && echo "- resources/opencode/plugins"
    [[ -d "${payload_dir}/resources/plugins" ]] && echo "- resources/plugins"
    [[ -d "${payload_dir}/resources/icons" ]] && echo "- resources/icons"
    echo
    echo "Native modules discovered:"
    if [[ -n "${native_modules}" ]]; then
      printf '%s\n' "${native_modules}"
    else
      echo "none"
    fi
    echo
    echo "Protocol candidates discovered:"
    if [[ -n "${protocol_candidates}" ]]; then
      printf '%s\n' "${protocol_candidates}"
    else
      echo "none"
    fi
    echo
    echo "Platform-specific replacements still required: Electron Linux runtime, Linux Node runtime, Linux OpenCode binary, Linux FFmpeg/FFprobe, and Linux native modules."
  } >"${report_file}"
}

if [[ -z "${source_path}" ]]; then
  source_path="$(default_source_install_path)"
fi

resolved_source="$(resolve_source_path "${source_path}")"
resources_source="${resolved_source}/resources"
payload_dir="${cache_dir}/payload"

[[ -d "${resources_source}" ]] || die "MiniMax Hub resources directory is missing under source path: ${resources_source}. Provide --source pointing at the installed app root that contains resources/app.asar."

rm -rf "${payload_dir}"
ensure_dir "${payload_dir}/resources"

copy_path_if_present "resources/app.asar" "${resolved_source}" "${payload_dir}"
copy_path_if_present "resources/app.asar.unpacked" "${resolved_source}" "${payload_dir}"
copy_path_if_present "resources/gateway" "${resolved_source}" "${payload_dir}"
copy_path_if_present "resources/mcp-tools" "${resolved_source}" "${payload_dir}"
copy_path_if_present "resources/opencode/config" "${resolved_source}" "${payload_dir}"
copy_path_if_present "resources/opencode/plugins" "${resolved_source}" "${payload_dir}"
copy_path_if_present "resources/plugins" "${resolved_source}" "${payload_dir}"
copy_path_if_present "resources/icons" "${resolved_source}" "${payload_dir}"
copy_path_if_present "resources/assets" "${resolved_source}" "${payload_dir}"
copy_path_if_present "resources/app-resources" "${resolved_source}" "${payload_dir}"
copy_path_if_present "resources/app-update.yml" "${resolved_source}" "${payload_dir}"
copy_path_if_present "resources/electron.asar" "${resolved_source}" "${payload_dir}"
copy_matching_top_level_files "${resolved_source}" "${payload_dir}"

remove_forbidden_windows_artifacts "${payload_dir}"

if [[ "${write_reports}" == "1" ]]; then
  write_sorted_inventory "${payload_dir}" "${cache_dir}/inventory.txt"
  write_sha256_report "${payload_dir}" "${cache_dir}/sha256.txt"
  write_extraction_report "${payload_dir}" "${cache_dir}/report.txt" "${resolved_source}"
else
  info "Skipping extraction inventory/checksum/discovery reports because reports are disabled"
fi

forbidden="$(find_forbidden_windows_artifacts "${payload_dir}")"
[[ -z "${forbidden}" ]] || die "Forbidden Windows artifacts remain in staged payload: ${forbidden}"

info "Staged Windows payload resources in ${payload_dir}"
if [[ "${write_reports}" == "1" ]]; then
  info "Wrote ${cache_dir}/inventory.txt, ${cache_dir}/sha256.txt, and ${cache_dir}/report.txt"
fi
