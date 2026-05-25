#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/scripts/common.sh"

VERSION="$(tr -d '[:space:]' < "${VERSION_FILE}")"
RPM_TOPDIR="${PROJECT_ROOT}/.cache/rpm"
RPM_BUILDROOT="${RPM_TOPDIR}/buildroot"
OUTPUT_DIR="${PROJECT_ROOT}/output"
SPEC_FILE="${PROJECT_ROOT}/rpm/minimax-hub.spec"
STAGED_ROOT="${PROJECT_ROOT}/linux-build"
PAYLOAD_DIR="${DEFAULT_PAYLOAD_DIR}"
RPM_ARTIFACT="${OUTPUT_DIR}/${PACKAGE_NAME}-${VERSION}-1.x86_64.rpm"

usage() {
  cat <<USAGE
Usage: $(basename "$0")

Builds a native RPM package from the assembled linux-build payload.

Required tools:
  rpmbuild  Build the RPM package
  rpm       Verify the built RPM metadata when available

USAGE
}

require_executable_file() {
  local path="$1"
  [[ -s "${path}" ]] || die "Expected non-empty executable file: ${path}"
  [[ -x "${path}" ]] || die "Expected executable bit on: ${path}"
}

validate_payload() {
  local missing=()

  [[ -d "${PAYLOAD_DIR}" ]] || missing+=("linux-build/opt/minimax-hub directory")
  if [[ -d "${PAYLOAD_DIR}" ]]; then
    local real_file_count
    real_file_count="$(find "${PAYLOAD_DIR}" -type f ! -name '.gitkeep' | wc -l | tr -d '[:space:]')"
    [[ "${real_file_count}" -gt 0 ]] || missing+=("linux-build/opt/minimax-hub real payload files")
  fi

  [[ -s "${PAYLOAD_DIR}/resources/app.asar" ]] || missing+=("opt/minimax-hub/resources/app.asar")
  [[ -s "${PAYLOAD_DIR}/resources/gateway/dist/main.js" ]] || missing+=("opt/minimax-hub/resources/gateway/dist/main.js")
  [[ -s "${PAYLOAD_DIR}/resources/mcp-tools/dist/main.js" ]] || missing+=("opt/minimax-hub/resources/mcp-tools/dist/main.js")
  [[ -d "${PAYLOAD_DIR}/resources/opencode/config" ]] || missing+=("opt/minimax-hub/resources/opencode/config")
  [[ -x "${PAYLOAD_DIR}/electron" ]] || missing+=("opt/minimax-hub/electron executable")
  [[ -x "${PAYLOAD_DIR}/chrome-sandbox" ]] || missing+=("opt/minimax-hub/chrome-sandbox executable")
  [[ -x "${PAYLOAD_DIR}/node/bin/node" ]] || missing+=("opt/minimax-hub/node/bin/node executable")
  [[ -x "${PAYLOAD_DIR}/resources/opencode/opencode" ]] || missing+=("opt/minimax-hub/resources/opencode/opencode executable")
  [[ -x "${PAYLOAD_DIR}/resources/ffmpeg/ffmpeg" ]] || missing+=("opt/minimax-hub/resources/ffmpeg/ffmpeg executable")
  [[ -x "${PAYLOAD_DIR}/resources/ffmpeg/ffprobe" ]] || missing+=("opt/minimax-hub/resources/ffmpeg/ffprobe executable")
  [[ -d "${PAYLOAD_DIR}/resources/gateway/node_modules" ]] || missing+=("opt/minimax-hub/resources/gateway/node_modules Linux-native modules")

  [[ -s "${STAGED_ROOT}/usr/share/applications/minimax-hub.desktop" ]] || missing+=("usr/share/applications/minimax-hub.desktop")
  [[ -x "${STAGED_ROOT}/usr/bin/minimax-hub" ]] || missing+=("usr/bin/minimax-hub executable")

  if [[ ${#missing[@]} -gt 0 ]]; then
    printf 'Error: RPM payload is incomplete; refusing to build a bogus package.\n' >&2
    printf 'Error: - %s\n' "${missing[@]}" >&2
    printf 'Error: Run scripts/assemble-linux-payload.sh and scripts/normalize-payload.sh after staging Linux runtimes and app resources.\n' >&2
    exit 1
  fi

  local forbidden
  forbidden="$(find_forbidden_windows_artifacts "${PAYLOAD_DIR}")"
  if [[ -n "${forbidden}" ]]; then
    printf '%s\n' "${forbidden}" >&2
    die "Forbidden Windows artifacts remain in RPM payload: ${PAYLOAD_DIR}"
  fi
}

validate_rpm_toolchain() {
  if ! command -v rpmbuild >/dev/null 2>&1; then
    die "Required command not found: rpmbuild. Install rpm-build, or run this script in a Fedora/RHEL/Rocky environment with RPM build tools."
  fi
}

prepare_rpm_tree() {
  rm -rf "${RPM_TOPDIR}"
  ensure_dir "${RPM_TOPDIR}/BUILD"
  ensure_dir "${RPM_TOPDIR}/BUILDROOT"
  ensure_dir "${RPM_TOPDIR}/RPMS"
  ensure_dir "${RPM_TOPDIR}/SOURCES"
  ensure_dir "${RPM_TOPDIR}/SPECS"
  ensure_dir "${RPM_TOPDIR}/SRPMS"
  ensure_dir "${OUTPUT_DIR}"
}

build_rpm() {
  rpmbuild -bb "${SPEC_FILE}" \
    --define "_topdir ${RPM_TOPDIR}" \
    --define "_version ${VERSION}" \
    --define "_staged_root ${STAGED_ROOT}" \
    --define "_payload_filelist ${RPM_TOPDIR}/minimax-hub-payload.files" \
    --define "__os_install_post %{nil}"
}

copy_artifact() {
  local built_rpm
  built_rpm="$(find "${RPM_TOPDIR}/RPMS" -type f -name "${PACKAGE_NAME}-${VERSION}-1*.x86_64.rpm" | sort | head -n 1)"
  [[ -n "${built_rpm}" ]] || die "rpmbuild completed but no RPM artifact was found under ${RPM_TOPDIR}/RPMS"
  cp "${built_rpm}" "${RPM_ARTIFACT}"
  info "Wrote ${RPM_ARTIFACT}"
}

verify_rpm_if_available() {
  if command -v rpm >/dev/null 2>&1; then
    "${PROJECT_ROOT}/tests/verify-rpm.sh" "${RPM_ARTIFACT}"
  else
    info "rpm command is unavailable; skipping tests/verify-rpm.sh. Install rpm to verify package metadata."
  fi
}

if [[ $# -gt 0 ]]; then
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
fi

validate_payload
validate_rpm_toolchain
prepare_rpm_tree
build_rpm
copy_artifact
verify_rpm_if_available
