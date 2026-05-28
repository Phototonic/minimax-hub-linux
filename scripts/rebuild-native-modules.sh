#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

payload_dir="${DEFAULT_PAYLOAD_DIR}"
gateway_dir=""
cache_dir="${DEFAULT_CACHE_DIR}"
node_bin=""
electron_bin=""
node_bin_dir=""
npm_bin=""
dry_run=0
offline=0
npm_cache_dir=""
node_abi=""
electron_abi=""
electron_version=""

native_report=""
dual_abi_loader_backup=""

sharp_version="0.34.5"
sharp_linux_package="@img/sharp-linux-x64@0.34.5"
sharp_libvips_package="@img/sharp-libvips-linux-x64@1.2.4"
xxhash_package="@node-rs/xxhash@1.7.6"
xxhash_linux_package="@node-rs/xxhash-linux-x64-gnu@1.7.6"
better_sqlite3_package=""

usage() {
  cat <<USAGE
Usage: $(basename "$0") [options]

Replaces Windows native gateway modules with Linux-compatible staged packages.

Options:
  --payload-dir DIR       Payload root (default: linux-build/opt/minimax-hub)
  --gateway-dir DIR       Gateway root (default: PAYLOAD_DIR/resources/gateway)
  --cache-dir DIR         Cache/report directory (default: .cache/runtimes)
  --node-bin FILE         Packaged Node binary (default: PAYLOAD_DIR/node/bin/node)
  --electron-bin FILE     Packaged Electron binary (default: PAYLOAD_DIR/electron)
  --node-abi ABI          Expected Node module ABI for better-sqlite3 reporting/rebuild context
  --electron-abi ABI      Expected Electron module ABI for better-sqlite3 reporting/rebuild context
  --electron-version VER  Electron version for optional better-sqlite3 Electron rebuild guidance
  --npm-cache DIR         npm cache directory for staged install/rebuild commands
  --offline               Pass --offline to npm; requires packages already in the npm cache
  --dry-run               Print planned operations without changing files or running npm
  -h, --help              Show this help text
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

run_npm() {
  run_or_print env PATH="${node_bin_dir}:${PATH}" "${npm_bin}" "$@"
}

relative_path() {
  local base_dir="$1"
  local path="$2"
  case "${path}" in
    "${base_dir}"/*) printf '%s\n' "${path#"${base_dir}/"}" ;;
    *) printf '%s\n' "${path}" ;;
  esac
}

package_json_version() {
  local package_json="$1"
  local python_bin
  if python_bin="$(python_command)"; then
    "${python_bin}" - "${package_json}" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    data = json.load(handle)

version = data.get("version")
if version:
    print(version)
PY
    return
  fi

  awk -F '"' '/"version"[[:space:]]*:/ { print $4; exit }' "${package_json}"
}

package_json_dependency() {
  local package_json="$1"
  local dependency_name="$2"
  local python_bin
  if python_bin="$(python_command)"; then
    "${python_bin}" - "${package_json}" "${dependency_name}" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    data = json.load(handle)

dependency_name = sys.argv[2]
for section in ("dependencies", "optionalDependencies", "devDependencies"):
    value = data.get(section, {}).get(dependency_name)
    if value:
        print(value)
        break
PY
    return
  fi

  awk -F '"' -v dep="${dependency_name}" '
    /"dependencies"[[:space:]]*:/ || /"optionalDependencies"[[:space:]]*:/ || /"devDependencies"[[:space:]]*:/ { in_deps = 1; next }
    in_deps && /^[[:space:]]*}/ { in_deps = 0 }
    in_deps && $2 == dep { print $4; exit }
  ' "${package_json}"
}

write_report_line() {
  if [[ -n "${native_report}" ]]; then
    printf '%s\n' "$*" >>"${native_report}"
  fi
}

require_staged_prerequisites() {
  [[ -d "${payload_dir}" ]] || die "Payload directory is missing: ${payload_dir}. Run extraction/assembly staging first or pass --payload-dir. Use --dry-run to preview planned native module operations without a payload."
  [[ -d "${gateway_dir}" ]] || die "Gateway directory is missing: ${gateway_dir}. Run scripts/extract-windows-payload.sh first or pass --gateway-dir."
  [[ -d "${gateway_dir}/node_modules" ]] || die "Gateway node_modules is missing: ${gateway_dir}/node_modules. Task 5 requires an extracted staged gateway payload; run Task 3 extraction before rebuilding native modules."
  [[ -x "${node_bin}" ]] || die "Packaged Node is missing or not executable: ${node_bin}. Run scripts/fetch-node-linux.sh first or pass --node-bin."
  [[ -x "${npm_bin}" ]] || die "Packaged npm is missing or not executable: ${npm_bin}. Run scripts/fetch-node-linux.sh first or pass --node-bin."
}

build_npm_args() {
  npm_args=(--prefix "${gateway_dir}" --no-save --omit=dev --os=linux --cpu=x64 --libc=glibc)
  if [[ -n "${npm_cache_dir}" ]]; then
    npm_args+=(--cache "${npm_cache_dir}")
  fi
  if [[ "${offline}" -eq 1 ]]; then
    npm_args+=(--offline)
  fi
}

detect_node_abi() {
  if [[ -n "${node_abi}" ]]; then
    return 0
  fi
  if [[ -x "${node_bin}" ]]; then
    node_abi="$(${node_bin} -p 'process.versions.modules')" || die "Unable to detect Node ABI using ${node_bin}. Pass --node-abi explicitly."
  fi
}

detect_electron_version() {
  if [[ -x "${electron_bin}" ]]; then
    electron_version="$(ELECTRON_RUN_AS_NODE=1 "${electron_bin}" -p 'process.versions.electron')" \
      || die "Unable to detect Electron version using ${electron_bin}. Pass --electron-version explicitly."
    return 0
  fi
  if [[ -z "${electron_version}" ]]; then
    electron_version="$(manifest_value runtimePlaceholders.electronVersion 2>/dev/null || true)"
  fi
}

detect_electron_abi() {
  if [[ -n "${electron_abi}" ]]; then
    return 0
  fi
  if [[ -x "${electron_bin}" ]]; then
    electron_abi="$(ELECTRON_RUN_AS_NODE=1 "${electron_bin}" -p 'process.versions.modules')" \
      || die "Unable to detect Electron ABI using ${electron_bin}. Pass --electron-abi explicitly."
  fi
  if [[ -z "${electron_abi}" ]]; then
    die "Electron ABI is required for better-sqlite3. Ensure ${electron_bin} is executable or pass --electron-abi."
  fi
}

require_electron_rebuild_context() {
  if [[ -x "${electron_bin}" ]]; then
    detect_electron_version
    detect_electron_abi
    return 0
  fi

  if [[ -n "${electron_abi}" && -n "${electron_version}" ]]; then
    log_action "Electron binary is not executable; using explicit Electron version ${electron_version} and ABI ${electron_abi}"
    write_report_line "Electron binary unavailable; using explicit Electron version ${electron_version} and ABI ${electron_abi}"
    return 0
  fi

  die "Electron binary is missing or not executable: ${electron_bin}. Run scripts/fetch-electron-linux.sh first, or pass both --electron-version and --electron-abi."
}

detect_better_sqlite3_package() {
  if [[ -n "${better_sqlite3_package}" ]]; then
    return 0
  fi

  local module_package
  for module_package in \
    "${gateway_dir}/node_modules/better-sqlite3/package.json" \
    "${WINDOWS_PAYLOAD_CACHE}/payload/resources/gateway/node_modules/better-sqlite3/package.json"; do
    if [[ -f "${module_package}" ]]; then
      local detected_version
      detected_version="$(package_json_version "${module_package}")" || die "Unable to read better-sqlite3 version from ${module_package}."
      [[ -n "${detected_version}" ]] || die "better-sqlite3 package.json is missing a version: ${module_package}."
      better_sqlite3_package="better-sqlite3@${detected_version}"
      return 0
    fi
  done

  local gateway_package="${gateway_dir}/package.json"
  if [[ -f "${gateway_package}" ]]; then
    local detected_range
    detected_range="$(package_json_dependency "${gateway_package}" "better-sqlite3")" || die "Unable to read better-sqlite3 dependency from ${gateway_package}."
    [[ -n "${detected_range}" ]] || die "better-sqlite3 is missing from staged node_modules and ${gateway_package} dependencies; cannot choose a safe install version."
    case "${detected_range}" in
      file:*|link:*|workspace:*|git:*|http:*|https:*)
        die "Unsupported better-sqlite3 dependency spec in staged gateway package.json: ${detected_range}. Provide a staged node_modules/better-sqlite3 package instead."
        ;;
    esac
    better_sqlite3_package="better-sqlite3@${detected_range}"
    return 0
  fi

  die "better-sqlite3 is missing from staged node_modules and no staged gateway package.json exists to infer an install version."
}

report_abi_locations() {
  local module_dir="${gateway_dir}/node_modules/better-sqlite3"
  log_action "better-sqlite3 ABI context:"
  write_report_line "better-sqlite3 ABI context:"
  if [[ -n "${node_abi}" ]]; then
    log_action "- Node ABI: ${node_abi}"
    write_report_line "- Node ABI: ${node_abi}"
  else
    log_action "- Node ABI: unknown (provide --node-bin or --node-abi)"
    write_report_line "- Node ABI: unknown"
  fi
  if [[ -n "${electron_abi}" ]]; then
    log_action "- Electron ABI: ${electron_abi}"
    write_report_line "- Electron ABI: ${electron_abi}"
  elif [[ -n "${electron_version}" ]]; then
    log_action "- Electron version: ${electron_version}; pass --electron-abi if an Electron ABI-specific better-sqlite3 build is required"
    write_report_line "- Electron version: ${electron_version}; Electron ABI not provided"
  else
    log_action "- Electron ABI: not provided; pass --electron-abi when the Electron process loads better-sqlite3 directly"
    write_report_line "- Electron ABI: not provided"
  fi

  if [[ -d "${module_dir}/build" ]]; then
    local abi_dirs
    abi_dirs="$(find "${module_dir}/build" -maxdepth 1 -type d -name 'Release-abi-*' -printf '%P\n' | LC_ALL=C sort || true)"
    if [[ -n "${abi_dirs}" ]]; then
      log_action "Existing better-sqlite3 Release-abi directories:"
      write_report_line "Existing better-sqlite3 Release-abi directories:"
      printf '%s\n' "${abi_dirs}"
      if [[ -n "${native_report}" ]]; then
        printf '%s\n' "${abi_dirs}" >>"${native_report}"
      fi
    else
      log_action "Existing better-sqlite3 Release-abi directories: none"
      write_report_line "Existing better-sqlite3 Release-abi directories: none"
    fi
  else
    log_action "Existing better-sqlite3 build directory: none"
    write_report_line "Existing better-sqlite3 build directory: none"
  fi
}

backup_dual_abi_loader() {
  local target="${gateway_dir}/node_modules/better-sqlite3/lib/database.js"
  dual_abi_loader_backup="${cache_dir}/better-sqlite3-database.dual-abi.js"
  if [[ -f "${target}" ]] && grep -F "hilo-agent-opencode patch: dual-ABI binding loader" "${target}" >/dev/null 2>&1; then
    mkdir -p "$(dirname "${dual_abi_loader_backup}")"
    cp -f "${target}" "${dual_abi_loader_backup}"
    log_action "Backed up better-sqlite3 dual-ABI loader patch"
    write_report_line "Backed up better-sqlite3 dual-ABI loader patch"
  fi
}

better_sqlite3_release_node() {
  printf '%s\n' "${gateway_dir}/node_modules/better-sqlite3/build/Release/better_sqlite3.node"
}

better_sqlite3_abi_node() {
  local abi="$1"
  printf '%s\n' "${gateway_dir}/node_modules/better-sqlite3/build/Release-abi-${abi}/better_sqlite3.node"
}

copy_release_to_abi_dir() {
  local abi="$1"
  local label="$2"
  local mode="${3:-keep}"
  local release_node
  release_node="$(better_sqlite3_release_node)"
  [[ -f "${release_node}" ]] || die "Cannot snapshot better-sqlite3 ${label} ABI ${abi}; missing ${release_node}"
  local abi_node abi_dir
  abi_node="$(better_sqlite3_abi_node "${abi}")"
  if [[ -f "${abi_node}" && "${mode}" != "overwrite" ]]; then
    log_action "Existing better-sqlite3 ${label} ABI ${abi} snapshot found at ${abi_node}"
    write_report_line "Existing better-sqlite3 ${label} ABI ${abi} snapshot: ${abi_node}"
    return 0
  fi
  abi_dir="$(dirname "${abi_node}")"
  mkdir -p "${abi_dir}"
  cp -f "${release_node}" "${abi_node}"
  log_action "Snapshotted better-sqlite3 ${label} ABI ${abi} to ${abi_node}"
  write_report_line "Snapshotted better-sqlite3 ${label} ABI ${abi}: ${abi_node}"
}

restore_dual_abi_loader() {
  local target="${gateway_dir}/node_modules/better-sqlite3/lib/database.js"
  local source=""
  local candidate
  for candidate in \
    "${dual_abi_loader_backup}" \
    "${target}" \
    "${WINDOWS_PAYLOAD_CACHE}/payload/resources/gateway/node_modules/better-sqlite3/lib/database.js"; do
    if [[ -f "${candidate}" ]] && grep -F "hilo-agent-opencode patch: dual-ABI binding loader" "${candidate}" >/dev/null 2>&1; then
      source="${candidate}"
      break
    fi
  done

  if [[ -z "${source}" ]]; then
    log_action "better-sqlite3 dual-ABI loader patch not found; keeping installed database.js"
    write_report_line "better-sqlite3 dual-ABI loader patch not found; kept installed database.js"
    return 0
  fi

  mkdir -p "$(dirname "${target}")"
  if [[ "${source}" != "${target}" ]]; then
    cp -f "${source}" "${target}"
  fi
  log_action "Restored better-sqlite3 dual-ABI loader patch"
  write_report_line "Restored better-sqlite3 dual-ABI loader patch"
}

remove_forbidden_artifacts() {
  local forbidden
  forbidden="$(find_forbidden_windows_artifacts "${gateway_dir}/node_modules")"
  if [[ -z "${forbidden}" ]]; then
    log_action "Forbidden Windows native artifacts before rebuild: none"
    write_report_line "Forbidden Windows native artifacts before rebuild: none"
    return 0
  fi

  log_action "Forbidden Windows native artifacts before rebuild:"
  printf '%s\n' "${forbidden}"
  write_report_line "Forbidden Windows native artifacts before rebuild:"
  if [[ -n "${native_report}" ]]; then
    printf '%s\n' "${forbidden}" >>"${native_report}"
  fi

  if [[ "${dry_run}" -eq 1 ]]; then
    while IFS= read -r artifact; do
      [[ -n "${artifact}" ]] || continue
      log_action "DRY-RUN: would remove $(relative_path "${gateway_dir}/node_modules" "${artifact}")"
    done <<<"${forbidden}"
    return 0
  fi

  while IFS= read -r artifact; do
    [[ -n "${artifact}" ]] || continue
    rm -rf "${artifact}"
  done <<<"${forbidden}"
}

install_linux_packages() {
  detect_better_sqlite3_package
  build_npm_args
  log_action "Installing Linux native package set into ${gateway_dir}/node_modules"
  run_npm install "${npm_args[@]}" \
    "${better_sqlite3_package}" \
    "sharp@${sharp_version}" \
    "${sharp_linux_package}" \
    "${sharp_libvips_package}" \
    "${xxhash_package}" \
    "${xxhash_linux_package}"
}

rebuild_better_sqlite3() {
  if [[ ! -d "${gateway_dir}/node_modules/better-sqlite3" ]]; then
    detect_better_sqlite3_package
    build_npm_args
    log_action "Installing ${better_sqlite3_package} into staged node_modules for Linux packaged Node ABI${node_abi:+ ${node_abi}}"
    run_npm install "${npm_args[@]}" "${better_sqlite3_package}" --build-from-source
  else
    detect_better_sqlite3_package
    build_npm_args
    log_action "Rebuilding ${better_sqlite3_package} for packaged Node ABI${node_abi:+ ${node_abi}}"
    run_npm rebuild "${npm_args[@]}" better-sqlite3 --build-from-source
  fi

  if [[ -n "${electron_abi}" || -n "${electron_version}" ]]; then
    log_action "Electron ABI requested for better-sqlite3; npm rebuild needs Electron headers in the staged build environment."
    log_action "Use --electron-abi to record the expected ABI and ensure an Electron-targeted Release-abi-${electron_abi:-<abi>} binding exists before Task 6 if Electron loads this module directly."
    write_report_line "better-sqlite3 Electron ABI requested: ${electron_abi:-unknown}; verify Electron-targeted binding before assembly"
  fi
}

rebuild_better_sqlite3_for_electron() {
  [[ -n "${electron_abi}" ]] || return 0
  [[ -n "${electron_version}" ]] || die "Electron ABI ${electron_abi} requires --electron-version so better-sqlite3 can be rebuilt against Electron headers."
  detect_better_sqlite3_package
  build_npm_args
  log_action "Rebuilding ${better_sqlite3_package} for Electron ${electron_version} ABI ${electron_abi}"
  run_npm rebuild "${npm_args[@]}" better-sqlite3 --build-from-source --runtime=electron --target="${electron_version}" --dist-url=https://electronjs.org/headers
  copy_release_to_abi_dir "${electron_abi}" "Electron" "overwrite"
}

verify_requires() {
  if [[ ! -x "${node_bin}" ]]; then
    die "Packaged Node is missing or not executable: ${node_bin}. Run scripts/fetch-node-linux.sh first or pass --node-bin."
  fi
  local module_name
  for module_name in better-sqlite3 sharp @node-rs/xxhash; do
    NODE_PATH="${gateway_dir}/node_modules" "${node_bin}" -e "require('${module_name}');" \
      || die "Staged native module cannot be required with packaged Node (${node_bin}): ${module_name}"
    log_action "OK require: ${module_name}"
    write_report_line "OK require: ${module_name}"
  done
}

verify_electron_requires() {
  [[ -n "${electron_abi}" ]] || return 0
  [[ -x "${electron_bin}" ]] || die "Electron binary is missing or not executable: ${electron_bin}. Run scripts/fetch-electron-linux.sh first or pass --electron-bin."
  NODE_PATH="${gateway_dir}/node_modules" ELECTRON_RUN_AS_NODE=1 "${electron_bin}" -e "require('better-sqlite3');" \
    || die "Staged native module cannot be required with packaged Electron (${electron_bin}): better-sqlite3"
  log_action "OK Electron require: better-sqlite3"
  write_report_line "OK Electron require: better-sqlite3"
}

dual_abi_loader_ready() {
  grep -F "hilo-agent-opencode patch: dual-ABI binding loader" \
    "${gateway_dir}/node_modules/better-sqlite3/lib/database.js" >/dev/null 2>&1
}

abi_snapshot_ready() {
  local abi="$1"
  [[ -f "$(better_sqlite3_abi_node "${abi}")" ]]
}

electron_module_ready() {
  [[ -n "${electron_abi}" ]] || return 1
  [[ -x "${electron_bin}" ]] || return 1
  abi_snapshot_ready "${electron_abi}" || return 1
  NODE_PATH="${gateway_dir}/node_modules" ELECTRON_RUN_AS_NODE=1 "${electron_bin}" -e "require('better-sqlite3');" >/dev/null 2>&1
}

native_modules_fully_ready() {
  [[ -n "${node_abi}" ]] || return 1
  native_modules_ready || return 1
  abi_snapshot_ready "${node_abi}" || return 1
  electron_module_ready || return 1
  dual_abi_loader_ready || return 1
}

native_modules_ready() {
  [[ -x "${node_bin}" ]] || return 1
  local module_name
  for module_name in better-sqlite3 sharp @node-rs/xxhash; do
    NODE_PATH="${gateway_dir}/node_modules" "${node_bin}" -e "require('${module_name}');" >/dev/null 2>&1 || return 1
  done
}

write_native_inventory() {
  ensure_dir "${cache_dir}"
  native_report="${cache_dir}/native-modules-report.txt"
  : >"${native_report}"
  write_report_line "MiniMax Hub native module rebuild report"
  write_report_line "Payload: ${payload_dir}"
  write_report_line "Gateway: ${gateway_dir}"
  write_report_line "Node: ${node_bin}"
  write_report_line ""

  if [[ -d "${gateway_dir}/node_modules" ]]; then
    write_sorted_inventory "${gateway_dir}/node_modules" "${cache_dir}/native-node-modules-inventory.txt"
    write_sha256_report "${gateway_dir}/node_modules" "${cache_dir}/native-node-modules-sha256.txt"
    write_report_line "Native .node files:"
    local native_files
    native_files="$(find "${gateway_dir}/node_modules" -type f -name '*.node' -printf '%P\n' | LC_ALL=C sort || true)"
    if [[ -n "${native_files}" ]]; then
      printf '%s\n' "${native_files}" >>"${native_report}"
    else
      write_report_line "none"
    fi
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --payload-dir)
      [[ $# -ge 2 ]] || die "--payload-dir requires a path."
      payload_dir="$2"
      shift 2
      ;;
    --gateway-dir)
      [[ $# -ge 2 ]] || die "--gateway-dir requires a path."
      gateway_dir="$2"
      shift 2
      ;;
    --cache-dir)
      [[ $# -ge 2 ]] || die "--cache-dir requires a path."
      cache_dir="$2"
      shift 2
      ;;
    --node-bin)
      [[ $# -ge 2 ]] || die "--node-bin requires a path."
      node_bin="$2"
      shift 2
      ;;
    --electron-bin)
      [[ $# -ge 2 ]] || die "--electron-bin requires a path."
      electron_bin="$2"
      shift 2
      ;;
    --node-abi)
      [[ $# -ge 2 ]] || die "--node-abi requires a value."
      node_abi="$2"
      shift 2
      ;;
    --electron-abi)
      [[ $# -ge 2 ]] || die "--electron-abi requires a value."
      electron_abi="$2"
      shift 2
      ;;
    --electron-version)
      [[ $# -ge 2 ]] || die "--electron-version requires a value."
      electron_version="$2"
      shift 2
      ;;
    --npm-cache)
      [[ $# -ge 2 ]] || die "--npm-cache requires a path."
      npm_cache_dir="$2"
      shift 2
      ;;
    --offline)
      offline=1
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

if [[ -z "${gateway_dir}" ]]; then
  gateway_dir="${payload_dir}/resources/gateway"
fi
if [[ -z "${node_bin}" ]]; then
  node_bin="${payload_dir}/node/bin/node"
fi
if [[ -z "${electron_bin}" ]]; then
  electron_bin="${payload_dir}/electron"
fi
node_bin_dir="$(dirname "${node_bin}")"
npm_bin="${node_bin_dir}/npm"
if [[ -z "${npm_cache_dir}" ]]; then
  npm_cache_dir="${cache_dir}/npm"
fi

log_action "Native module rebuild plan"
log_action "- payload: ${payload_dir}"
log_action "- gateway: ${gateway_dir}"
log_action "- node_modules: ${gateway_dir}/node_modules"
log_action "- node: ${node_bin}"
log_action "- electron: ${electron_bin}${electron_version:+ (${electron_version})}"
log_action "- npm: ${npm_bin}"
log_action "- cache: ${cache_dir}"
log_action "- npm cache: ${npm_cache_dir}"
log_action "- npm mode: $([[ "${offline}" -eq 1 ]] && echo offline || echo online)"
log_action "- packages: sharp@${sharp_version}, ${sharp_linux_package}, ${sharp_libvips_package}, ${xxhash_package}, ${xxhash_linux_package}"

if [[ "${dry_run}" -eq 1 ]]; then
  log_action "Dry run only; npm will not run and files will not be changed."
  if [[ -d "${gateway_dir}/node_modules" ]]; then
    remove_forbidden_artifacts
    report_abi_locations
    if [[ -d "${gateway_dir}/node_modules/better-sqlite3" || -f "${WINDOWS_PAYLOAD_CACHE}/payload/resources/gateway/node_modules/better-sqlite3/package.json" || -f "${gateway_dir}/package.json" ]]; then
      install_linux_packages
    else
      log_action "better-sqlite3: no staged module, cached source module, or gateway package.json found; non-dry-run would fail before selecting an install version."
    fi
  else
    log_action "Staged node_modules is absent; non-dry-run would fail clearly before npm."
    log_action "better-sqlite3: would rebuild an existing staged module or install a version inferred from staged gateway package.json."
  fi
  exit 0
fi

require_staged_prerequisites
ensure_dir "${cache_dir}"
ensure_dir "${npm_cache_dir}"
write_native_inventory
detect_node_abi
require_electron_rebuild_context
detect_better_sqlite3_package
report_abi_locations
backup_dual_abi_loader
remove_forbidden_artifacts
if native_modules_fully_ready; then
  log_action "Existing Linux native modules already load with packaged Node and Electron; skipping npm install and rebuild"
  write_report_line "Existing Linux native modules already load with packaged Node and Electron; skipped npm install and rebuild"
elif native_modules_ready; then
  log_action "Existing Linux native modules already load with packaged Node; skipping npm install"
  write_report_line "Existing Linux native modules already load with packaged Node; skipped npm install"
  restore_dual_abi_loader
  copy_release_to_abi_dir "${node_abi}" "Node"
  rebuild_better_sqlite3_for_electron
  restore_dual_abi_loader
else
  install_linux_packages
  restore_dual_abi_loader
  copy_release_to_abi_dir "${node_abi}" "Node"
  rebuild_better_sqlite3_for_electron
  restore_dual_abi_loader
fi

remaining_forbidden="$(find_forbidden_windows_artifacts "${gateway_dir}/node_modules")"
if [[ -n "${remaining_forbidden}" ]]; then
  printf '%s\n' "${remaining_forbidden}" >&2
  die "Forbidden Windows native artifacts remain in staged gateway node_modules after rebuild."
fi

write_native_inventory
report_abi_locations
verify_requires
verify_electron_requires

info "Wrote ${native_report}"
info "Native module rebuild completed for ${gateway_dir}/node_modules"
