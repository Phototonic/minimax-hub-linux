#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${TEST_DIR}/.." && pwd)"
PACKAGE_NAME="minimax-hub"
VERSION="$(tr -d '[:space:]' < "${PROJECT_ROOT}/VERSION")"
PAYLOAD_DIR="${PROJECT_ROOT}/linux-build/opt/minimax-hub"
DEBIAN_CONTROL="${PROJECT_ROOT}/linux-build/DEBIAN/control"
DESKTOP_FILE="${PROJECT_ROOT}/linux-build/usr/share/applications/minimax-hub.desktop"
RPM_SPEC="${PROJECT_ROOT}/rpm/minimax-hub.spec"
LAUNCHER_FILE="${PROJECT_ROOT}/linux-build/usr/bin/minimax-hub"
INSTALLED_ICON="${PROJECT_ROOT}/linux-build/usr/share/icons/hicolor/256x256/apps/minimax-hub.png"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

note() {
  echo "INFO: $*" >&2
}

require_command() {
  local command_name="$1"
  command -v "${command_name}" >/dev/null 2>&1 || fail "Required command '${command_name}' is not available. Install it or run this verifier in an environment that provides it."
}

require_file() {
  local path="$1"
  [[ -f "${path}" ]] || fail "Required file is missing: ${path}"
  [[ -s "${path}" ]] || fail "Required file is empty: ${path}"
}

require_dir() {
  local path="$1"
  [[ -d "${path}" ]] || fail "Required directory is missing: ${path}"
}

require_executable() {
  local path="$1"
  require_file "${path}"
  [[ -x "${path}" ]] || fail "Required executable bit is missing: ${path}"
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local label="$3"
  [[ "${haystack}" == *"${needle}"* ]] || fail "${label} does not contain expected text: ${needle}"
}

assert_file_contains() {
  local path="$1"
  local needle="$2"
  require_file "${path}"
  grep -F -- "${needle}" "${path}" >/dev/null || fail "${path} does not contain expected text: ${needle}"
}

assert_file_matches() {
  local path="$1"
  local pattern="$2"
  require_file "${path}"
  grep -E -- "${pattern}" "${path}" >/dev/null || fail "${path} does not match expected pattern: ${pattern}"
}

assert_no_crlf() {
  local path="$1"
  require_file "${path}"
  if LC_ALL=C grep -q $'\r' "${path}"; then
    fail "CRLF line endings are not allowed in packaged text file: ${path}"
  fi
}

assert_no_crlf_in_tree() {
  local root_dir="$1"
  shift
  require_dir "${root_dir}"
  local file
  while IFS= read -r -d '' file; do
    assert_no_crlf "${file}"
  done < <(find "${root_dir}" -type f \( "$@" \) -print0)
}

assert_no_forbidden_windows_artifacts() {
  local root_dir="$1"
  require_dir "${root_dir}"
  local found
  found="$(find "${root_dir}" -type f \( -iname '*.exe' -o -iname '*.dll' -o -iname '*.bat' -o -iname '*.cmd' \) -print | sort)"
  [[ -z "${found}" ]] || fail "Forbidden Windows artifacts found under ${root_dir}: ${found}"
  found="$(find "${root_dir}" -type d \( -iname '*win32*' -o -iname '*windows*' -o -iname '*msvc*' \) -print | sort)"
  [[ -z "${found}" ]] || fail "Forbidden Windows-specific directories found under ${root_dir}: ${found}"
}

assert_no_linux_updater_metadata() {
  local root_dir="$1"
  [[ ! -e "${root_dir}/resources/app-update.yml" ]] || fail "Linux payload must not include upstream updater metadata: ${root_dir}/resources/app-update.yml"
  [[ ! -e "${root_dir}/app-update.yml" ]] || fail "Linux payload must not include upstream updater metadata: ${root_dir}/app-update.yml"
}

require_payload_not_empty() {
  local payload_dir="$1"
  require_dir "${payload_dir}"
  local real_file_count
  real_file_count="$(find "${payload_dir}" -type f ! -name '.gitkeep' | wc -l | tr -d '[:space:]')"
  [[ "${real_file_count}" -gt 0 ]] || fail "Payload directory is empty or contains only placeholders: ${payload_dir}"
}

read_desktop_value() {
  local path="$1"
  local key="$2"
  awk -F= -v key="${key}" '$1 == key { print substr($0, length(key) + 2); found=1; exit } END { if (!found) exit 1 }' "${path}"
}

require_desktop_key() {
  local path="$1"
  local key="$2"
  read_desktop_value "${path}" "${key}" >/dev/null || fail "Desktop file is missing required key: ${key}"
}

validate_desktop_file() {
  local path="$1"
  require_file "${path}"
  assert_no_crlf "${path}"

  if command -v desktop-file-validate >/dev/null 2>&1; then
    desktop-file-validate "${path}" || fail "desktop-file-validate rejected ${path}"
  else
    note "desktop-file-validate is unavailable; using fallback desktop parser."
    grep -Fx '[Desktop Entry]' "${path}" >/dev/null || fail "Desktop file is missing [Desktop Entry] header: ${path}"
    require_desktop_key "${path}" "Type"
    require_desktop_key "${path}" "Name"
    require_desktop_key "${path}" "Exec"
    require_desktop_key "${path}" "Icon"
    require_desktop_key "${path}" "Categories"
  fi

  local type exec_line icon_value mime_type schemes
  type="$(read_desktop_value "${path}" "Type")"
  [[ "${type}" == "Application" ]] || fail "Desktop Type must be Application, got: ${type}"
  exec_line="$(read_desktop_value "${path}" "Exec")"
  [[ "${exec_line}" == *"minimax-hub"* ]] || fail "Desktop Exec must launch minimax-hub, got: ${exec_line}"
  [[ "${exec_line}" == *"%u"* || "${exec_line}" == *"%U"* ]] || fail "Desktop Exec must include %u or %U protocol URL placeholder once protocol handlers are enabled."
  icon_value="$(read_desktop_value "${path}" "Icon")"
  [[ "${icon_value}" == "minimax-hub" ]] || fail "Desktop Icon must be minimax-hub, got: ${icon_value}"
  mime_type="$(read_desktop_value "${path}" "MimeType" 2>/dev/null || true)"
  [[ -n "${mime_type}" ]] || fail "Desktop file is missing MimeType protocol handler entries."
  [[ "${mime_type}" == *"x-scheme-handler/"* ]] || fail "Desktop MimeType must contain x-scheme-handler entries, got: ${mime_type}"
  schemes="$(read_desktop_value "${path}" "X-MiniMaxHub-Protocol-Schemes" 2>/dev/null || true)"
  [[ -n "${schemes}" ]] || fail "Desktop file is missing X-MiniMaxHub-Protocol-Schemes discovery marker."
  [[ "${schemes}" != "planned-discovery" ]] || fail "Desktop protocol schemes are still the planned-discovery placeholder."
}
