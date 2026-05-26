#!/usr/bin/env bash
set -euo pipefail

# MiniMax Hub Linux Release Helper
# Builds .deb and .rpm packages in Docker and creates a GitHub release.
#
# Usage:
#   bash create-release.sh [VERSION]
#   bash create-release.sh --check
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
if [[ "${1:-}" == "--check" ]]; then
  CHECK_ONLY=1
  shift
fi

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

mount_path() {
  local path="$1"
  local drive rest

  if command -v cygpath >/dev/null 2>&1; then
    cygpath -w "${path}"
    return 0
  fi

  case "${path}" in
    /tmp/docker-desktop-root/run/desktop/mnt/host/[A-Za-z]/*)
      drive="${path#/tmp/docker-desktop-root/run/desktop/mnt/host/}"
      drive="${drive%%/*}"
      rest="${path#/tmp/docker-desktop-root/run/desktop/mnt/host/${drive}/}"
      printf '%s:\\%s\n' "${drive^^}" "${rest//\//\\}"
      ;;
    /mnt/host/[A-Za-z]/*)
      drive="${path#/mnt/host/}"
      drive="${drive%%/*}"
      rest="${path#/mnt/host/${drive}/}"
      printf '%s:\\%s\n' "${drive^^}" "${rest//\//\\}"
      ;;
    /mnt/[A-Za-z]/*)
      drive="${path#/mnt/}"
      drive="${drive%%/*}"
      rest="${path#/mnt/${drive}/}"
      printf '%s:\\%s\n' "${drive^^}" "${rest//\//\\}"
      ;;
    /[A-Za-z]/*)
      drive="${path#/}"
      drive="${drive%%/*}"
      rest="${path#/${drive}/}"
      printf '%s:\\%s\n' "${drive^^}" "${rest//\//\\}"
      ;;
    *)
      printf '%s\n' "${path}"
      ;;
  esac
}

assert_docker_mount_works() {
  local host_path
  host_path="$(mount_path "${SCRIPT_DIR}")"
  "${DOCKER_CMD}" run --rm -v "${host_path}:/work" -w /work alpine:3.20 test -f VERSION >/dev/null
}

info "MiniMax Hub Linux Release Helper"
info "================================"
info "Version: ${VERSION}"
info "Tag: ${TAG_VERSION}"
echo

info "Checking prerequisites..."
GH_CMD="$(find_gh)" || die "GitHub CLI (gh) is not found. Install from: https://cli.github.com/"
info "Found GitHub CLI: ${GH_CMD}"

if ! "${GH_CMD}" auth status >/dev/null 2>&1; then
  die "GitHub CLI is not authenticated. Run: gh auth login"
fi
success "GitHub CLI is authenticated"

DOCKER_CMD="$(find_docker)" || die "Docker CLI is not found. Install Docker Desktop first."
info "Found Docker CLI: ${DOCKER_CMD}"
"${DOCKER_CMD}" info >/dev/null 2>&1 || die "Docker is not reachable. Start Docker Desktop and make sure the Windows Docker CLI works."
success "Docker is running"

info "Checking Docker bind mount access..."
assert_docker_mount_works || die "Docker cannot mount this repository. Check Docker Desktop file sharing settings."
success "Docker can access the repository"

if [[ "${CHECK_ONLY}" -eq 1 ]]; then
  success "Prerequisite check passed"
  exit 0
fi

PAYLOAD_DIR="${SCRIPT_DIR}/linux-build/opt/minimax-hub"
if [[ ! -d "${PAYLOAD_DIR}/resources" ]]; then
  die "Payload not found at ${PAYLOAD_DIR}. Run payload preparation first, then rerun this script."
fi
success "Payload found"

echo
BUILT_FILES=()
HOST_WORKDIR="$(mount_path "${SCRIPT_DIR}")"

info "Building Debian package with Docker..."
"${DOCKER_CMD}" run --rm \
  -v "${HOST_WORKDIR}:/work" \
  -w /work \
  ubuntu:24.04 \
  bash -lc 'apt-get update >/dev/null && apt-get install -y dpkg-dev rsync >/dev/null && bash build.sh'

DEB_FILE="${SCRIPT_DIR}/output/minimax-hub_${VERSION}_amd64.deb"
[[ -f "${DEB_FILE}" ]] || die "Debian package was not created: ${DEB_FILE}"
BUILT_FILES+=("${DEB_FILE}")
success "Debian package built: ${DEB_FILE}"

echo
info "Building RPM package with Docker..."
"${DOCKER_CMD}" run --rm \
  -v "${HOST_WORKDIR}:/work" \
  -w /work \
  rockylinux:9 \
  bash -lc 'dnf install -y rpm-build rpm cpio rsync findutils >/dev/null && bash build-rpm.sh'

RPM_FILE="${SCRIPT_DIR}/output/minimax-hub-${VERSION}-1.x86_64.rpm"
[[ -f "${RPM_FILE}" ]] || die "RPM package was not created: ${RPM_FILE}"
BUILT_FILES+=("${RPM_FILE}")
success "RPM package built: ${RPM_FILE}"

echo
info "Ready to create GitHub release: ${TAG_VERSION}"
info "Files to upload:"
for file in "${BUILT_FILES[@]}"; do
  info "  - $(basename "${file}") ($(du -h "${file}" | cut -f1))"
done
echo

read -r -p "Create release and upload files? [y/N] " reply
if [[ ! "${reply}" =~ ^[Yy]$ ]]; then
  info "Release cancelled. Built files are in output/."
  exit 0
fi

if "${GH_CMD}" release view "${TAG_VERSION}" >/dev/null 2>&1; then
  warn "Release ${TAG_VERSION} already exists."
  read -r -p "Upload files to existing release? [y/N] " reply
  if [[ ! "${reply}" =~ ^[Yy]$ ]]; then
    info "Upload cancelled."
    exit 0
  fi
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
