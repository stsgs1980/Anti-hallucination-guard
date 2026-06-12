#!/bin/bash
# ============================================================
# anti-hallucination-guard / check-hooks-lib.sh
#
# Shared library for hook integrity tools. Provides:
#   - Project/module path resolution
#   - Color setup and logging helpers
#   - detect_module() -- find the AHG module directory
#   - fingerprint()  -- compute SHA256 of a file
#
# Sourced by:
#   - check-hooks-snapshot.sh
#   - check-hooks-verify.sh
# ============================================================

# Guard against double-sourcing
[ -n "${_AHG_LIB_LOADED:-}" ] && return 0
_AHG_LIB_LOADED=1

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MODULE_ROOT=""  # Will be populated by detect_module

STATE_FILE="$PROJECT_ROOT/.ahg-integrity.json"

# -- Colors -------------------------------------------------------------------
if [ -t 1 ]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
else
  RED=""; GREEN=""; YELLOW=""; CYAN=""; NC=""
fi

ok()   { echo -e "${GREEN}[OK]${NC} $*"; }
fail() { echo -e "${RED}[FAIL]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
info() { echo -e "${CYAN}[INFO]${NC} $*"; }

# -- Detect module location ---------------------------------------------------
detect_module() {
  local candidates=(
    "$PROJECT_ROOT/anti-hallucination-guard"
    "$PROJECT_ROOT/scripts/anti-hallucination-guard"
    "$PROJECT_ROOT/vendor/anti-hallucination-guard"
  )
  for dir in "${candidates[@]}"; do
    if [ -d "$dir" ] && [ -f "$dir/setup.sh" ]; then
      MODULE_ROOT="$dir"
      return 0
    fi
  done
  # Try git submodule
  if [ -f "$PROJECT_ROOT/.gitmodules" ]; then
    local sub_path
    sub_path=$(git -C "$PROJECT_ROOT" config -f .gitmodules --get-regexp 'path' 2>/dev/null \
      | grep -i 'anti.hallucination' | awk '{print $2}' | head -1 || true)
    if [ -n "$sub_path" ] && [ -d "$PROJECT_ROOT/$sub_path" ]; then
      MODULE_ROOT="$PROJECT_ROOT/$sub_path"
      return 0
    fi
  fi
  return 1
}

# -- Compute SHA256 fingerprint -----------------------------------------------
fingerprint() {
  if command -v sha256sum &>/dev/null; then
    sha256sum "$1" 2>/dev/null | cut -d' ' -f1
  elif command -v shasum &>/dev/null; then
    shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1
  else
    # Fallback: use md5 (weaker but better than nothing)
    md5sum "$1" 2>/dev/null | cut -d' ' -f1 || echo "unknown"
  fi
}
