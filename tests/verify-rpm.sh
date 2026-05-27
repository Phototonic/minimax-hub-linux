#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/testlib.sh"

if [[ $# -gt 0 ]]; then
  rpm_path="$1"
else
  rpm_path=""
  while IFS= read -r candidate; do
    rpm_path="${candidate}"
    break
  done < <(find "${PROJECT_ROOT}/output" -maxdepth 1 -type f -name "${PACKAGE_NAME}-${VERSION}-1*.x86_64.rpm" 2>/dev/null | sort)
  rpm_path="${rpm_path:-${PROJECT_ROOT}/output/${PACKAGE_NAME}-${VERSION}-1.x86_64.rpm}"
fi
[[ -f "${rpm_path}" ]] || fail "RPM package artifact is missing: ${rpm_path}. Build it with build-rpm.sh before running this verifier."
[[ -s "${rpm_path}" ]] || fail "RPM package artifact is empty: ${rpm_path}"
require_command rpm

info="$(rpm -qpi "${rpm_path}")"
files="$(rpm -qpl "${rpm_path}")"
requires="$(rpm -qp --requires "${rpm_path}")"
scripts="$(rpm -qp --scripts "${rpm_path}")"

assert_contains "${info}" "Name        : ${PACKAGE_NAME}" "rpm -qpi output"
assert_contains "${info}" "Version     : ${VERSION}" "rpm -qpi output"
assert_contains "${info}" "Architecture: x86_64" "rpm -qpi output"
assert_contains "${files}" "/opt/minimax-hub" "rpm -qpl output"
assert_contains "${files}" "/opt/minimax-hub/resources/app.asar" "rpm -qpl output"
assert_contains "${files}" "/opt/minimax-hub/electron" "rpm -qpl output"
assert_contains "${files}" "/opt/minimax-hub/node/bin/node" "rpm -qpl output"
assert_contains "${files}" "/opt/minimax-hub/resources/opencode/opencode" "rpm -qpl output"
assert_contains "${files}" "/usr/bin/minimax-hub" "rpm -qpl output"
assert_contains "${files}" "/usr/share/applications/minimax-hub.desktop" "rpm -qpl output"
assert_contains "${files}" "/usr/share/icons/hicolor/256x256/apps/minimax-hub.png" "rpm -qpl output"
assert_contains "${files}" "/opt/minimax-hub/chrome-sandbox" "rpm -qpl output"
[[ "${files}" != *"/opt/minimax-hub/resources/app-update.yml"* ]] || fail "RPM package must not include upstream updater metadata: /opt/minimax-hub/resources/app-update.yml"
[[ "${files}" != *"/opt/minimax-hub/app-update.yml"* ]] || fail "RPM package must not include upstream updater metadata: /opt/minimax-hub/app-update.yml"
assert_contains "${requires}" "gtk3" "rpm -qp --requires output"
assert_contains "${requires}" "nss" "rpm -qp --requires output"
assert_contains "${requires}" "desktop-file-utils" "rpm -qp --requires output"
assert_contains "${scripts}" "update-desktop-database" "rpm -qp --scripts output"
assert_contains "${scripts}" "xdg-mime default minimax-hub.desktop x-scheme-handler/minimax-hub" "rpm -qp --scripts output"
assert_contains "${scripts}" "gio mime x-scheme-handler/minimax-hub minimax-hub.desktop" "rpm -qp --scripts output"
assert_contains "${scripts}" "chrome-sandbox" "rpm -qp --scripts output"

if command -v rpm2cpio >/dev/null 2>&1 && command -v cpio >/dev/null 2>&1; then
  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "${tmp_dir}"' EXIT
  (cd "${tmp_dir}" && rpm2cpio "${rpm_path}" | cpio -idm --quiet)
  assert_file_contains "${tmp_dir}/usr/bin/minimax-hub" "export ELECTRON_FORCE_IS_PACKAGED=true"
  validate_desktop_file "${tmp_dir}/usr/share/applications/minimax-hub.desktop"
  require_file "${tmp_dir}/usr/share/icons/hicolor/256x256/apps/minimax-hub.png"
  assert_no_forbidden_windows_artifacts "${tmp_dir}/opt/minimax-hub"
  assert_no_linux_updater_metadata "${tmp_dir}/opt/minimax-hub"
elif command -v bsdtar >/dev/null 2>&1; then
  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "${tmp_dir}"' EXIT
  bsdtar -xf "${rpm_path}" -C "${tmp_dir}"
  assert_file_contains "${tmp_dir}/usr/bin/minimax-hub" "export ELECTRON_FORCE_IS_PACKAGED=true"
  validate_desktop_file "${tmp_dir}/usr/share/applications/minimax-hub.desktop"
  require_file "${tmp_dir}/usr/share/icons/hicolor/256x256/apps/minimax-hub.png"
  assert_no_forbidden_windows_artifacts "${tmp_dir}/opt/minimax-hub"
  assert_no_linux_updater_metadata "${tmp_dir}/opt/minimax-hub"
else
  note "rpm2cpio+cpio and bsdtar are unavailable; skipping extracted RPM payload inspection after metadata checks."
fi

echo "RPM package verification passed: ${rpm_path}"
