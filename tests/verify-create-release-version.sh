#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/testlib.sh"

assert_file_contains "${PROJECT_ROOT}/create-release.sh" "Run 'bash create-release.sh --publish' to rebuild and upload artifacts"
if grep -F -- "Run 'bash create-release.sh --publish \${VERSION}'" "${PROJECT_ROOT}/create-release.sh" >/dev/null; then
  fail "create-release.sh must not tell maintainers to pass an explicit version to --publish"
fi

run_version_only() {
  MINIMAX_HUB_RELEASE_VERSION_ONLY=1 \
    MINIMAX_HUB_RELEASE_NO_SYNC=1 \
    "$@"
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

source_dir="${tmp_dir}/MiniMax Hub"
mkdir -p "${source_dir}/resources/app.asar"
printf '%s\n' '{"version":"0.1.46"}' >"${source_dir}/resources/app.asar/package.json"

auto_output="$(MINIMAX_HUB_SOURCE="${source_dir}" run_version_only bash "${PROJECT_ROOT}/create-release.sh")"
assert_contains "${auto_output}" "Version: 0.1.46" "create-release auto-version output"
assert_contains "${auto_output}" "Tag: v0.1.46" "create-release auto-version output"

publish_output="$(MINIMAX_HUB_SOURCE="${source_dir}" run_version_only bash "${PROJECT_ROOT}/create-release.sh" --publish)"
assert_contains "${publish_output}" "Version: 0.1.46" "create-release publish auto-version output"
assert_contains "${publish_output}" "Tag: v0.1.46" "create-release publish auto-version output"

override_output="$(run_version_only bash "${PROJECT_ROOT}/create-release.sh" v0.2.0)"
assert_contains "${override_output}" "Version: 0.2.0" "create-release explicit-version output"
assert_contains "${override_output}" "Tag: v0.2.0" "create-release explicit-version output"

if command -v npx >/dev/null 2>&1; then
  packed_source="${tmp_dir}/Packed MiniMax Hub"
  packed_app="${tmp_dir}/packed-app"
  mkdir -p "${packed_source}/resources" "${packed_app}"
  printf '%s\n' '{"version":"0.3.0"}' >"${packed_app}/package.json"
  npx --yes @electron/asar pack "${packed_app}" "${packed_source}/resources/app.asar" >/dev/null
  packed_output="$(MINIMAX_HUB_SOURCE="${packed_source}" run_version_only bash "${PROJECT_ROOT}/create-release.sh")"
  assert_contains "${packed_output}" "Version: 0.3.0" "create-release packed-asar auto-version output"
else
  note "npx is unavailable; skipping packed app.asar auto-version fixture."
fi

echo "Create-release version verification passed"
