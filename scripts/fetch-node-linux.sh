#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

DEFAULT_NODE_VERSION="22.16.0"

usage() {
  cat <<'EOF'
Usage: fetch-node-linux.sh [options]

Downloads or stages Node linux-x64 into node/bin/node.

Options:
  --version VERSION  Node version (default: package-manifest runtimePlaceholders.nodeVersion, then 22.16.0)
EOF
  print_common_options
}

version=""
cache_dir="$DEFAULT_CACHE_DIR"
payload_dir="$DEFAULT_PAYLOAD_DIR"
archive=""
url=""
dry_run=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) version="${2:-}"; shift 2 ;;
    --cache-dir) cache_dir="${2:-}"; shift 2 ;;
    --payload-dir) payload_dir="${2:-}"; shift 2 ;;
    --archive) archive="${2:-}"; shift 2 ;;
    --url) url="${2:-}"; shift 2 ;;
    --dry-run) dry_run=1; shift ;;
    --help|-h) usage; exit 0 ;;
    *) die "Unknown option for Node fetcher: $1" ;;
  esac
done

if [[ -z "$version" ]]; then
  version="$(manifest_value runtimePlaceholders.nodeVersion 2>/dev/null || true)"
fi
version="${version:-$DEFAULT_NODE_VERSION}"
version="${version#v}"

archive_name="node-v${version}-linux-x64.tar.xz"
runtime_cache="${cache_dir}/node/${version}"
archive_path="${archive:-${runtime_cache}/${archive_name}}"
download_url="${url:-https://nodejs.org/dist/v${version}/${archive_name}}"
shasums_url="https://nodejs.org/dist/v${version}/SHASUMS256.txt"
shasums_path="${runtime_cache}/SHASUMS256.txt"
node_dir="${payload_dir}/node"

if [[ "$dry_run" -eq 1 ]]; then
  echo "Would fetch Node ${version} from ${download_url}"
  echo "Would verify ${archive_name} with ${shasums_url}"
  echo "Would stage Node into ${node_dir}/bin/node"
  exit 0
fi

ensure_dir "$runtime_cache"
if [[ -z "$archive" ]]; then
  download_file "$download_url" "$archive_path"
else
  [[ -f "$archive_path" ]] || die "Node archive not found: ${archive_path}"
fi
require_nonempty_file "$archive_path"
download_file "$shasums_url" "$shasums_path"
checksum="$(verify_checksum_from_sums "$shasums_path" "$archive_name" "$archive_path" sha256)"

tmp_extract="$(mktemp -d "${runtime_cache}/extract.XXXXXX")"
trap 'rm -rf "$tmp_extract"' EXIT
extract_archive "$archive_path" "$tmp_extract"
source_root="${tmp_extract}/node-v${version}-linux-x64"
[[ -d "$source_root" ]] || die "Expected Node archive root missing: ${source_root}"
rm -rf "$node_dir"
ensure_dir "$(dirname "$node_dir")"
mv "$source_root" "$node_dir"
set_executable_if_present "${node_dir}/bin/node"
[[ -x "${node_dir}/bin/node" ]] || die "Node binary was not staged at ${node_dir}/bin/node"

update_manifest_runtime nodeVersion "$version" nodeLinux "$checksum"
echo "Node ${version} staged at ${node_dir}/bin/node"
