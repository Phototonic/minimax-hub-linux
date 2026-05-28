#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION_FILE="${PROJECT_ROOT}/VERSION"
PACKAGE_MANIFEST="${PROJECT_ROOT}/package-manifest.json"
PACKAGE_NAME="minimax-hub"
DEFAULT_CACHE_DIR="${PROJECT_ROOT}/.cache/runtimes"
DEFAULT_PAYLOAD_DIR="${PROJECT_ROOT}/linux-build/opt/minimax-hub"
WINDOWS_PAYLOAD_CACHE="${PROJECT_ROOT}/.cache/windows-payload"

die() {
  echo "Error: $*" >&2
  exit 1
}

info() {
  echo "$*" >&2
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

python_command() {
  if command -v python3 >/dev/null 2>&1; then
    echo python3
  elif command -v python >/dev/null 2>&1; then
    echo python
  else
    return 1
  fi
}

ensure_dir() {
  mkdir -p "$1"
}

manifest_value() {
  local expression="$1"
  local python_bin
  if python_bin="$(python_command)"; then
    "$python_bin" - "$PACKAGE_MANIFEST" "$expression" <<'PY'
import json
import sys

path, expression = sys.argv[1], sys.argv[2]
with open(path, "r", encoding="utf-8") as handle:
    data = json.load(handle)
value = data
for part in expression.split("."):
    if not isinstance(value, dict) or part not in value:
        value = None
        break
    value = value[part]
if value is None:
    sys.exit(1)
print(value)
PY
    return
  fi
  awk -v expr="$expression" '
    BEGIN { split(expr, parts, "."); found = 0 }
    $0 ~ "\"" parts[1] "\"[[:space:]]*:" {
      if (length(parts) == 1) { line = $0; found = 1 }
      in_object = 1
      next
    }
    in_object == 1 && length(parts) > 1 && $0 ~ "\"" parts[2] "\"[[:space:]]*:" { line = $0; found = 1 }
    found == 1 {
      sub(/^[^:]*:[[:space:]]*/, "", line)
      sub(/,[[:space:]]*$/, "", line)
      gsub(/^\"|\"$/, "", line)
      if (line == "null") exit 1
      print line
      exit 0
    }
    END { if (found == 0) exit 1 }
  ' "$PACKAGE_MANIFEST"
}

default_source_install_path() {
  manifest_value "sourceInstallPath"
}

resolve_source_path() {
  local raw_path="$1"
  local drive rest lower_drive candidate

  [[ -n "${raw_path}" ]] || die "Source path is empty. Provide --source or set sourceInstallPath in ${PACKAGE_MANIFEST}."

  if [[ -e "${raw_path}" ]]; then
    echo "${raw_path}"
    return 0
  fi

  if command -v cygpath >/dev/null 2>&1; then
    candidate="$(cygpath -u "${raw_path}" 2>/dev/null || true)"
    if [[ -n "${candidate}" && -e "${candidate}" ]]; then
      echo "${candidate}"
      return 0
    fi
  fi

  if [[ "${raw_path}" =~ ^([A-Za-z]):\\(.*)$ ]]; then
    drive="${BASH_REMATCH[1]}"
    rest="${BASH_REMATCH[2]//\\//}"
    lower_drive="$(printf '%s' "${drive}" | tr '[:upper:]' '[:lower:]')"

    candidate="/mnt/${lower_drive}/${rest}"
    if [[ -e "${candidate}" ]]; then
      echo "${candidate}"
      return 0
    fi

    candidate="/${lower_drive}/${rest}"
    if [[ -e "${candidate}" ]]; then
      echo "${candidate}"
      return 0
    fi
  fi

  die "Windows payload source path does not exist: ${raw_path}. Provide --source with an existing MiniMax Hub install root, or run from WSL/Git Bash where sourceInstallPath is reachable. Tried direct path, cygpath, /mnt/<drive>/..., and /<drive>/... conversions."
}

sha256_command() {
  if command -v sha256sum >/dev/null 2>&1; then
    echo "sha256sum"
  elif command -v shasum >/dev/null 2>&1; then
    echo "shasum -a 256"
  else
    die "Neither sha256sum nor shasum is available; install one to generate reproducible checksums."
  fi
}

write_sorted_inventory() {
  local root_dir="$1"
  local inventory_file="$2"

  [[ -d "${root_dir}" ]] || die "Cannot inventory missing directory: ${root_dir}"
  ensure_dir "$(dirname "${inventory_file}")"
  (cd "${root_dir}" && find . -type f -printf '%P\n' | LC_ALL=C sort) >"${inventory_file}"
}

write_sha256_report() {
  local root_dir="$1"
  local output_file="$2"
  local hasher jobs

  [[ -d "${root_dir}" ]] || die "Cannot checksum missing directory: ${root_dir}"
  ensure_dir "$(dirname "${output_file}")"
  hasher="$(sha256_command)"

  jobs="${MINIMAX_HUB_CHECKSUM_JOBS:-}"
  if [[ -z "${jobs}" ]]; then
    if command -v nproc >/dev/null 2>&1; then
      jobs="$(nproc)"
    else
      jobs=4
    fi
  fi

  (cd "${root_dir}" && find . -type f -printf '%P\0' | LC_ALL=C sort -z | xargs -0 -r -P "${jobs}" ${hasher}) \
    | LC_ALL=C sort >"${output_file}"
}

find_forbidden_windows_artifacts() {
  local root_dir="$1"
  [[ -d "${root_dir}" ]] || return 0
  find "${root_dir}" \
    \( -path "${WINDOWS_PAYLOAD_CACHE}/source" -o -path "${WINDOWS_PAYLOAD_CACHE}/source/*" \) -prune -o \
    \( -type f \( -iname '*.exe' -o -iname '*.dll' -o -iname '*.bat' -o -iname '*.cmd' \) -o \
       -type d \( -iname '*win32*' -o -iname '*windows*' -o -iname '*msvc*' \) \) -print | LC_ALL=C sort
}

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
    return
  fi
  local python_bin
  python_bin="$(python_command)" || die "Required command not found: sha256sum or python3"
  "$python_bin" - "$1" <<'PY'
import hashlib
import sys

digest = hashlib.sha256()
with open(sys.argv[1], "rb") as handle:
    for chunk in iter(lambda: handle.read(1024 * 1024), b""):
        digest.update(chunk)
print(digest.hexdigest())
PY
}

sha512_file() {
  if command -v sha512sum >/dev/null 2>&1; then
    sha512sum "$1" | awk '{print $1}'
    return
  fi
  local python_bin
  python_bin="$(python_command)" || die "Required command not found: sha512sum or python3"
  "$python_bin" - "$1" <<'PY'
import hashlib
import sys

digest = hashlib.sha512()
with open(sys.argv[1], "rb") as handle:
    for chunk in iter(lambda: handle.read(1024 * 1024), b""):
        digest.update(chunk)
print(digest.hexdigest())
PY
}

download_file() {
  local url="$1"
  local output="$2"
  ensure_dir "$(dirname "$output")"
  if [[ -s "$output" ]]; then
    info "Using cached download: ${output}"
    return 0
  fi
  if command -v curl >/dev/null 2>&1; then
    curl -fL --retry 3 --retry-delay 2 -o "$output" "$url"
  elif command -v wget >/dev/null 2>&1; then
    wget -O "$output" "$url"
  else
    die "Required command not found: curl or wget"
  fi
}

verify_checksum() {
  local expected="$1"
  local file="$2"
  local algorithm="$3"
  local actual
  case "$algorithm" in
    sha256) actual="$(sha256_file "$file")" ;;
    sha512) actual="$(sha512_file "$file")" ;;
    *) die "Unsupported checksum algorithm: ${algorithm}" ;;
  esac
  [[ "$actual" == "$expected" ]] || die "Checksum mismatch for ${file}: expected ${expected}, got ${actual}"
}

verify_checksum_from_sums() {
  local sums_file="$1"
  local archive_name="$2"
  local archive_path="$3"
  local algorithm="$4"
  local expected
  expected="$(awk -v name="$archive_name" '{ file=$2; sub(/^\*/, "", file) } file == name || file == "./" name { print $1; found=1; exit } END { if (!found) exit 1 }' "$sums_file")" \
    || die "Checksum entry not found for ${archive_name} in ${sums_file}"
  verify_checksum "$expected" "$archive_path" "$algorithm"
  echo "$expected"
}

extract_archive() {
  local archive="$1"
  local destination="$2"
  rm -rf "$destination"
  ensure_dir "$destination"
  case "$archive" in
    *.zip)
      require_command unzip
      unzip -q "$archive" -d "$destination"
      ;;
    *.tar.gz|*.tgz|*.tar.xz|*.txz|*.tar)
      require_command tar
      tar -xf "$archive" -C "$destination"
      ;;
    *)
      die "Unsupported archive format: ${archive}"
      ;;
  esac
}

copy_tree_contents() {
  local source_dir="$1"
  local destination_dir="$2"
  ensure_dir "$destination_dir"
  (cd "$source_dir" && tar -cf - .) | (cd "$destination_dir" && tar -xf -)
}

set_executable_if_present() {
  local path="$1"
  [[ -e "$path" ]] && chmod 0755 "$path"
}

require_nonempty_file() {
  [[ -s "$1" ]] || die "Expected non-empty file: $1"
}

update_manifest_runtime() {
  local runtime_key="$1"
  local version="$2"
  local checksum_key="$3"
  local checksum="$4"
  local python_bin
  python_bin="$(python_command)" || die "Required command not found: python3 or python for package-manifest.json update"
  local temp_manifest
  temp_manifest="$(mktemp "${PACKAGE_MANIFEST}.tmp.XXXXXX")"
  "$python_bin" - "$PACKAGE_MANIFEST" "$temp_manifest" "$runtime_key" "$version" "$checksum_key" "$checksum" <<'PY'
import json
import os
import sys

source, target, runtime_key, version, checksum_key, checksum = sys.argv[1:]
with open(source, "r", encoding="utf-8") as handle:
    data = json.load(handle)
if runtime_key != "-":
    data.setdefault("runtimePlaceholders", {})[runtime_key] = version
if checksum_key != "-":
    data.setdefault("checksums", {})[checksum_key] = checksum
with open(target, "w", encoding="utf-8") as handle:
    json.dump(data, handle, indent=2)
    handle.write("\n")
PY
  mv "$temp_manifest" "$PACKAGE_MANIFEST"
}

update_manifest_top_level_and_checksum() {
  local top_key="$1"
  local version="$2"
  local checksum_key="$3"
  local checksum="$4"
  local python_bin
  python_bin="$(python_command)" || die "Required command not found: python3 or python for package-manifest.json update"
  local temp_manifest
  temp_manifest="$(mktemp "${PACKAGE_MANIFEST}.tmp.XXXXXX")"
  "$python_bin" - "$PACKAGE_MANIFEST" "$temp_manifest" "$top_key" "$version" "$checksum_key" "$checksum" <<'PY'
import json
import sys

source, target, top_key, version, checksum_key, checksum = sys.argv[1:]
with open(source, "r", encoding="utf-8") as handle:
    data = json.load(handle)
data[top_key] = version
data.setdefault("checksums", {})[checksum_key] = checksum
with open(target, "w", encoding="utf-8") as handle:
    json.dump(data, handle, indent=2)
    handle.write("\n")
PY
  mv "$temp_manifest" "$PACKAGE_MANIFEST"
}

print_common_options() {
  cat <<'EOF'
Common options:
  --cache-dir DIR    Runtime download cache (default: .cache/runtimes)
  --payload-dir DIR  Payload root (default: linux-build/opt/minimax-hub)
  --archive FILE     Use an existing local archive instead of downloading
  --url URL          Override the default download URL
  --dry-run          Print planned actions without downloading, extracting, or updating manifest
  --help             Show help
EOF
}

not_implemented() {
  local script_name
  script_name="$(basename "$0")"
  die "Scaffold only: ${script_name} is not implemented yet."
}
