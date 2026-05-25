#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/testlib.sh"

deb_path="${1:-${PROJECT_ROOT}/output/${PACKAGE_NAME}_${VERSION}_amd64.deb}"
[[ -f "${deb_path}" ]] || fail "Debian package artifact is missing: ${deb_path}. Build it with build.sh before running this verifier."
[[ -s "${deb_path}" ]] || fail "Debian package artifact is empty: ${deb_path}"
require_command dpkg-deb

info="$(dpkg-deb --info "${deb_path}")"
contents="$(dpkg-deb --contents "${deb_path}")"

assert_contains "${info}" "Package: ${PACKAGE_NAME}" "dpkg-deb --info output"
assert_contains "${info}" "Version: ${VERSION}" "dpkg-deb --info output"
assert_contains "${info}" "Architecture: amd64" "dpkg-deb --info output"
assert_contains "${info}" "Maintainer:" "dpkg-deb --info output"
assert_contains "${info}" "postinst" "dpkg-deb --info output"
assert_contains "${info}" "prerm" "dpkg-deb --info output"
assert_contains "${info}" "postrm" "dpkg-deb --info output"
assert_contains "${contents}" "./opt/minimax-hub/" "dpkg-deb --contents output"
assert_contains "${contents}" "./opt/minimax-hub/resources/app.asar" "dpkg-deb --contents output"
assert_contains "${contents}" "./opt/minimax-hub/electron" "dpkg-deb --contents output"
assert_contains "${contents}" "./opt/minimax-hub/node/bin/node" "dpkg-deb --contents output"
assert_contains "${contents}" "./opt/minimax-hub/resources/opencode/opencode" "dpkg-deb --contents output"
assert_contains "${contents}" "./usr/bin/minimax-hub" "dpkg-deb --contents output"
assert_contains "${contents}" "./usr/share/applications/minimax-hub.desktop" "dpkg-deb --contents output"
assert_contains "${contents}" "./opt/minimax-hub/chrome-sandbox" "dpkg-deb --contents output"

if command -v dpkg >/dev/null 2>&1; then
  if ! dpkg --contents "${deb_path}" | awk '/\.\/opt\/minimax-hub\/chrome-sandbox$/ { if ($1 ~ /^-rws/) found=1 } END { exit(found ? 0 : 1) }'; then
    fail "chrome-sandbox must be packaged with setuid executable permissions or fixed by maintainer scripts."
  fi
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT
dpkg-deb --extract "${deb_path}" "${tmp_dir}/root"
validate_desktop_file "${tmp_dir}/root/usr/share/applications/minimax-hub.desktop"
assert_no_forbidden_windows_artifacts "${tmp_dir}/root/opt/minimax-hub"

echo "Debian package verification passed: ${deb_path}"

