#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

usage() {
  cat <<'EOF'
Usage: fetch-opencode-linux.sh [options]

Downloads or stages OpenCode linux-x64 into resources/opencode/opencode.

Options:
  --version VERSION  OpenCode version (default: package-manifest openCodeVersion, currently 1.15.10)
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
    *) die "Unknown option for OpenCode fetcher: $1" ;;
  esac
done

if [[ -z "$version" ]]; then
  version="$(manifest_value openCodeVersion 2>/dev/null || true)"
fi
[[ -n "$version" ]] || die "OpenCode version is required. Pass --version or set openCodeVersion in package-manifest.json."

archive_name="opencode-linux-x64.tar.gz"
runtime_cache="${cache_dir}/opencode/${version}"
archive_path="${archive:-${runtime_cache}/${archive_name}}"
download_url="${url:-https://github.com/anomalyco/opencode/releases/download/v${version}/${archive_name}}"
target_dir="${payload_dir}/resources/opencode"
target_bin="${target_dir}/opencode"

if [[ "$dry_run" -eq 1 ]]; then
  echo "Would fetch OpenCode ${version} from ${download_url}"
  echo "Would stage OpenCode into ${target_bin}"
  echo "Would record local SHA256 because upstream checksums may be unavailable"
  exit 0
fi

ensure_dir "$runtime_cache"
if [[ -z "$archive" ]]; then
  download_file "$download_url" "$archive_path"
else
  [[ -f "$archive_path" ]] || die "OpenCode archive not found: ${archive_path}"
fi
require_nonempty_file "$archive_path"
checksum="$(sha256_file "$archive_path")"

tmp_extract="$(mktemp -d "${runtime_cache}/extract.XXXXXX")"
trap 'rm -rf "$tmp_extract"' EXIT
extract_archive "$archive_path" "$tmp_extract"
opencode_source="$(find "$tmp_extract" -type f -name opencode -print -quit)"
[[ -n "$opencode_source" ]] || die "OpenCode binary named 'opencode' was not found in ${archive_path}"
ensure_dir "$target_dir"
cp "$opencode_source" "$target_bin"
chmod 0755 "$target_bin"
[[ -x "$target_bin" ]] || die "OpenCode binary was not staged at ${target_bin}"

update_manifest_top_level_and_checksum openCodeVersion "$version" opencodeLinux "$checksum"
echo "OpenCode ${version} staged at ${target_bin}"
