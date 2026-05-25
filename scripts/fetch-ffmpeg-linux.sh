#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

DEFAULT_FFMPEG_VERSION="latest"
DEFAULT_FFMPEG_URL="https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-linux64-gpl.tar.xz"
DEFAULT_FFMPEG_SUMS_URL="https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/checksums.sha256"

usage() {
  cat <<'EOF'
Usage: fetch-ffmpeg-linux.sh [options]

Downloads or stages Linux ffmpeg and ffprobe into resources/ffmpeg/.

Options:
  --version VERSION     FFmpeg version label recorded in manifest (default: manifest value, then latest)
  --ffmpeg FILE         Stage an existing ffmpeg binary
  --ffprobe FILE        Stage an existing ffprobe binary
  --checksums-url URL   Override checksum file URL for archive verification
  --no-checksum         Skip archive checksum lookup and record local SHA256
EOF
  print_common_options
}

version=""
cache_dir="$DEFAULT_CACHE_DIR"
payload_dir="$DEFAULT_PAYLOAD_DIR"
archive=""
url=""
checksums_url="$DEFAULT_FFMPEG_SUMS_URL"
ffmpeg_bin=""
ffprobe_bin=""
dry_run=0
no_checksum=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) version="${2:-}"; shift 2 ;;
    --ffmpeg) ffmpeg_bin="${2:-}"; shift 2 ;;
    --ffprobe) ffprobe_bin="${2:-}"; shift 2 ;;
    --checksums-url) checksums_url="${2:-}"; shift 2 ;;
    --no-checksum) no_checksum=1; shift ;;
    --cache-dir) cache_dir="${2:-}"; shift 2 ;;
    --payload-dir) payload_dir="${2:-}"; shift 2 ;;
    --archive) archive="${2:-}"; shift 2 ;;
    --url) url="${2:-}"; shift 2 ;;
    --dry-run) dry_run=1; shift ;;
    --help|-h) usage; exit 0 ;;
    *) die "Unknown option for FFmpeg fetcher: $1" ;;
  esac
done

if [[ -z "$version" ]]; then
  version="$(manifest_value runtimePlaceholders.ffmpegVersion 2>/dev/null || true)"
fi
version="${version:-$DEFAULT_FFMPEG_VERSION}"

target_dir="${payload_dir}/resources/ffmpeg"
target_ffmpeg="${target_dir}/ffmpeg"
target_ffprobe="${target_dir}/ffprobe"
runtime_cache="${cache_dir}/ffmpeg/${version}"

if [[ -n "$ffmpeg_bin" || -n "$ffprobe_bin" ]]; then
  [[ -n "$ffmpeg_bin" && -n "$ffprobe_bin" ]] || die "Both --ffmpeg and --ffprobe are required when staging binaries directly."
  if [[ "$dry_run" -eq 1 ]]; then
    echo "Would stage ffmpeg from ${ffmpeg_bin} into ${target_ffmpeg}"
    echo "Would stage ffprobe from ${ffprobe_bin} into ${target_ffprobe}"
    exit 0
  fi
  [[ -f "$ffmpeg_bin" ]] || die "ffmpeg binary not found: ${ffmpeg_bin}"
  [[ -f "$ffprobe_bin" ]] || die "ffprobe binary not found: ${ffprobe_bin}"
  ensure_dir "$target_dir"
  cp "$ffmpeg_bin" "$target_ffmpeg"
  cp "$ffprobe_bin" "$target_ffprobe"
  chmod 0755 "$target_ffmpeg" "$target_ffprobe"
  ffmpeg_checksum="$(sha256_file "$target_ffmpeg")"
  ffprobe_checksum="$(sha256_file "$target_ffprobe")"
  update_manifest_runtime ffmpegVersion "$version" ffmpegLinux "$ffmpeg_checksum"
  update_manifest_runtime ffprobeVersion "$version" ffprobeLinux "$ffprobe_checksum"
  echo "FFmpeg binaries staged at ${target_dir}"
  exit 0
fi

archive_name="$(basename "${url:-$DEFAULT_FFMPEG_URL}")"
archive_path="${archive:-${runtime_cache}/${archive_name}}"
download_url="${url:-$DEFAULT_FFMPEG_URL}"
checksums_path="${runtime_cache}/checksums.sha256"

if [[ "$dry_run" -eq 1 ]]; then
  echo "Would fetch FFmpeg ${version} from ${download_url}"
  if [[ "$no_checksum" -eq 0 ]]; then
    echo "Would verify ${archive_name} with ${checksums_url} when an entry exists"
  else
    echo "Would skip upstream checksum and record local SHA256"
  fi
  echo "Would stage ffmpeg and ffprobe into ${target_dir}"
  exit 0
fi

ensure_dir "$runtime_cache"
if [[ -z "$archive" ]]; then
  download_file "$download_url" "$archive_path"
else
  [[ -f "$archive_path" ]] || die "FFmpeg archive not found: ${archive_path}"
fi
require_nonempty_file "$archive_path"
archive_checksum="$(sha256_file "$archive_path")"
if [[ "$no_checksum" -eq 0 ]]; then
  if download_file "$checksums_url" "$checksums_path"; then
    if grep -Eq "[[:space:]](\./)?${archive_name}$" "$checksums_path"; then
      archive_checksum="$(verify_checksum_from_sums "$checksums_path" "$archive_name" "$archive_path" sha256)"
    else
      info "Checksum file did not contain ${archive_name}; recording local SHA256."
    fi
  else
    info "Could not download FFmpeg checksum file; recording local SHA256."
  fi
fi

tmp_extract="$(mktemp -d "${runtime_cache}/extract.XXXXXX")"
trap 'rm -rf "$tmp_extract"' EXIT
extract_archive "$archive_path" "$tmp_extract"
ffmpeg_source="$(find "$tmp_extract" -type f -path '*/bin/ffmpeg' -print -quit)"
ffprobe_source="$(find "$tmp_extract" -type f -path '*/bin/ffprobe' -print -quit)"
[[ -n "$ffmpeg_source" ]] || ffmpeg_source="$(find "$tmp_extract" -type f -name ffmpeg -print -quit)"
[[ -n "$ffprobe_source" ]] || ffprobe_source="$(find "$tmp_extract" -type f -name ffprobe -print -quit)"
[[ -n "$ffmpeg_source" ]] || die "ffmpeg binary was not found in ${archive_path}"
[[ -n "$ffprobe_source" ]] || die "ffprobe binary was not found in ${archive_path}"
ensure_dir "$target_dir"
cp "$ffmpeg_source" "$target_ffmpeg"
cp "$ffprobe_source" "$target_ffprobe"
chmod 0755 "$target_ffmpeg" "$target_ffprobe"
[[ -x "$target_ffmpeg" ]] || die "ffmpeg binary was not staged at ${target_ffmpeg}"
[[ -x "$target_ffprobe" ]] || die "ffprobe binary was not staged at ${target_ffprobe}"

update_manifest_runtime ffmpegVersion "$version" ffmpegLinux "$archive_checksum"
update_manifest_runtime ffprobeVersion "$version" ffprobeLinux "$(sha256_file "$target_ffprobe")"
echo "FFmpeg ${version} staged at ${target_dir}"
