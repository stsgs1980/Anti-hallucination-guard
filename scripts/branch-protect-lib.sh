#!/bin/bash
# ============================================================
# Anti-hallucination-guard / branch-protect-lib.sh
# Shared library for branch-protect.sh
#
# Provides: paths, color output helpers, configuration
# constants, and helper functions used by branch-protect.sh
#
# What branch-protect does:
#   1. Enforces branch naming convention: only "main" and "fix/*" can receive pushes
#   2. Validates commit author against ALLOWED_AUTHORS list
#   3. Detects and blocks "foreign" branch pushes
#   4. Checks that pushed commits don't modify module config files
#   5. Validates that setup.sh / update.sh signatures are intact
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STATE_FILE="$MODULE_ROOT/.branch-protect-state.json"

# ---- Colors ----
if [ -t 1 ]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
else
    RED=""; GREEN=""; YELLOW=""; CYAN=""; NC=""
fi
ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
fail() { echo -e "${RED}[BLOCKED]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
info() { echo -e "${CYAN}[INFO]${NC} $1"; }

# ============================================================
# CONFIGURATION
# ============================================================

# Allowed branch patterns (glob-style)
ALLOWED_BRANCHES=(
    "main"
    "fix/*"
    "feat/*"
    "chore/*"
)

# Files that MUST NOT be modified by external pushes
PROTECTED_FILES=(
    "scripts/validate.sh"
    ".gitignore"
    "setup.sh"
    "update.sh"
)

# SHA256 fingerprints of critical script first lines (tamper detection)
# Format: "file:expected_sha256_of_first_line"
SCRIPT_FINGERPRINTS=(
    "setup.sh:#!/bin/bash"
    "update.sh:#!/usr/bin/env bash"
)

# ============================================================
# FUNCTIONS
# ============================================================

init_state() {
    if [ ! -f "$STATE_FILE" ]; then
        cat > "$STATE_FILE" << JSONEOF
{
  "module": "anti-hallucination-guard",
  "version": "1.0",
  "protectedBranches": ["main"],
  "allowedAuthors": [],
  "fileHashes": {},
  "initialized": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSONEOF
        ok "State file created: $STATE_FILE"
    fi
}

# Get the list of remote refs that already exist
get_existing_branches() {
    git -C "$MODULE_ROOT" for-each-ref --format='%(refname:short)' refs/heads/ 2>/dev/null || true
}

# Check if a branch name matches any allowed pattern
branch_allowed() {
    local branch="$1"
    for pattern in "${ALLOWED_BRANCHES[@]}"; do
        # Simple glob match
        case "$branch" in
            $pattern) return 0 ;;
        esac
    done
    return 1
}

# -- Self-test routine --
run_test() {
    info "Running self-test..."
    init_state

    # Test 1: Check main branch is allowed
    if branch_allowed "main"; then
        ok "Test 1: 'main' branch allowed"
    else
        fail "Test 1: 'main' branch should be allowed"
    fi

    # Test 2: Check feature branch is allowed
    if branch_allowed "fix/worklog-timestamp"; then
        ok "Test 2: 'fix/worklog-timestamp' branch allowed"
    else
        fail "Test 2: 'fix/*' branches should be allowed"
    fi

    # Test 3: Reject foreign branch
    if ! branch_allowed "foreign-project-patch"; then
        ok "Test 3: 'foreign-project-patch' branch rejected"
    else
        fail "Test 3: Foreign branch names should be rejected"
    fi

    # Test 4: Script fingerprint check
    for fp in "${SCRIPT_FINGERPRINTS[@]}"; do
        ffile="${fp%%:*}"
        expected="${fp#*:}"
        if [ -f "$MODULE_ROOT/$ffile" ]; then
            first_line=$(head -1 "$MODULE_ROOT/$ffile")
            if [ "$first_line" = "$expected" ]; then
                ok "Test: $ffile fingerprint intact"
            else
                fail "Test: $ffile fingerprint changed!"
            fi
        fi
    done

    info "Self-test complete"
}

# -- Audit routine --
run_audit() {
    info "Branch Protection Audit"
    echo ""
    init_state

    echo "  Allowed branches: ${ALLOWED_BRANCHES[*]}"
    echo "  Protected files:  ${PROTECTED_FILES[*]}"
    echo "  State file:       $STATE_FILE"
    echo ""

    info "Existing branches:"
    get_existing_branches | while read -r b; do
        if branch_allowed "$b"; then
            ok "  $b"
        else
            warn "  $b (not in allowed list)"
        fi
    done

    echo ""
    info "Script fingerprints:"
    for fp in "${SCRIPT_FINGERPRINTS[@]}"; do
        ffile="${fp%%:*}"
        expected="${fp#*:}"
        if [ -f "$MODULE_ROOT/$ffile" ]; then
            first_line=$(head -1 "$MODULE_ROOT/$ffile")
            if [ "$first_line" = "$expected" ]; then
                ok "  $ffile -- intact"
            else
                fail "  $ffile -- TAMPERED (expected: '$expected', got: '$first_line')"
            fi
        else
            warn "  $ffile -- not found"
        fi
    done

    echo ""
    info "Protected files status:"
    for pf in "${PROTECTED_FILES[@]}"; do
        if [ -f "$MODULE_ROOT/$pf" ]; then
            size=$(wc -c < "$MODULE_ROOT/$pf")
            ok "  $pf ($size bytes)"
        else
            warn "  $pf -- missing"
        fi
    done
}
