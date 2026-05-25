#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/scripts/common.sh"

DEBIAN_ROOT="${PROJECT_ROOT}/linux-build"
DEBIAN_CONTROL="${DEBIAN_ROOT}/DEBIAN/control"
PAYLOAD_DIR="${DEFAULT_PAYLOAD_DIR}"
OUTPUT_DIR="${PROJECT_ROOT}/output"
ARCHITECTURE="amd64"
VERSION="$(tr -d '[:space:]' < "${VERSION_FILE}")"
DEB_PATH="${OUTPUT_DIR}/${PACKAGE_NAME}_${VERSION}_${ARCHITECTURE}.deb"

record_missing() {
  missing_items+=("$1")
}

require_file_present() {
  local path="$1"
  local label="$2"
  [[ -s "${path}" ]] || record_missing "${label}: ${path}"
}

require_dir_present() {
  local path="$1"
  local label="$2"
  [[ -d "${path}" ]] || record_missing "${label}: ${path}"
}

require_executable_present() {
  local path="$1"
  local label="$2"
  if [[ ! -s "${path}" ]]; then
    record_missing "${label}: ${path}"
  elif [[ ! -x "${path}" ]]; then
    record_missing "${label} is not executable: ${path}"
  fi
}


normalize_text_file() {
  local file_path="$1"
  [[ -f "${file_path}" ]] || return 0
  local temp_file
  temp_file="$(mktemp "${file_path}.XXXXXX")"
  tr -d '\r' <"${file_path}" >"${temp_file}"
  cat "${temp_file}" >"${file_path}"
  rm -f "${temp_file}"
}

normalize_payload_text_files() {
  [[ -d "${PAYLOAD_DIR}" ]] || return 0
  local file_path
  while IFS= read -r -d '' file_path; do
    normalize_text_file "${file_path}"
  done < <(find "${PAYLOAD_DIR}" -type f \( \
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

set_executable_if_present() {
  local file_path="$1"
  local mode="${2:-0755}"
  [[ -e "${file_path}" ]] || return 0
  chmod "${mode}" "${file_path}"
}

normalize_debian_package() {
  normalize_text_file "${DEBIAN_CONTROL}"
  normalize_text_file "${DEBIAN_ROOT}/DEBIAN/postinst"
  normalize_text_file "${DEBIAN_ROOT}/DEBIAN/prerm"
  normalize_text_file "${DEBIAN_ROOT}/DEBIAN/postrm"
  normalize_text_file "${DEBIAN_ROOT}/usr/bin/${PACKAGE_NAME}"
  normalize_text_file "${DEBIAN_ROOT}/usr/share/applications/${PACKAGE_NAME}.desktop"
  normalize_payload_text_files

  set_executable_if_present "${DEBIAN_ROOT}/usr/bin/${PACKAGE_NAME}"
  set_executable_if_present "${DEBIAN_ROOT}/DEBIAN/postinst"
  set_executable_if_present "${DEBIAN_ROOT}/DEBIAN/prerm"
  set_executable_if_present "${DEBIAN_ROOT}/DEBIAN/postrm"
  set_executable_if_present "${PAYLOAD_DIR}/electron"
  set_executable_if_present "${PAYLOAD_DIR}/node/bin/node"
  set_executable_if_present "${PAYLOAD_DIR}/resources/opencode/opencode"
  set_executable_if_present "${PAYLOAD_DIR}/chrome-sandbox" 4755
}

verify_no_forbidden_windows_artifacts() {
  local forbidden
  forbidden="$(find_forbidden_windows_artifacts "${PAYLOAD_DIR}")"
  if [[ -n "${forbidden}" ]]; then
    printf '%s\n' "${forbidden}" >&2
    die "Forbidden Windows artifacts remain in payload: ${PAYLOAD_DIR}"
  fi
}

validate_control_metadata() {
  require_file_present "${DEBIAN_CONTROL}" "Debian control file"
  grep -Fx "Package: ${PACKAGE_NAME}" "${DEBIAN_CONTROL}" >/dev/null || die "${DEBIAN_CONTROL} must declare Package: ${PACKAGE_NAME}"
  grep -Fx "Version: ${VERSION}" "${DEBIAN_CONTROL}" >/dev/null || die "${DEBIAN_CONTROL} must declare Version: ${VERSION} from ${VERSION_FILE}"
  grep -Fx "Architecture: ${ARCHITECTURE}" "${DEBIAN_CONTROL}" >/dev/null || die "${DEBIAN_CONTROL} must declare Architecture: ${ARCHITECTURE}"
}

validate_package_payload() {
  missing_items=()

  require_dir_present "${DEBIAN_ROOT}" "Debian package root"
  require_dir_present "${PAYLOAD_DIR}" "MiniMax Hub payload directory"
  require_file_present "${PAYLOAD_DIR}/resources/app.asar" "Application archive"
  require_executable_present "${PAYLOAD_DIR}/electron" "Electron Linux runtime"
  require_executable_present "${PAYLOAD_DIR}/node/bin/node" "Node Linux runtime"
  require_executable_present "${PAYLOAD_DIR}/resources/opencode/opencode" "OpenCode Linux binary"
  require_executable_present "${PAYLOAD_DIR}/chrome-sandbox" "Electron chrome-sandbox"
  require_executable_present "${DEBIAN_ROOT}/usr/bin/${PACKAGE_NAME}" "Package launcher"
  require_file_present "${DEBIAN_ROOT}/usr/share/applications/${PACKAGE_NAME}.desktop" "Desktop entry"
  require_executable_present "${DEBIAN_ROOT}/DEBIAN/postinst" "postinst maintainer script"
  require_executable_present "${DEBIAN_ROOT}/DEBIAN/prerm" "prerm maintainer script"
  require_executable_present "${DEBIAN_ROOT}/DEBIAN/postrm" "postrm maintainer script"

  if [[ ${#missing_items[@]} -gt 0 ]]; then
    printf '%s\n' 'Error: Cannot build Debian package; required payload files are missing or incomplete:' >&2
    printf 'Error: - %s\n' "${missing_items[@]}" >&2
    printf '%s\n' 'Error: Run scripts/assemble-linux-payload.sh after staging Linux runtime prerequisites, then retry build.sh.' >&2
    exit 1
  fi
}

prepare_permissions() {
  chmod 0755 "${DEBIAN_ROOT}/usr/bin/${PACKAGE_NAME}"
  chmod 0755 "${DEBIAN_ROOT}/DEBIAN/postinst" "${DEBIAN_ROOT}/DEBIAN/prerm" "${DEBIAN_ROOT}/DEBIAN/postrm"
  chmod 0755 "${PAYLOAD_DIR}/electron" "${PAYLOAD_DIR}/node/bin/node" "${PAYLOAD_DIR}/resources/opencode/opencode"
  chmod 4755 "${PAYLOAD_DIR}/chrome-sandbox"
}

build_deb() {
  rm -f "${DEB_PATH}"
  ensure_dir "${OUTPUT_DIR}"
  dpkg-deb --root-owner-group --build "${DEBIAN_ROOT}" "${DEB_PATH}"
}

validate_control_metadata
normalize_debian_package
validate_package_payload
verify_no_forbidden_windows_artifacts
prepare_permissions
require_command dpkg-deb
build_deb
bash "${PROJECT_ROOT}/tests/verify-deb.sh" "${DEB_PATH}"

info "Debian package created: ${DEB_PATH}"
