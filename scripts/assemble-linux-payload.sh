#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

source_payload="${WINDOWS_PAYLOAD_CACHE}/payload"
payload_dir="${DEFAULT_PAYLOAD_DIR}"
installed_icon="${PROJECT_ROOT}/linux-build/usr/share/icons/hicolor/256x256/apps/minimax-hub.png"
runtime_dir=""
assembly_dir="${PROJECT_ROOT}/.cache/assembly"
electron_bin=""
chrome_sandbox_bin=""
node_dir=""
node_bin=""
opencode_bin=""
ffmpeg_bin=""
ffprobe_bin=""
dry_run=0
run_normalize=1

usage() {
  cat <<USAGE
Usage: $(basename "$0") [options]

Assembles linux-build/opt/minimax-hub from staged Windows app resources and
Linux runtime replacements that are already present or provided explicitly.

Options:
  --source-payload DIR   Staged Windows app-resource payload (default: .cache/windows-payload/payload)
  --payload-dir DIR      Final payload root (default: linux-build/opt/minimax-hub)
  --runtime-dir DIR      Optional payload-shaped tree containing Linux replacements
  --assembly-dir DIR     Report/cache directory (default: .cache/assembly)
  --electron FILE        Override Electron Linux binary
  --chrome-sandbox FILE  Override chrome-sandbox binary
  --node-dir DIR         Override complete Node runtime directory copied to PAYLOAD_DIR/node
  --node-bin FILE        Override Node binary copied to PAYLOAD_DIR/node/bin/node
  --opencode FILE        Override OpenCode Linux binary
  --ffmpeg FILE          Override ffmpeg Linux binary
  --ffprobe FILE         Override ffprobe Linux binary
  --no-normalize         Do not run scripts/normalize-payload.sh after assembly
  --dry-run              Print planned operations without changing files
  -h, --help             Show this help text
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

copy_file_to() {
  local source_file="$1"
  local target_file="$2"
  [[ -f "${source_file}" ]] || die "Required source file is missing: ${source_file}"
  log_action "Copy $(relative_path "${PROJECT_ROOT}" "${source_file}") -> $(relative_path "${PROJECT_ROOT}" "${target_file}")"
  if [[ "${dry_run}" -eq 1 ]]; then
    run_or_print cp -a "${source_file}" "${target_file}"
    return 0
  fi
  ensure_dir "$(dirname "${target_file}")"
  cp -a "${source_file}" "${target_file}"
}

copy_dir_to() {
  local source_dir="$1"
  local target_dir="$2"
  shift 2
  [[ -d "${source_dir}" ]] || die "Required source directory is missing: ${source_dir}"
  log_action "Copy $(relative_path "${PROJECT_ROOT}" "${source_dir}") -> $(relative_path "${PROJECT_ROOT}" "${target_dir}")"
  if [[ "${dry_run}" -eq 1 ]]; then
    run_or_print mkdir -p "${target_dir}"
    if [[ $# -gt 0 ]]; then
      log_action "DRY-RUN: tar exclusions: $*"
    fi
    run_or_print tar -C "${source_dir}" -cf - .
    return 0
  fi
  ensure_dir "${target_dir}"
  if [[ $# -gt 0 ]]; then
    (cd "${source_dir}" && tar "$@" -cf - .) | (cd "${target_dir}" && tar -xf -)
  else
    copy_tree_contents "${source_dir}" "${target_dir}"
  fi
}

copy_optional_file() {
  local relative="$1"
  local source_file="${source_payload}/${relative}"
  local target_file="${payload_dir}/${relative}"
  [[ -f "${source_file}" ]] || return 0
  copy_file_to "${source_file}" "${target_file}"
}

copy_optional_dir() {
  local relative="$1"
  local source_dir="${source_payload}/${relative}"
  local target_dir="${payload_dir}/${relative}"
  shift
  [[ -d "${source_dir}" ]] || return 0
  copy_dir_to "${source_dir}" "${target_dir}" "$@"
}

copy_missing_gateway_node_modules() {
  local source_modules="${source_payload}/resources/gateway/node_modules"
  local target_modules="${payload_dir}/resources/gateway/node_modules"
  local entry entry_name scoped_entry scoped_name

  [[ -d "${source_modules}" && -d "${target_modules}" ]] || return 0

  while IFS= read -r -d '' entry; do
    entry_name="$(basename "${entry}")"
    if [[ "${entry_name}" == @* && -d "${entry}" ]]; then
      ensure_dir "${target_modules}/${entry_name}"
      while IFS= read -r -d '' scoped_entry; do
        scoped_name="$(basename "${scoped_entry}")"
        if [[ ! -e "${target_modules}/${entry_name}/${scoped_name}" ]]; then
          copy_dir_to "${scoped_entry}" "${target_modules}/${entry_name}/${scoped_name}"
        fi
      done < <(find "${entry}" -mindepth 1 -maxdepth 1 -type d -print0 | LC_ALL=C sort -z)
    elif [[ ! -e "${target_modules}/${entry_name}" ]]; then
      if [[ -d "${entry}" ]]; then
        copy_dir_to "${entry}" "${target_modules}/${entry_name}"
      elif [[ -f "${entry}" ]]; then
        copy_file_to "${entry}" "${target_modules}/${entry_name}"
      fi
    fi
  done < <(find "${source_modules}" -mindepth 1 -maxdepth 1 -print0 | LC_ALL=C sort -z)
}

copy_runtime_file_from_tree() {
  local relative="$1"
  [[ -n "${runtime_dir}" ]] || return 0
  [[ -f "${runtime_dir}/${relative}" ]] || return 0
  copy_file_to "${runtime_dir}/${relative}" "${payload_dir}/${relative}"
}

copy_runtime_dir_from_tree() {
  local relative="$1"
  [[ -n "${runtime_dir}" ]] || return 0
  [[ -d "${runtime_dir}/${relative}" ]] || return 0
  copy_dir_to "${runtime_dir}/${relative}" "${payload_dir}/${relative}"
}

copy_top_level_resource_files() {
  local file_name lower_name target_file
  [[ -d "${source_payload}" ]] || return 0
  while IFS= read -r -d '' file_name; do
    lower_name="$(basename "${file_name}" | tr '[:upper:]' '[:lower:]')"
    case "${lower_name}" in
      app-update.yml)
        log_action "Skip Linux-disabled updater metadata: $(relative_path "${PROJECT_ROOT}" "${file_name}")"
        ;;
      *.json|*.pak|*.dat|*.bin|*.ico|*.png|*.icns|*.desktop|*.yml|*.yaml|license*|credits*)
        target_file="${payload_dir}/$(basename "${file_name}")"
        copy_file_to "${file_name}" "${target_file}"
        ;;
    esac
  done < <(find "${source_payload}" -maxdepth 1 -type f -print0)
}

find_icon_candidate_in_dir() {
  local search_dir="$1"
  local maxdepth="${2:-}"
  local find_args=("${search_dir}")
  [[ -d "${search_dir}" ]] || return 0
  [[ -z "${maxdepth}" ]] || find_args+=(-maxdepth "${maxdepth}")
  find "${find_args[@]}" -type f -iname '*.png' | LC_ALL=C sort | awk '
    { lower = tolower($0) }
    lower ~ /minimax.*hub.*256|256.*minimax.*hub|minimax.*hub|hub|icon.*256|256.*icon|logo.*256|256.*logo|icon|logo/ { print; exit }
  '
}

find_desktop_icon_candidate() {
  local candidate search_dir
  for candidate in \
    "${source_payload}/resources/icons/minimax-hub.png" \
    "${source_payload}/resources/icons/icon.png" \
    "${source_payload}/resources/icons/256x256.png" \
    "${source_payload}/resources/assets/minimax-hub.png" \
    "${source_payload}/resources/assets/icon.png" \
    "${source_payload}/resources/app-resources/minimax-hub.png" \
    "${source_payload}/resources/app-resources/icon.png" \
    "${source_payload}/resources/app-resources/tray.png" \
    "${source_payload}/resources/minimax-hub.png" \
    "${source_payload}/resources/icon.png" \
    "${source_payload}/minimax-hub.png" \
    "${source_payload}/icon.png"; do
    [[ -s "${candidate}" ]] && printf '%s\n' "${candidate}" && return 0
  done

  for search_dir in \
    "${source_payload}/resources/icons" \
    "${source_payload}/resources/assets" \
    "${source_payload}/resources/app-resources" \
    "${source_payload}/resources"; do
    candidate="$(find_icon_candidate_in_dir "${search_dir}")"
    [[ -n "${candidate}" && -s "${candidate}" ]] && printf '%s\n' "${candidate}" && return 0
  done

  candidate="$(find_icon_candidate_in_dir "${source_payload}" 1)"
  [[ -n "${candidate}" && -s "${candidate}" ]] && printf '%s\n' "${candidate}" && return 0
}

stage_desktop_icon() {
  local icon_candidate
  icon_candidate="$(find_desktop_icon_candidate)"
  if [[ -n "${icon_candidate}" ]]; then
    copy_file_to "${icon_candidate}" "${installed_icon}"
  else
    log_action "MISSING: desktop icon candidate for ${installed_icon} (expected a PNG from source payload resources/icons, resources/assets, resources/app-resources, resources, or top level)"
  fi
}

remove_linux_updater_metadata() {
  local updater_file
  for updater_file in "${payload_dir}/resources/app-update.yml" "${payload_dir}/app-update.yml"; do
    [[ -e "${updater_file}" ]] || continue
    log_action "Remove Linux-disabled updater metadata: $(relative_path "${PROJECT_ROOT}" "${updater_file}")"
    run_or_print rm -f "${updater_file}"
  done
}

record_missing() {
  local message="$1"
  missing+=("${message}")
  log_action "MISSING: ${message}"
}

require_existing_prerequisites() {
  missing=()
  if [[ ! -d "${source_payload}" ]]; then
    record_missing "source payload directory: ${source_payload} (run scripts/extract-windows-payload.sh first or pass --source-payload)"
  else
    [[ -s "${source_payload}/resources/app.asar" ]] || record_missing "${source_payload}/resources/app.asar"
    [[ -s "${source_payload}/resources/gateway/dist/main.js" ]] || record_missing "${source_payload}/resources/gateway/dist/main.js"
    [[ -s "${source_payload}/resources/mcp-tools/dist/main.js" ]] || record_missing "${source_payload}/resources/mcp-tools/dist/main.js"
    [[ -d "${source_payload}/resources/opencode/config" ]] || record_missing "${source_payload}/resources/opencode/config"
  fi

  if [[ -n "${runtime_dir}" && ! -d "${runtime_dir}" ]]; then
    record_missing "runtime override directory: ${runtime_dir}"
  fi

  local override
  for override in "${electron_bin}" "${chrome_sandbox_bin}" "${node_bin}" "${opencode_bin}" "${ffmpeg_bin}" "${ffprobe_bin}"; do
    [[ -z "${override}" || -f "${override}" ]] || record_missing "override file: ${override}"
  done
  [[ -z "${node_dir}" || -d "${node_dir}" ]] || record_missing "Node override directory: ${node_dir}"

  if [[ ${#missing[@]} -gt 0 ]]; then
    if [[ "${dry_run}" -eq 1 ]]; then
      log_action "Dry run only; non-dry-run assembly would fail until missing prerequisites are staged."
    else
      printf 'Error: Missing assembly prerequisites:\n' >&2
      printf 'Error: - %s\n' "${missing[@]}" >&2
      exit 1
    fi
  fi
}

copy_app_resources() {
  [[ -d "${source_payload}" ]] || return 0
  copy_optional_file "resources/app.asar"
  copy_optional_dir "resources/app.asar.unpacked"

  gateway_excludes=()
  if [[ -d "${payload_dir}/resources/gateway/node_modules" ]]; then
    gateway_excludes+=(--exclude ./node_modules)
    log_action "Preserve existing Linux gateway node_modules at ${payload_dir}/resources/gateway/node_modules"
  fi
  copy_optional_dir "resources/gateway" "${gateway_excludes[@]}"
  copy_missing_gateway_node_modules
  copy_optional_dir "resources/mcp-tools"
  copy_optional_dir "resources/opencode/config"
  copy_optional_dir "resources/opencode/plugins"
  copy_optional_dir "resources/plugins"
  copy_optional_dir "resources/icons"
  copy_optional_dir "resources/assets"
  copy_optional_dir "resources/app-resources"
  copy_optional_file "resources/electron.asar"
  copy_top_level_resource_files
  stage_desktop_icon
  remove_linux_updater_metadata
}

copy_linux_replacements() {
  copy_runtime_file_from_tree "electron"
  copy_runtime_file_from_tree "chrome-sandbox"
  copy_runtime_dir_from_tree "node"
  copy_runtime_file_from_tree "resources/opencode/opencode"
  copy_runtime_file_from_tree "resources/ffmpeg/ffmpeg"
  copy_runtime_file_from_tree "resources/ffmpeg/ffprobe"

  [[ -z "${electron_bin}" ]] || copy_file_to "${electron_bin}" "${payload_dir}/electron"
  [[ -z "${chrome_sandbox_bin}" ]] || copy_file_to "${chrome_sandbox_bin}" "${payload_dir}/chrome-sandbox"
  [[ -z "${node_dir}" ]] || copy_dir_to "${node_dir}" "${payload_dir}/node"
  [[ -z "${node_bin}" ]] || copy_file_to "${node_bin}" "${payload_dir}/node/bin/node"
  [[ -z "${opencode_bin}" ]] || copy_file_to "${opencode_bin}" "${payload_dir}/resources/opencode/opencode"
  [[ -z "${ffmpeg_bin}" ]] || copy_file_to "${ffmpeg_bin}" "${payload_dir}/resources/ffmpeg/ffmpeg"
  [[ -z "${ffprobe_bin}" ]] || copy_file_to "${ffprobe_bin}" "${payload_dir}/resources/ffmpeg/ffprobe"
}

verify_final_prerequisites() {
  local required=()
  [[ -s "${payload_dir}/resources/app.asar" ]] || required+=("resources/app.asar")
  [[ -s "${payload_dir}/resources/gateway/dist/main.js" ]] || required+=("resources/gateway/dist/main.js")
  [[ -s "${payload_dir}/resources/mcp-tools/dist/main.js" ]] || required+=("resources/mcp-tools/dist/main.js")
  [[ -d "${payload_dir}/resources/opencode/config" ]] || required+=("resources/opencode/config")
  [[ -x "${payload_dir}/electron" ]] || required+=("electron executable")
  [[ ! -e "${payload_dir}/chrome-sandbox" || -x "${payload_dir}/chrome-sandbox" ]] || required+=("chrome-sandbox executable bit")
  [[ -x "${payload_dir}/node/bin/node" ]] || required+=("node/bin/node executable")
  [[ -x "${payload_dir}/resources/opencode/opencode" ]] || required+=("resources/opencode/opencode executable")
  [[ -x "${payload_dir}/resources/ffmpeg/ffmpeg" ]] || required+=("resources/ffmpeg/ffmpeg executable")
  [[ -x "${payload_dir}/resources/ffmpeg/ffprobe" ]] || required+=("resources/ffmpeg/ffprobe executable")
  [[ -d "${payload_dir}/resources/gateway/node_modules" ]] || required+=("resources/gateway/node_modules Linux-native modules from Task 5")
  [[ -s "${installed_icon}" ]] || required+=("installed desktop icon: ${installed_icon}")
  [[ ! -e "${payload_dir}/resources/app-update.yml" ]] || required+=("remove Linux-disabled updater metadata: resources/app-update.yml")
  [[ ! -e "${payload_dir}/app-update.yml" ]] || required+=("remove Linux-disabled updater metadata: app-update.yml")

  if [[ ${#required[@]} -gt 0 ]]; then
    printf 'Error: Assembled payload is missing required Linux prerequisites:\n' >&2
    printf 'Error: - %s\n' "${required[@]}" >&2
    printf 'Error: Run Tasks 3, 4, and 5 first, or pass explicit Linux replacement options to this script.\n' >&2
    exit 1
  fi
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
    --runtime-dir)
      [[ $# -ge 2 ]] || die "--runtime-dir requires a path."
      runtime_dir="$2"
      shift 2
      ;;
    --assembly-dir)
      [[ $# -ge 2 ]] || die "--assembly-dir requires a path."
      assembly_dir="$2"
      shift 2
      ;;
    --electron)
      [[ $# -ge 2 ]] || die "--electron requires a path."
      electron_bin="$2"
      shift 2
      ;;
    --chrome-sandbox)
      [[ $# -ge 2 ]] || die "--chrome-sandbox requires a path."
      chrome_sandbox_bin="$2"
      shift 2
      ;;
    --node-dir)
      [[ $# -ge 2 ]] || die "--node-dir requires a path."
      node_dir="$2"
      shift 2
      ;;
    --node-bin)
      [[ $# -ge 2 ]] || die "--node-bin requires a path."
      node_bin="$2"
      shift 2
      ;;
    --opencode)
      [[ $# -ge 2 ]] || die "--opencode requires a path."
      opencode_bin="$2"
      shift 2
      ;;
    --ffmpeg)
      [[ $# -ge 2 ]] || die "--ffmpeg requires a path."
      ffmpeg_bin="$2"
      shift 2
      ;;
    --ffprobe)
      [[ $# -ge 2 ]] || die "--ffprobe requires a path."
      ffprobe_bin="$2"
      shift 2
      ;;
    --no-normalize)
      run_normalize=0
      shift
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

log_action "Linux payload assembly plan"
log_action "- source payload: ${source_payload}"
log_action "- payload: ${payload_dir}"
log_action "- runtime overrides: ${runtime_dir:-already staged in payload or explicit file options}"
log_action "- reports: ${assembly_dir}"
log_action "- normalize: $([[ "${run_normalize}" -eq 1 ]] && echo yes || echo no)"

require_existing_prerequisites

if [[ "${dry_run}" -eq 1 ]]; then
  log_action "Dry run only; files will not be changed."
else
  ensure_dir "${payload_dir}"
  ensure_dir "${assembly_dir}"
fi

copy_app_resources
copy_linux_replacements

if [[ "${run_normalize}" -eq 1 ]]; then
  normalize_args=("${PROJECT_ROOT}/scripts/normalize-payload.sh" --payload-dir "${payload_dir}" --assembly-dir "${assembly_dir}")
  [[ "${dry_run}" -eq 0 ]] || normalize_args+=(--dry-run)
  log_action "Run normalize-payload.sh for executable bits, CRLF cleanup, forbidden artifact checks, and reports"
  run_or_print bash "${normalize_args[@]}"
fi

if [[ "${dry_run}" -eq 1 ]]; then
  log_action "Dry run complete."
  exit 0
fi

verify_final_prerequisites

info "Linux payload assembled at ${payload_dir}"
