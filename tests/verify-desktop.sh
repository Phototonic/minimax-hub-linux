#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/testlib.sh"

desktop_file="${1:-${DESKTOP_FILE}}"
validate_desktop_file "${desktop_file}"
echo "Desktop verification passed: ${desktop_file}"

