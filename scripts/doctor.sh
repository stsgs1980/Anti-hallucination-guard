#!/usr/bin/env bash
# ============================================================
# anti-hallucination-guard / doctor.sh
# Reports what this environment can and cannot run, before any
# check is attempted.
#
# Usage: bash scripts/doctor.sh [--strict]
#   --strict  exit 1 when a tool needed by the gate is missing
#
# Exit: 0 report produced, 1 with --strict and a required tool missing.
# ============================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_ROOT="$(git -C "$MODULE_ROOT" rev-parse --show-toplevel 2>/dev/null || echo "$MODULE_ROOT")"

STRICT=0
for arg in "$@"; do
    case "$arg" in
        --strict) STRICT=1 ;;
        --help|-h) sed -n '3,10p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "doctor: unknown option '$arg'" >&2; exit 2 ;;
    esac
done

MISSING_REQUIRED=0

line() { printf '  %-16s %s\n' "$1" "$2"; }

tool() { # name required
    local name="$1" required="$2" version=""
    if command -v "$name" &>/dev/null; then
        version="$("$name" --version 2>&1 | head -1)"
        line "$name" "$version"
    elif [ "$required" = "yes" ]; then
        line "$name" "MISSING (required)"
        MISSING_REQUIRED=$((MISSING_REQUIRED + 1))
    else
        line "$name" "MISSING (optional)"
    fi
}

present() { # label path
    if [ -e "$2" ]; then line "$1" "present"; else line "$1" "absent"; fi
}

CONTEXT="consumer"
if [ -f "$MODULE_ROOT/setup.sh" ] && [ -f "$MODULE_ROOT/AGENT_RULES.md" ]; then
    CONTEXT="AHG module"
fi

echo "ahg doctor"
echo ""
echo "Context"
line "role" "$CONTEXT"
line "project root" "$PROJECT_ROOT"
line "module root" "$MODULE_ROOT"

echo ""
echo "Tools"
tool git yes
tool bash yes
tool python3 yes
tool bun yes
tool gh no
tool jq no

echo ""
echo "Hooks (installed in .git/hooks)"
if [ -d "$PROJECT_ROOT/.git/hooks" ]; then
    for hook in pre-commit pre-push post-checkout; do
        if [ -f "$PROJECT_ROOT/.git/hooks/$hook" ]; then
            line "$hook" "installed"
        else
            line "$hook" "not installed"
        fi
    done
else
    line "hooks dir" "no .git/hooks (not a git checkout?)"
fi

echo ""
echo "Configuration"
present "verify-docs.json" "$PROJECT_ROOT/verify-docs.json"
present ".ahgrc" "$PROJECT_ROOT/.ahgrc"
present ".ahg-cochange.json" "$PROJECT_ROOT/.ahg-cochange.json"

echo ""
echo "What the gate would do here"
if [ -f "$SCRIPT_DIR/check.sh" ]; then
    bash "$SCRIPT_DIR/check.sh" --list | tail -n +2 | while IFS= read -r row; do
        echo "  $row"
    done
else
    echo "  check.sh not found next to this script"
fi

echo ""
if [ "$MISSING_REQUIRED" -gt 0 ]; then
    echo "$MISSING_REQUIRED required tool(s) missing: those checks will be"
    echo "reported as SKIP by 'ahg check', not as PASS."
    if [ "$STRICT" -eq 1 ]; then
        exit 1
    fi
    exit 0
fi
echo "All required tools are available."
exit 0
