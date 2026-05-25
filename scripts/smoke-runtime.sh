#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

usage() {
  cat <<'EOF'
Usage: smoke-runtime.sh [--payload-dir DIR]

Runs packaged runtime version checks:
  resources/opencode/opencode --version
  node/bin/node --version
  resources/ffmpeg/ffmpeg -version
  resources/ffmpeg/ffprobe -version
EOF
}

payload_dir="$DEFAULT_PAYLOAD_DIR"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --payload-dir) payload_dir="${2:-}"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) die "Unknown option for runtime smoke: $1" ;;
  esac
done

run_version_check() {
  local label="$1"
  local binary="$2"
  shift 2
  [[ -x "$binary" ]] || die "${label} runtime is missing or not executable: ${binary}"
  if ! output="$($binary "$@" 2>&1)"; then
    echo "$output" >&2
    die "${label} runtime version check failed: ${binary} $*"
  fi
  first_line="$(printf '%s\n' "$output" | sed -n '1p')"
  echo "${label}: ${first_line}"
}

run_version_check "OpenCode" "${payload_dir}/resources/opencode/opencode" --version
run_version_check "Node" "${payload_dir}/node/bin/node" --version
run_version_check "FFmpeg" "${payload_dir}/resources/ffmpeg/ffmpeg" -version
run_version_check "FFprobe" "${payload_dir}/resources/ffmpeg/ffprobe" -version
echo "Runtime smoke checks passed: ${payload_dir}"
