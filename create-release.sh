#!/usr/bin/env bash
set -euo pipefail

# MiniMax Hub Linux Release Helper
# Builds .deb and .rpm packages and creates a GitHub release with attached assets
#
# Usage: bash create-release.sh [VERSION]
#   If VERSION is not provided, reads from VERSION file
#   Example: bash create-release.sh v0.1.44

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info() {
  echo -e "${BLUE}[INFO]${NC} $*"
}

success() {
  echo -e "${GREEN}[SUCCESS]${NC} $*"
}

warn() {
  echo -e "${YELLOW}[WARN]${NC} $*"
}

error() {
  echo -e "${RED}[ERROR]${NC} $*" >&2
}

die() {
  error "$*"
  exit 1
}

# Get version
if [[ $# -ge 1 ]]; then
  VERSION="$1"
else
  VERSION="$(tr -d '[:space:]' < VERSION)"
fi

# Ensure version has v prefix for git tag
if [[ "${VERSION}" != v* ]]; then
  TAG_VERSION="v${VERSION}"
else
  TAG_VERSION="${VERSION}"
  VERSION="${VERSION#v}"
fi

info "MiniMax Hub Linux Release Helper"
info "================================"
info "Version: ${VERSION}"
info "Tag: ${TAG_VERSION}"
echo

# Check prerequisites
info "Checking prerequisites..."

# Check gh CLI
if ! command -v gh &> /dev/null; then
  die "GitHub CLI (gh) is not installed. Install from: https://cli.github.com/"
fi

# Check gh authentication
if ! gh auth status &> /dev/null; then
  die "GitHub CLI is not authenticated. Run: gh auth login"
fi

# Check build tools
if ! command -v dpkg-deb &> /dev/null; then
  warn "dpkg-deb not found. Debian package build will be skipped."
  BUILD_DEB=false
else
  BUILD_DEB=true
fi

if ! command -v rpmbuild &> /dev/null; then
  warn "rpmbuild not found. RPM package build will be skipped."
  BUILD_RPM=false
else
  BUILD_RPM=true
fi

if [[ "${BUILD_DEB}" == false && "${BUILD_RPM}" == false ]]; then
  die "No package build tools found. Install dpkg-deb (Debian/Ubuntu) or rpm-build (Fedora/RHEL)."
fi

# Check if payload exists
PAYLOAD_DIR="${SCRIPT_DIR}/linux-build/opt/minimax-hub"
if [[ ! -d "${PAYLOAD_DIR}/resources" ]]; then
  die "Payload not found at ${PAYLOAD_DIR}. Run the build steps first:\n" \
      "  bash scripts/extract-windows-payload.sh --source '/path/to/MiniMax Hub'\n" \
      "  bash scripts/fetch-electron-linux.sh\n" \
      "  bash scripts/fetch-node-linux.sh\n" \
      "  bash scripts/fetch-opencode-linux.sh\n" \
      "  bash scripts/fetch-ffmpeg-linux.sh\n" \
      "  bash scripts/rebuild-native-modules.sh\n" \
      "  bash scripts/assemble-linux-payload.sh"
fi

echo

# Build packages
BUILT_FILES=()

if [[ "${BUILD_DEB}" == true ]]; then
  info "Building Debian package..."
  bash build.sh
  DEB_FILE="${SCRIPT_DIR}/output/minimax-hub_${VERSION}_amd64.deb"
  if [[ -f "${DEB_FILE}" ]]; then
    success "Debian package built: ${DEB_FILE}"
    BUILT_FILES+=("${DEB_FILE}")
  else
    error "Debian package build failed"
  fi
  echo
fi

if [[ "${BUILD_RPM}" == true ]]; then
  info "Building RPM package..."
  bash build-rpm.sh
  RPM_FILE="${SCRIPT_DIR}/output/minimax-hub-${VERSION}-1.x86_64.rpm"
  if [[ -f "${RPM_FILE}" ]]; then
    success "RPM package built: ${RPM_FILE}"
    BUILT_FILES+=("${RPM_FILE}")
  else
    error "RPM package build failed"
  fi
  echo
fi

if [[ ${#BUILT_FILES[@]} -eq 0 ]]; then
  die "No packages were built. Check errors above."
fi

# Confirm release creation
echo
info "Ready to create GitHub release: ${TAG_VERSION}"
info "Files to upload:"
for file in "${BUILT_FILES[@]}"; do
  info "  - $(basename "${file}") ($(du -h "${file}" | cut -f1))"
done
echo

read -p "Create release and upload files? [y/N] " -n 1 -r
echo

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  info "Release cancelled. Built files are in output/"
  exit 0
fi

# Create GitHub release
echo
info "Creating GitHub release ${TAG_VERSION}..."

# Check if release already exists
if gh release view "${TAG_VERSION}" &> /dev/null; then
  warn "Release ${TAG_VERSION} already exists."
  read -p "Upload files to existing release? [y/N] " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    info "Upload cancelled."
    exit 0
  fi
  RELEASE_EXISTS=true
else
  # Create new release
  gh release create "${TAG_VERSION}" \
    --title "${TAG_VERSION}" \
    --notes "MiniMax Hub Linux ${TAG_VERSION}\n\nUnofficial community Linux packaging for MiniMax Hub.\n\n## Install\n\n### Debian/Ubuntu\n\`\`\`bash\nsudo apt install ./minimax-hub_${VERSION}_amd64.deb\n\`\`\`\n\n### Fedora/RHEL/Rocky\n\n\`\`\`bash\nsudo dnf install ./minimax-hub-${VERSION}-1.x86_64.rpm\n\`\`\`\n\n## Notes\n\n- This is an unofficial community project, not affiliated with MiniMax\n- The MiniMax Hub application is proprietary software owned by MiniMax\n- See LICENSE and NOTICE files for details"
  RELEASE_EXISTS=false
  success "Release ${TAG_VERSION} created"
fi

# Upload files
echo
info "Uploading packages..."
for file in "${BUILT_FILES[@]}"; do
  info "Uploading $(basename "${file}")..."
  gh release upload "${TAG_VERSION}" "${file}" --clobber
  success "Uploaded $(basename "${file}")"
done

echo
success "Release ${TAG_VERSION} complete!"
info "URL: https://github.com/Phototonic/minimax-hub-linux/releases/tag/${TAG_VERSION}"
echo
info "Built files remain in output/ directory"
