#!/bin/bash
# anti-hallucination-guard / validate.sh
# ANTI-MONOLITH exception: flat whitelist config file, naturally exceeds 250 lines.
# Checks that the repository contains only module files.
# Run: bash validate.sh
# Can also be used as a pre-push hook.

set -euo pipefail

# Resolve the module repository root.
# BUG FIX: Do NOT use `git -C "$SCRIPT_DIR" rev-parse --show-toplevel`
# because when AHG is a git submodule, that resolves to the PARENT repo
# root (the consumer project), not the AHG submodule directory.
# Instead, use SCRIPT_DIR-relative resolution like check-hooks-lib.sh does.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Guard: validate.sh must only run inside the AHG module repo.
# If run from a consumer project, ALL consumer files would be flagged FORBIDDEN.
# We also verify we are NOT inside a submodule of a larger project
# (pushing from inside a submodule consumer should use AHG_MODULE_PUSH=1).
if [ ! -f "$MODULE_ROOT/setup.sh" ] || [ ! -f "$MODULE_ROOT/AGENT_RULES.md" ] || [ ! -f "$MODULE_ROOT/.git-hooks/pre-commit" ]; then
    echo "ERROR: validate.sh must run inside the AHG module repo."
    echo "  Current MODULE_ROOT: $MODULE_ROOT"
    echo "  This script checks AHG module purity, not consumer project files."
    echo "  If you see this in a pre-push hook, the hook context detection is broken."
    exit 1
fi

# Resolve the git working tree root to detect submodule context.
# In a standalone AHG repo, GIT_ROOT == MODULE_ROOT.
# In a submodule, GIT_ROOT == the consumer project root.
GIT_ROOT="$(git -C "$MODULE_ROOT" rev-parse --show-toplevel 2>/dev/null || echo "$MODULE_ROOT")"

# Submodule safety: if AHG is a submodule of a larger project,
# BLOCK push unless AHG_MODULE_PUSH=1 is explicitly set.
#
# DETECTION METHOD: In a git submodule, the .git entry is a FILE
# (containing a reference like "gitdir: ../.git/modules/xxx"),
# NOT a directory. In a standalone repo, .git IS a directory.
# Comparing GIT_ROOT != MODULE_ROOT does NOT work because
# `git -C <submodule-dir> rev-parse --show-toplevel` returns the
# submodule's own working tree, NOT the parent repo's root.
if [ -f "$MODULE_ROOT/.git" ]; then
    # .git is a file, not a directory -- we are inside a submodule
    if [ "${AHG_MODULE_PUSH:-}" != "1" ]; then
        echo ""
        echo "BLOCKED: Pushing from inside a git submodule."
        echo "  AHG module directory: $MODULE_ROOT"
        echo "  Consumer project root: $GIT_ROOT"
        echo "  Consumer projects must NOT push to the AHG module."
        echo "  If you are the maintainer, set AHG_MODULE_PUSH=1:"
        echo "    AHG_MODULE_PUSH=1 git push"
        echo ""
        exit 1
    fi
fi

# Whitelist of allowed paths
ALLOWED=(
    "setup.sh"
    "setup/"
    "setup/_lib.sh"
    "setup/01-deploy-agent-rules.sh"
    "setup/02-create-worklog.sh"
    "setup/03-install-pre-commit-hook.sh"
    "setup/04-install-pre-push-hook.sh"
    "setup/05-deploy-monitoring-scripts.sh"
    "setup/06-deploy-skill.sh"
    "setup/07-install-verify-docs.sh"
    "setup/08-integrate-cascade-guard.sh"
    "setup/09-git-staging.sh"
    "update.sh"
    "AGENT_RULES.md"
    "README.md"
    "CHANGELOG.md"
    "registry.json"
    ".gitignore"
    ".ahg-cochange.json"
    ".git-hooks/"
    ".git-hooks/pre-commit"
    ".git-hooks/pre-push"
    ".github/"
    ".github/CODEOWNERS"
    ".github/workflows/"
    ".github/workflows/*"
    "scripts/"
    "scripts/check-agent.sh"
    "scripts/audit.sh"
    "scripts/validate.sh"
    "scripts/branch-protect.sh"
    "scripts/branch-protect-lib.sh"
    "scripts/sync-task-state.sh"
    "scripts/ahg.sh"
    "scripts/check-hooks-lib.sh"
    "scripts/check-hooks-snapshot.sh"
    "scripts/check-hooks-verify.sh"
    "scripts/line-count-check.sh"
    "scripts/co-change-check.sh"
    "scripts/setup-branch-protection.sh"
    "skills/"
    "skills/anti-hallucination-guard/"
    "skills/anti-hallucination-guard/SKILL.md"
    "tools/"
    "tools/verify-docs/"
    "tools/verify-docs/src/"
    "tools/verify-docs/src/types.ts"
    "tools/verify-docs/src/resolvers.ts"
    "tools/verify-docs/src/resolve-check.ts"
    "tools/verify-docs/src/verify-section1.ts"
    "tools/verify-docs/src/verify-section2.ts"
    "tools/verify-docs/src/verify-section3.ts"
    "tools/verify-docs/src/verify-section4.ts"
    "tools/verify-docs/src/verify-section5.ts"
    "tools/verify-docs/src/engine.ts"
    "tools/verify-docs/src/auto-config.ts"
    "tools/verify-docs/src/cli-helpers.ts"
    "tools/verify-docs/src/cli.ts"
    "tools/verify-docs/src/discover-project.ts"
    "tools/verify-docs/src/init.ts"
    "tools/verify-docs/src/discover-versions.ts"
    "tools/verify-docs/src/discover-changelog.ts"
    "tools/verify-docs/src/discover-coverage.ts"
    "tools/verify-docs/src/discover-baseline.ts"
    "tools/verify-docs/src/discover.ts"
    "tools/verify-docs/src/bump.ts"
    "tools/verify-docs/package.json"
    "tools/verify-docs/templates/"
    "tools/verify-docs/templates/pre-push"
    "tools/verify-docs/templates/verify.yml"
    "tools/verify-docs/templates/install-hooks.ts"
    "tools/verify-docs/examples/"
    "tools/verify-docs/examples/simple/"
    "tools/verify-docs/examples/simple/verify-docs.json"
    "tools/verify-docs/examples/monorepo/"
    "tools/verify-docs/examples/monorepo/verify-docs.json"
    "tools/verify-docs/examples/monorepo/verify-docs.plugins.ts"
)

# Forbidden patterns
FORBIDDEN_PATTERNS=(
    "*.env"
    "*.log"
    "*.tmp"
    "node_modules/"
    ".next/"
    "upload/"
    "download/"
    "src/"
    "app/"
    "public/"
    "package-lock.json"
    "tsconfig.json"
    ".git/modules/"
)

ERRORS=0

echo "=== validate.sh: repository purity check ==="
echo ""

# Phase 0: Check for core.hooksPath bypass (anti-tampering)
HP=$(git -C "$MODULE_ROOT" config --get core.hooksPath 2>/dev/null || echo "")
if [ -n "$HP" ]; then
    echo "[-] core.hooksPath is set to '$HP'"
    echo "    This bypasses the standard .git/hooks/ directory."
    echo "    Unset it: git config --unset core.hooksPath"
    echo ""
    ERRORS=$((ERRORS + 1))
else
    echo "[+] core.hooksPath -- not set (OK)"
fi

# Phase 1: check that all tracked files are whitelisted
TRACKED_FILES=$(git -C "$MODULE_ROOT" ls-files)
ALLOWED_FILES=()

for FILE in $TRACKED_FILES; do
    ALLOWED_FLAG=0
    for PATTERN in "${ALLOWED[@]}"; do
        case "$FILE" in
            "$PATTERN"*) ALLOWED_FLAG=1 ;;
        esac
    done
    if [ "$ALLOWED_FLAG" -eq 0 ]; then
        echo "[-] FORBIDDEN FILE: $FILE"
        echo "    This file should not be in the module repository."
        echo "    Module contains only: setup.sh, AGENT_RULES.md, .git-hooks/, scripts/, tools/, skills/, README.md, .gitignore"
        ERRORS=$((ERRORS + 1))
    else
        ALLOWED_FILES+=("$FILE")
    fi
done

# (Forbidden patterns are superseded by the whitelist above.
#  If a path is whitelisted, it is allowed regardless of patterns.)

# Check that all allowed files exist
for ITEM in "${ALLOWED[@]}"; do
    if [ -e "$MODULE_ROOT/$ITEM" ]; then
        echo "[+] $ITEM -- OK"
    elif [[ "$ITEM" == */ ]]; then
        DIR_CONTENTS=$(find "$MODULE_ROOT/$ITEM" -type f 2>/dev/null | head -1)
        if [ -z "$DIR_CONTENTS" ]; then
            echo "[-] $ITEM -- EMPTY DIRECTORY (or missing)"
            ERRORS=$((ERRORS + 1))
        else
            echo "[+] $ITEM -- OK"
        fi
    fi
done

echo ""
echo "=== Result ==="

# Phase 2: Unicode policy check (Rule 14)
UNICODE_ERRORS=0
while IFS= read -r FILE; do
    if [ -f "$MODULE_ROOT/$FILE" ]; then
        # Check for prohibited Unicode: em dash, en dash, box drawing
        if grep -Pq '[\x{2014}\x{2013}\x{2500}-\x{257F}\x{1F000}-\x{1FFFF}]' "$MODULE_ROOT/$FILE" 2>/dev/null; then
            echo "[-] UNICODE POLICY: $FILE contains prohibited Unicode characters"
            UNICODE_ERRORS=$((UNICODE_ERRORS + 1))
        fi
    fi
done < <(git -C "$MODULE_ROOT" ls-files)

if [ "$UNICODE_ERRORS" -gt 0 ]; then
    echo ""
    echo "  UNICODE POLICY VIOLATIONS: $UNICODE_ERRORS files"
    echo "  Prohibited: em dash (U+2014), en dash (U+2013), box drawing (U+2500-257F)"
    echo "  Replace: -- for dashes, - for section dividers"
    echo ""
    ERRORS=$((ERRORS + UNICODE_ERRORS))
fi

if [ "$ERRORS" -eq 0 ]; then
    echo "Repository is clean. All files match the module."
    exit 0
else
    echo "ERRORS FOUND: $ERRORS"
    echo ""
    echo "Possible causes:"
    echo "  1. Pushing from sandbox -- submodule leaked into parent repo"
    echo "  2. Accidentally added foreign files (git add -A)"
    echo "  3. Module files deleted or renamed"
    echo ""
    echo "Fix:"
    echo "  git rm --cached <file>    -- remove from index"
    echo "  git commit --amend         -- fix the commit"
    echo ""
    exit 1
fi
