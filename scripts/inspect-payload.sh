#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

cache_dir="${WINDOWS_PAYLOAD_CACHE}"
payload_dir=""
strict=1

usage() {
  cat <<USAGE
Usage: $(basename "$0") [--payload PATH] [--cache-dir PATH] [--no-fail]

Inspects a staged MiniMax Hub payload and writes deterministic reports.

Options:
  --payload PATH    Staged payload root. Defaults to CACHE_DIR/payload.
  --cache-dir PATH  Report/cache directory. Defaults to .cache/windows-payload.
  --no-fail         Write reports but return success even when required items are missing.
  -h, --help        Show this help text.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --payload)
      [[ $# -ge 2 ]] || die "--payload requires a path."
      payload_dir="$2"
      shift 2
      ;;
    --cache-dir)
      [[ $# -ge 2 ]] || die "--cache-dir requires a path."
      cache_dir="$2"
      shift 2
      ;;
    --no-fail)
      strict=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
done

if [[ -z "${payload_dir}" ]]; then
  payload_dir="${cache_dir}/payload"
fi

missing=()
warnings=()

record_required_file() {
  local relative_path="$1"
  if [[ -s "${payload_dir}/${relative_path}" ]]; then
    echo "OK file: ${relative_path}"
  else
    echo "MISSING file: ${relative_path}"
    missing+=("${relative_path}")
  fi
}

record_required_dir() {
  local relative_path="$1"
  if [[ -d "${payload_dir}/${relative_path}" ]]; then
    echo "OK dir: ${relative_path}"
  else
    echo "MISSING dir: ${relative_path}"
    missing+=("${relative_path}")
  fi
}

list_relative_matches() {
  local label="$1"
  shift
  local matches

  if [[ ! -d "${payload_dir}" ]]; then
    echo "${label}: none"
    return 0
  fi

  matches="$(find "${payload_dir}" "$@" -printf '%P\n' | LC_ALL=C sort || true)"
  if [[ -n "${matches}" ]]; then
    echo "${label}:"
    printf '%s\n' "${matches}"
  else
    echo "${label}: none"
  fi
}

detect_protocol_candidates() {
  local candidates

  if [[ ! -d "${payload_dir}" ]]; then
    echo "Protocol candidates: none"
    return 0
  fi

  candidates="$(find "${payload_dir}" -type f \( -iname '*.desktop' -o -iname '*.json' -o -iname '*.plist' -o -iname '*.yml' -o -iname '*.yaml' \) -print0 | xargs -0 grep -Eho 'x-scheme-handler/[A-Za-z0-9.+-]+|[A-Za-z][A-Za-z0-9.+-]+://' 2>/dev/null | LC_ALL=C sort -u || true)"
  if [[ -n "${candidates}" ]]; then
    echo "Protocol candidates:"
    printf '%s\n' "${candidates}"
  else
    echo "Protocol candidates: none"
    warnings+=("No protocol candidates discovered in staged metadata/config files; do not invent schemes.")
  fi
}

ensure_dir "${cache_dir}"
inspection_report="${cache_dir}/inspection-report.txt"

{
  echo "MiniMax Hub staged payload inspection"
  echo "Payload: ${payload_dir}"
  echo

  if [[ ! -d "${payload_dir}" ]]; then
    echo "MISSING dir: ${payload_dir}"
    missing+=("${payload_dir}")
  fi

  record_required_file "resources/app.asar"
  record_required_file "resources/gateway/dist/main.js"
  record_required_file "resources/mcp-tools/dist/main.js"
  record_required_dir "resources/opencode/config"
    if [[ -d "${payload_dir}/resources/icons" || -d "${payload_dir}/resources/assets" || -d "${payload_dir}/resources/app-resources" ]]; then
    echo "OK dir: icon resources"
  else
    echo "MISSING dir: resources/icons, resources/assets, or resources/app-resources"
    missing+=("icon resources")
  fi

  echo
  list_relative_matches "Icons" -type f \( -iname '*.png' -o -iname '*.ico' -o -iname '*.icns' -o -iname '*.svg' \)
  echo
  list_relative_matches "Native modules" -type f -name '*.node'
  echo
  list_relative_matches "better-sqlite3 native candidates" -type f -path '*better-sqlite3*' -name '*.node'
  echo
  list_relative_matches "sharp native candidates" -type f \( -path '*sharp*' -o -path '*@img*' \)
  echo
  list_relative_matches "@node-rs/xxhash native candidates" -type f -path '*@node-rs*xxhash*'
  echo
  detect_protocol_candidates
  echo

  forbidden="$(find_forbidden_windows_artifacts "${payload_dir}")"
  if [[ -n "${forbidden}" ]]; then
    echo "Forbidden Windows artifacts:"
    printf '%s\n' "${forbidden}"
    missing+=("forbidden Windows artifacts")
  else
    echo "Forbidden Windows artifacts: none"
  fi
  echo
  echo "Platform-specific replacements required:"
  echo "- Electron Linux runtime"
  echo "- Linux Node runtime for gateway and MCP tools"
  echo "- Linux OpenCode binary at resources/opencode/opencode"
  echo "- Linux FFmpeg and FFprobe"
  echo "- Linux-native replacements for any listed *.node modules"

  if [[ ${#warnings[@]} -gt 0 ]]; then
    echo
    echo "Warnings:"
    printf -- '- %s\n' "${warnings[@]}"
  fi
} >"${inspection_report}"

cat "${inspection_report}"

if [[ -d "${payload_dir}" ]]; then
  write_sorted_inventory "${payload_dir}" "${cache_dir}/inventory.txt"
  write_sha256_report "${payload_dir}" "${cache_dir}/sha256.txt"
fi

if [[ ${#missing[@]} -gt 0 && "${strict}" -eq 1 ]]; then
  echo >&2
  echo "Error: Staged payload inspection failed. Missing or invalid items:" >&2
  printf 'Error: - %s\n' "${missing[@]}" >&2
  echo "Error: Run scripts/extract-windows-payload.sh --source PATH first, or pass --payload PATH to inspect a fixture/staged payload." >&2
  exit 1
fi

info "Wrote ${inspection_report}"
