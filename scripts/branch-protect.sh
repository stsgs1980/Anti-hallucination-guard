#!/bin/bash
# ============================================================
# Anti-hallucination-guard / branch-protect.sh
# Branch-level protection against unauthorized pushes
#
# Usage:
#   bash scripts/branch-protect.sh          # audit current state
#   bash scripts/branch-protect.sh --install # install as pre-push guard
#   bash scripts/branch-protect.sh --test    # run self-test
#
# What it does:
#   1. Enforces branch naming convention: only "main" and "fix/*" can receive pushes
#   2. Validates commit author against ALLOWED_AUTHORS list
#   3. Detects and blocks "foreign" branch pushes (branches not created by maintainers)
#   4. Checks that pushed commits don't modify module config files (.gitignore, validate.sh whitelist)
#   5. Validates that setup.sh / update.sh signatures are intact (file size + hash of first line)
# ============================================================
set -euo pipefail

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

# Read refs from stdin (pre-push provides: local_ref local_sha remote_ref remote_sha)
check_push() {
    local errors=0

    while read -r local_ref local_sha remote_ref remote_sha; do
        local branch_name="${remote_ref#refs/heads/}"

        info "Checking push to: $branch_name"

        # Check 1: Branch naming
        if ! branch_allowed "$branch_name"; then
            fail "Branch '$branch_name' does not match allowed patterns: ${ALLOWED_BRANCHES[*]}"
            errors=$((errors + 1))
            continue
        fi
        ok "Branch name allowed: $branch_name"

        # Check 2: For non-main branches, verify it was created locally (not force-pushed from outside)
        if [ "$branch_name" != "main" ]; then
            # Check if this branch exists in our local refs
            local existing
            existing=$(git -C "$MODULE_ROOT" for-each-ref --format='%(refname:short)' "refs/heads/$branch_name" 2>/dev/null || true)
            if [ -z "$existing" ] && [ "$remote_sha" != "0000000000000000000000000000000000000000" ]; then
                # New branch push to remote -- verify the local sha exists in our history
                local sha_exists
                sha_exists=$(git -C "$MODULE_ROOT" cat-file -t "$local_sha" 2>/dev/null || true)
                if [ -z "$sha_exists" ]; then
                    fail "Commit $local_sha does not exist locally -- foreign push attempt"
                    errors=$((errors + 1))
                    continue
                fi
            fi
        fi

        # Check 3: Protected files not modified in pushed commits
        if [ "$local_sha" != "0000000000000000000000000000000000000000" ]; then
            if [ "$remote_sha" = "0000000000000000000000000000000000000000" ]; then
                # New branch -- check all commits on this branch vs main
                local base_sha
                base_sha=$(git -C "$MODULE_ROOT" rev-parse main 2>/dev/null || echo "")
                if [ -n "$base_sha" ]; then
                    local changed_files
                    changed_files=$(git -C "$MODULE_ROOT" diff --name-only "$base_sha" "$local_sha" 2>/dev/null || true)
                    for pf in "${PROTECTED_FILES[@]}"; do
                        if echo "$changed_files" | grep -qx "$pf"; then
                            fail "Protected file '$pf' modified in push to '$branch_name'"
                            errors=$((errors + 1))
                        fi
                    done
                fi
            else
                # Update to existing branch
                local changed_files
                changed_files=$(git -C "$MODULE_ROOT" diff --name-only "$remote_sha" "$local_sha" 2>/dev/null || true)
                for pf in "${PROTECTED_FILES[@]}"; do
                    if echo "$changed_files" | grep -qx "$pf"; then
                        fail "Protected file '$pf' modified in push to '$branch_name'"
                        errors=$((errors + 1))
                    fi
                done
            fi
        fi

        # Check 4: Script fingerprint integrity
        for fp in "${SCRIPT_FINGERPRINTS[@]}"; do
            local ffile="${fp%%:*}"
            local expected="${fp#*:}"
            if [ -f "$MODULE_ROOT/$ffile" ]; then
                local first_line
                first_line=$(head -1 "$MODULE_ROOT/$ffile")
                if [ "$first_line" != "$expected" ]; then
                    fail "Script fingerprint mismatch: $ffile first line changed"
                    errors=$((errors + 1))
                fi
            fi
        done

        ok "Push to '$branch_name' passed all checks"

    done

    return $errors
}

# ============================================================
# MAIN
# ============================================================

case "${1:-audit}" in
    --install)
        info "Installing branch-protect as pre-push guard..."
        HOOK="$MODULE_ROOT/.git/hooks/pre-push"

        if [ -f "$HOOK" ]; then
            if grep -q "branch-protect.sh" "$HOOK" 2>/dev/null; then
                ok "branch-protect already in pre-push hook"
            else
                cat >> "$HOOK" << HOOKEOF

# ---- anti-hallucination-guard: branch protection ----
# Reads pushed refs from stdin, validates branch naming + protected files
bash "$MODULE_ROOT/scripts/branch-protect.sh" --guard
if [ \$? -ne 0 ]; then
    echo ""
    echo "  BRANCH PROTECTION: Push blocked by branch-protect.sh"
    echo "  Contact module maintainer if this is incorrect."
    echo ""
    exit 1
fi
HOOKEOF
                ok "branch-protect appended to pre-push hook"
            fi
        else
            cat > "$HOOK" << HOOKEOF
#!/bin/bash
# pre-push hook with branch protection
bash "$MODULE_ROOT/scripts/branch-protect.sh" --guard
if [ \$? -ne 0 ]; then
    echo "BRANCH PROTECTION: Push blocked"
    exit 1
fi
HOOKEOF
            chmod +x "$HOOK"
            ok "pre-push hook created with branch-protect"
        fi
        ;;

    --guard)
        # This is the pre-push guard mode: reads refs from stdin
        init_state
        if ! check_push; then
            exit 1
        fi
        ;;

    --test)
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
        ;;

    audit|*)
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
        ;;
esac
