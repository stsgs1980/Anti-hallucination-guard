#!/bin/bash
# branch-protect.sh -- Branch-level protection against unauthorized pushes
# Usage: bash scripts/branch-protect.sh [--install|--guard|--test]
# See branch-protect-lib.sh for full documentation.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/branch-protect-lib.sh"

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

# -- MAIN --

case "${1:-audit}" in
    --install)
        info "Installing branch-protect as pre-push guard..."
        # Find the real hooks directory. In submodules, .git is a file (not a dir),
        # so we use git to find the actual git directory.
        _bp_git_dir=$(git -C "$MODULE_ROOT" rev-parse --git-dir 2>/dev/null || echo ".git")
        HOOK="$_bp_git_dir/hooks/pre-push"
        mkdir -p "$_bp_git_dir/hooks" 2>/dev/null || true

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
        run_test
        ;;

    audit|*)
        run_audit
        ;;
esac
