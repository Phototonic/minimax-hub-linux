#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

usage() {
  cat <<'EOF'
Usage: fetch-electron-linux.sh --version VERSION [options]

Downloads or stages Electron linux-x64 into the payload root.

Options:
  --version VERSION  Electron version. If omitted, package-manifest runtimePlaceholders.electronVersion is used when present.
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
    *) die "Unknown option for Electron fetcher: $1" ;;
  esac
done

if [[ -z "$version" ]]; then
  version="$(manifest_value runtimePlaceholders.electronVersion 2>/dev/null || true)"
fi
[[ -n "$version" ]] || die "Electron version is required. Pass --version or set runtimePlaceholders.electronVersion in package-manifest.json."

archive_name="electron-v${version}-linux-x64.zip"
runtime_cache="${cache_dir}/electron/${version}"
archive_path="${archive:-${runtime_cache}/${archive_name}}"
download_url="${url:-https://github.com/electron/electron/releases/download/v${version}/${archive_name}}"
shasums_url="https://github.com/electron/electron/releases/download/v${version}/SHASUMS512.txt"
shasums_path="${runtime_cache}/SHASUMS512.txt"

if [[ "$dry_run" -eq 1 ]]; then
  echo "Would fetch Electron ${version} from ${download_url}"
  echo "Would verify ${archive_name} with ${shasums_url}"
  echo "Would stage Electron into ${payload_dir}"
  exit 0
fi

ensure_dir "$runtime_cache"
if [[ -z "$archive" ]]; then
  download_file "$download_url" "$archive_path"
else
  [[ -f "$archive_path" ]] || die "Electron archive not found: ${archive_path}"
fi
require_nonempty_file "$archive_path"
download_file "$shasums_url" "$shasums_path"
checksum="$(verify_checksum_from_sums "$shasums_path" "$archive_name" "$archive_path" sha512)"

tmp_extract="$(mktemp -d "${runtime_cache}/extract.XXXXXX")"
trap 'rm -rf "$tmp_extract"' EXIT
extract_archive "$archive_path" "$tmp_extract"
copy_tree_contents "$tmp_extract" "$payload_dir"
set_executable_if_present "${payload_dir}/electron"
set_executable_if_present "${payload_dir}/chrome-sandbox"
[[ -x "${payload_dir}/electron" ]] || die "Electron binary was not staged at ${payload_dir}/electron"

update_manifest_runtime electronVersion "$version" electronLinux "$checksum"
echo "Electron ${version} staged at ${payload_dir}/electron"
