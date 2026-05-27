#!/usr/bin/env bash
set -euo pipefail

# MiniMax Hub Linux Release Helper
# Runs the full Linux payload preparation and package build flow in Docker.
#
# Usage:
#   bash create-release.sh [VERSION]
#   bash create-release.sh --check
#   bash create-release.sh --resume
#   bash create-release.sh --publish [VERSION]
#
# If VERSION is omitted, VERSION is read from the VERSION file.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
die() { error "$*"; exit 1; }

CHECK_ONLY=0
RESUME=0
PUBLISH=0
while [[ "${1:-}" == --* ]]; do
  case "${1}" in
    --check) CHECK_ONLY=1 ;;
    --resume) RESUME=1 ;;
    --publish) PUBLISH=1 ;;
    *) die "Unknown option: ${1}" ;;
  esac
  shift
done

if [[ $# -gt 1 ]]; then die "Expected at most one VERSION argument"; fi
if [[ "${CHECK_ONLY}" -eq 1 && "${RESUME}" -eq 1 ]]; then die "--resume cannot be combined with --check"; fi

if [[ $# -ge 1 ]]; then
  VERSION="$1"
else
  VERSION="$(tr -d '[:space:]' < VERSION)"
fi

if [[ "${VERSION}" == v* ]]; then
  TAG_VERSION="${VERSION}"
  VERSION="${VERSION#v}"
else
  TAG_VERSION="v${VERSION}"
fi

if [[ -n "${MINIMAX_HUB_SOURCE:-}" ]]; then
  SOURCE_PATH="${MINIMAX_HUB_SOURCE}"
elif [[ -n "${LOCALAPPDATA:-}" ]]; then
  SOURCE_PATH="${LOCALAPPDATA}\\Programs\\MiniMax Hub"
else
  SOURCE_PATH=""
fi
ELECTRON_VERSION="${MINIMAX_HUB_ELECTRON_VERSION:-38.8.6}"
NODE_VERSION="${MINIMAX_HUB_NODE_VERSION:-22.22.0}"

find_gh() {
  if command -v gh >/dev/null 2>&1; then command -v gh; return 0; fi
  if command -v gh.exe >/dev/null 2>&1; then command -v gh.exe; return 0; fi
  for candidate in \
    "/mnt/host/c/Program Files/GitHub CLI/gh.exe" \
    "/tmp/docker-desktop-root/run/desktop/mnt/host/c/Program Files/GitHub CLI/gh.exe" \
    "/mnt/c/Program Files/GitHub CLI/gh.exe" \
    "/c/Program Files/GitHub CLI/gh.exe"; do
    if [[ -x "${candidate}" ]]; then printf '%s\n' "${candidate}"; return 0; fi
  done
  return 1
}

find_docker() {
  if command -v docker.exe >/dev/null 2>&1; then command -v docker.exe; return 0; fi
  for candidate in \
    "/mnt/host/c/Program Files/Docker/Docker/resources/bin/docker.exe" \
    "/tmp/docker-desktop-root/run/desktop/mnt/host/c/Program Files/Docker/Docker/resources/bin/docker.exe" \
    "/mnt/c/Program Files/Docker/Docker/resources/bin/docker.exe" \
    "/c/Program Files/Docker/Docker/resources/bin/docker.exe"; do
    if [[ -x "${candidate}" ]]; then printf '%s\n' "${candidate}"; return 0; fi
  done
  if command -v docker >/dev/null 2>&1; then command -v docker; return 0; fi
  return 1
}

windows_path_from_bash() {
  local path="$1"
  local drive rest
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -w "${path}"
    return 0
  fi
  case "${path}" in
    /tmp/docker-desktop-root/run/desktop/mnt/host/[A-Za-z]/*)
      drive="${path#/tmp/docker-desktop-root/run/desktop/mnt/host/}"; drive="${drive%%/*}"; rest="${path#/tmp/docker-desktop-root/run/desktop/mnt/host/${drive}/}"; printf '%s:\\%s\n' "${drive^^}" "${rest//\//\\}" ;;
    /mnt/host/[A-Za-z]/*)
      drive="${path#/mnt/host/}"; drive="${drive%%/*}"; rest="${path#/mnt/host/${drive}/}"; printf '%s:\\%s\n' "${drive^^}" "${rest//\//\\}" ;;
    /mnt/[A-Za-z]/*)
      drive="${path#/mnt/}"; drive="${drive%%/*}"; rest="${path#/mnt/${drive}/}"; printf '%s:\\%s\n' "${drive^^}" "${rest//\//\\}" ;;
    /[A-Za-z]/*)
      drive="${path#/}"; drive="${drive%%/*}"; rest="${path#/${drive}/}"; printf '%s:\\%s\n' "${drive^^}" "${rest//\//\\}" ;;
    *) printf '%s\n' "${path}" ;;
  esac
}

bash_path_from_windows() {
  local path="$1"
  local drive rest lower_drive
  if [[ "${path}" =~ ^([A-Za-z]):[\\/](.*)$ ]]; then
    drive="${BASH_REMATCH[1]}"
    rest="${BASH_REMATCH[2]//\\//}"
    lower_drive="$(printf '%s' "${drive}" | tr '[:upper:]' '[:lower:]')"
    printf '/mnt/host/%s/%s\n' "${lower_drive}" "${rest}"
  else
    printf '%s\n' "${path}"
  fi
}

assert_docker_mount_works() {
  MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL="*" "${DOCKER_CMD}" run --rm --mount "type=bind,source=${HOST_WORKDIR},target=/work" -w /work alpine:3.20 test -f VERSION >/dev/null
}

assert_source_mount_works() {
  MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL="*" "${DOCKER_CMD}" run --rm --mount "type=bind,source=${HOST_SOURCE_PATH},target=/source,readonly" alpine:3.20 test -f /source/resources/app.asar >/dev/null
}

run_pipeline_container() {
  MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL="*" "${DOCKER_CMD}" run --rm \
    -e DEBIAN_FRONTEND=noninteractive \
    -e ELECTRON_VERSION="${ELECTRON_VERSION}" \
    -e NODE_VERSION="${NODE_VERSION}" \
    -e SOURCE_PATH="/source" \
    -e RESUME="${RESUME}" \
    --mount "type=bind,source=${HOST_WORKDIR},target=/work" \
    --mount "type=bind,source=${HOST_SOURCE_PATH},target=/source,readonly" \
    -w /work \
    ubuntu:24.04 \
    bash -lc '
      set -euo pipefail
      apt-get update >/dev/null
      apt-get install -y curl unzip tar xz-utils python3 ca-certificates npm build-essential pkg-config git >/dev/null
      if [[ "${RESUME}" != "1" || ! -d .cache/windows-payload/payload ]]; then
        bash scripts/extract-windows-payload.sh --source "${SOURCE_PATH}"
      else
        echo "Resume: using existing .cache/windows-payload/payload"
      fi
      bash scripts/inspect-payload.sh
      if [[ "${RESUME}" != "1" || ! -x linux-build/opt/minimax-hub/electron ]]; then
        bash scripts/fetch-electron-linux.sh --version "${ELECTRON_VERSION}"
      else
        echo "Resume: using existing Electron runtime"
      fi
      if [[ "${RESUME}" != "1" || ! -x linux-build/opt/minimax-hub/node/bin/node ]]; then
        bash scripts/fetch-node-linux.sh --version "${NODE_VERSION}"
      else
        echo "Resume: using existing Node runtime"
      fi
      if [[ "${RESUME}" != "1" || ! -x linux-build/opt/minimax-hub/resources/opencode/opencode ]]; then
        bash scripts/fetch-opencode-linux.sh
      else
        echo "Resume: using existing OpenCode binary"
      fi
      if [[ "${RESUME}" != "1" || ! -x linux-build/opt/minimax-hub/resources/ffmpeg/ffmpeg || ! -x linux-build/opt/minimax-hub/resources/ffmpeg/ffprobe ]]; then
        bash scripts/fetch-ffmpeg-linux.sh
      else
        echo "Resume: using existing FFmpeg binaries"
      fi
      bash scripts/assemble-linux-payload.sh --no-normalize
      bash scripts/rebuild-native-modules.sh
      MINIMAX_HUB_SKIP_PAYLOAD_REPORTS=1 bash scripts/assemble-linux-payload.sh
      bash tests/verify-payload.sh linux-build/opt/minimax-hub
      MINIMAX_HUB_SKIP_PAYLOAD_NORMALIZE=1 bash build.sh
    '
}

run_rpm_container() {
  MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL="*" "${DOCKER_CMD}" run --rm \
    --mount "type=bind,source=${HOST_WORKDIR},target=/work" \
    -w /work \
    rockylinux:9 \
    bash -lc 'dnf install -y rpm-build rpm cpio rsync findutils tar >/dev/null && bash build-rpm.sh'
}

info "MiniMax Hub Linux Release Helper"
info "================================"
info "Version: ${VERSION}"
info "Tag: ${TAG_VERSION}"
info "Source: ${SOURCE_PATH}"
info "Electron: ${ELECTRON_VERSION}"
info "Node: ${NODE_VERSION}"
echo

info "Checking prerequisites..."
if [[ -z "${SOURCE_PATH}" ]]; then die "MiniMax Hub source path is not set. Set MINIMAX_HUB_SOURCE to the installed MiniMax Hub directory."; fi
if [[ "${PUBLISH}" -eq 1 ]]; then
  GH_CMD="$(find_gh)" || die "GitHub CLI (gh) is not found. Install from: https://cli.github.com/"
  info "Found GitHub CLI: ${GH_CMD}"
  if ! "${GH_CMD}" auth status >/dev/null 2>&1; then die "GitHub CLI is not authenticated. Run: gh auth login"; fi
  success "GitHub CLI is authenticated"
fi

DOCKER_CMD="$(find_docker)" || die "Docker CLI is not found. Install Docker Desktop first."
info "Found Docker CLI: ${DOCKER_CMD}"
"${DOCKER_CMD}" info >/dev/null 2>&1 || die "Docker is not reachable. Start Docker Desktop and make sure the Windows Docker CLI works."
success "Docker is running"

HOST_WORKDIR="$(windows_path_from_bash "${SCRIPT_DIR}")"
if [[ "${SOURCE_PATH}" =~ ^[A-Za-z]:[\\/] ]]; then
  HOST_SOURCE_PATH="${SOURCE_PATH}"
else
  HOST_SOURCE_PATH="$(windows_path_from_bash "${SOURCE_PATH}")"
fi

info "Checking Docker repository mount access..."
assert_docker_mount_works || die "Docker cannot mount this repository. Check Docker Desktop file sharing settings."
success "Docker can access the repository"

info "Checking Docker MiniMax source mount access..."
assert_source_mount_works || die "Docker cannot mount the MiniMax Hub install at ${HOST_SOURCE_PATH}. Check the source path and Docker Desktop file sharing settings."
success "Docker can access the MiniMax Hub install"

if [[ "${CHECK_ONLY}" -eq 1 ]]; then
  success "Prerequisite check passed"
  exit 0
fi

echo
info "Preparing payload and building Debian package in Docker..."
run_pipeline_container
DEB_FILE="${SCRIPT_DIR}/output/minimax-hub_${VERSION}_amd64.deb"
[[ -f "${DEB_FILE}" ]] || die "Debian package was not created: ${DEB_FILE}"
success "Debian package built: ${DEB_FILE}"

echo
info "Building RPM package in Docker..."
run_rpm_container
RPM_FILE="${SCRIPT_DIR}/output/minimax-hub-${VERSION}-1.x86_64.rpm"
[[ -f "${RPM_FILE}" ]] || die "RPM package was not created: ${RPM_FILE}"
success "RPM package built: ${RPM_FILE}"

BUILT_FILES=("${DEB_FILE}" "${RPM_FILE}")
echo
info "Built packages for ${TAG_VERSION}:"
info "Files:"
for file in "${BUILT_FILES[@]}"; do info "  - $(basename "${file}") ($(du -h "${file}" | cut -f1))"; done
echo

if [[ "${PUBLISH}" -ne 1 ]]; then
  success "Package build complete. Built files are in output/."
  info "Run 'bash create-release.sh --publish ${VERSION}' to rebuild and upload artifacts to ${TAG_VERSION}."
  exit 0
fi

read -r -p "Publish release and upload files to ${TAG_VERSION}? [y/N] " reply
if [[ ! "${reply}" =~ ^[Yy]$ ]]; then info "Release upload cancelled. Built files are in output/."; exit 0; fi

if "${GH_CMD}" release view "${TAG_VERSION}" >/dev/null 2>&1; then
  warn "Release ${TAG_VERSION} already exists."
  read -r -p "Upload files to existing release? [y/N] " reply
  if [[ ! "${reply}" =~ ^[Yy]$ ]]; then info "Upload cancelled."; exit 0; fi
else
  "${GH_CMD}" release create "${TAG_VERSION}" \
    --title "${TAG_VERSION}" \
    --notes "MiniMax Hub Linux ${TAG_VERSION}

Unofficial community Linux packaging for MiniMax Hub.

## Install

### Debian/Ubuntu

\`\`\`bash
sudo apt install ./minimax-hub_${VERSION}_amd64.deb
\`\`\`

### Fedora/RHEL/Rocky

\`\`\`bash
sudo dnf install ./minimax-hub-${VERSION}-1.x86_64.rpm
\`\`\`

## Notes

- This is an unofficial community project, not affiliated with MiniMax.
- The MiniMax Hub application is proprietary software owned by MiniMax.
- Packages were built locally by the release maintainer from a local MiniMax Hub installation.
- Linux runtimes were staged from Electron, Node.js, OpenCode, and FFmpeg Linux releases or equivalent local archives.
- Known runtime, desktop integration, sandbox, gateway, MCP, OpenCode, FFmpeg, and native module risks are tracked in the repository documentation.
- See LICENSE and NOTICE files for details."
  success "Release ${TAG_VERSION} created"
fi

echo
info "Uploading packages..."
for file in "${BUILT_FILES[@]}"; do
  info "Uploading $(basename "${file}")..."
  "${GH_CMD}" release upload "${TAG_VERSION}" "${file}" --clobber
  success "Uploaded $(basename "${file}")"
done

echo
success "Release ${TAG_VERSION} complete!"
info "URL: https://github.com/Phototonic/minimax-hub-linux/releases/tag/${TAG_VERSION}"
