#!/usr/bin/env bash
# setup/_lib.sh - Shared variables and logging functions
# Sourced by setup.sh orchestrator and all setup/ step scripts.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# SCRIPT_DIR points to setup/; the module root is one level up
MODULE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
WORKLOG="$PROJECT_ROOT/worklog.md"
RULES="$PROJECT_ROOT/AGENT_RULES.md"
HOOK_DIR="$PROJECT_ROOT/.git/hooks"
HOOK_SRC="$MODULE_ROOT/.git-hooks/pre-commit"
PUSH_HOOK_SRC="$MODULE_ROOT/.git-hooks/pre-push"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
info()  { echo -e "${CYAN}[INFO]${NC} $*"; }
