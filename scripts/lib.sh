#!/usr/bin/env bash
# Shared helpers sourced by every component install.sh.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${REPO_ROOT}/versions.env"

# ver_flag <version>  ->  "--version <version>" or nothing if empty
ver_flag() { if [[ -n "${1:-}" ]]; then echo "--version ${1}"; fi; }

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }

require() {
  for bin in "$@"; do
    command -v "$bin" >/dev/null 2>&1 || { echo "missing required binary: $bin" >&2; exit 1; }
  done
}

require kubectl helm
