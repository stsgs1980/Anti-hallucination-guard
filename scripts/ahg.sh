#!/bin/bash
# ============================================================
# anti-hallucination-guard / ahg.sh
# Unified CLI entry point for all AHG commands.
#
# Usage: bash scripts/ahg.sh <command> [args]
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VD_CLI="$PROJECT_ROOT/tools/verify-docs/src/cli.ts"
VD_INIT="$PROJECT_ROOT/tools/verify-docs/src/init.ts"

# -- Verify prerequisites -----------------------------------------------------
if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    echo ""
    echo "ahg -- Anti-Hallucination Guard CLI v2.1"
    echo ""
    echo "USAGE"
    echo "  bash scripts/ahg.sh <command> [args]"
    echo ""
    echo "COMMANDS"
    echo "  verify [--ci]           Verify docs (auto-discover if no config!)"
    echo "  discover                Auto-scan project (no config needed)"
    echo "  bump <version>          Update version in all files"
    echo "  bump <version> --dry-run   Preview bump without writing"
    echo "  init                    Generate verify-docs.json"
    echo "  baseline                Create .ahg-baseline.json"
    echo "  baseline --check        Check current files vs baseline"
    echo "  snapshot [--snapshot]   Manage hook integrity snapshots"
    echo "  integrity [--repair]    Check or repair hook integrity"
    echo "  sync [--dry-run]        Auto-sync task statuses"
    echo "  audit                   Post-session audit"
    echo "  validate                Repository purity check"
    echo ""
    echo "EXAMPLES"
    echo "  bash scripts/ahg.sh discover"
    echo "  bash scripts/ahg.sh bump 2.0.0"
    echo "  bash scripts/ahg.sh verify --ci"
    echo ""
    exit 0
fi

# -- Helper: check bun --------------------------------------------------------
check_bun() {
    if ! command -v bun &>/dev/null; then
        echo "ahg: bun is required. Install: https://bun.sh"
        exit 1
    fi
}

# -- Helper: check verify-docs ------------------------------------------------
check_vd() {
    if [ ! -f "$VD_CLI" ]; then
        echo "ahg: verify-docs not found at $VD_CLI"
        echo "     Run: bash anti-hallucination-guard/setup.sh"
        exit 1
    fi
}

# -- Fix CWD: always run from project root ------------------------------------
cd "$PROJECT_ROOT"

# -- Command router -----------------------------------------------------------
case "${1:-}" in
  verify)
    shift
    check_bun && check_vd
    bun run "$VD_CLI" "$@"
    ;;

  discover)
    shift
    check_bun && check_vd
    bun run "$VD_CLI" --discover "$@"
    ;;

  bump)
    shift
    check_bun && check_vd
    if [ -z "${1:-}" ]; then
        echo "ahg bump: version required (e.g. ahg bump 2.0.0)"
        exit 1
    fi
    bun run "$VD_CLI" --bump="$1" "${@:2}"
    ;;

  init)
    shift
    check_bun && check_vd
    bun run "$VD_CLI" --init "$@"
    ;;

  baseline)
    shift
    check_bun && check_vd
    if echo "$@" | grep -q "\-\-check"; then
        bun run "$VD_CLI" --baseline --check "$@"
    else
        bun run "$VD_CLI" --baseline "$@"
    fi
    ;;

  snapshot)
    shift
    if [ -f "$SCRIPT_DIR/check-hooks-snapshot.sh" ]; then
        bash "$SCRIPT_DIR/check-hooks-snapshot.sh" --snapshot "$@"
    else
        echo "ahg: check-hooks-snapshot.sh not found"
        exit 1
    fi
    ;;

  integrity)
    shift
    if [ -f "$SCRIPT_DIR/check-hooks-verify.sh" ]; then
        bash "$SCRIPT_DIR/check-hooks-verify.sh" "$@"
    elif [ -f "$SCRIPT_DIR/check-hooks-integrity.sh" ]; then
        bash "$SCRIPT_DIR/check-hooks-integrity.sh" "$@"
    else
        echo "ahg: integrity check script not found"
        exit 1
    fi
    ;;

  sync)
    shift
    if [ -f "$SCRIPT_DIR/sync-task-state.sh" ]; then
        bash "$SCRIPT_DIR/sync-task-state.sh" "$@"
    else
        echo "ahg: sync-task-state.sh not found"
        exit 1
    fi
    ;;

  audit)
    shift
    if [ -f "$SCRIPT_DIR/audit.sh" ]; then
        bash "$SCRIPT_DIR/audit.sh" "$@"
    else
        echo "ahg: audit.sh not found"
        exit 1
    fi
    ;;

  validate)
    shift
    if [ -f "$SCRIPT_DIR/validate.sh" ]; then
        bash "$SCRIPT_DIR/validate.sh" "$@"
    else
        echo "ahg: validate.sh not found"
        exit 1
    fi
    ;;

  *)
    echo "ahg: unknown command '${1:-}'"
    echo "Run: bash scripts/ahg.sh --help"
    exit 1
    ;;
esac
