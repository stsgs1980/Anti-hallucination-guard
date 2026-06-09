#!/bin/bash
# anti-hallucination-guard / validate.sh
# Checks that the repository contains only module files.
# Run: bash validate.sh
# Can also be used as a pre-push hook.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Whitelist of allowed paths
ALLOWED=(
    "setup.sh"
    "AGENT_RULES.md"
    "README.md"
    ".gitignore"
    ".git-hooks/"
    ".git-hooks/pre-commit"
    ".git-hooks/pre-push"
    "scripts/"
    "scripts/check-agent.sh"
    "scripts/audit.sh"
    "scripts/validate.sh"
    "skills/"
    "skills/anti-hallucination-guard/"
    "skills/anti-hallucination-guard/SKILL.md"
    "tools/"
    "tools/verify-docs/"
    "tools/verify-docs/src/"
    "tools/verify-docs/src/engine.ts"
    "tools/verify-docs/src/cli.ts"
    "tools/verify-docs/src/init.ts"
    "tools/verify-docs/package.json"
    "tools/verify-docs/templates/"
    "tools/verify-docs/templates/pre-push"
    "tools/verify-docs/templates/verify.yml"
    "tools/verify-docs/templates/install-hooks.ts"
    "tools/verify-docs/examples/"
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

# Check that all tracked files are allowed
TRACKED_FILES=$(git -C "$SCRIPT_DIR" ls-files)
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
    fi
done

# Check that no tracked files match forbidden patterns
for FILE in $TRACKED_FILES; do
    for PATTERN in "${FORBIDDEN_PATTERNS[@]}"; do
        case "$FILE" in
            *"$PATTERN"*)
                echo "[-] FORBIDDEN PATTERN: $FILE (match: $PATTERN)"
                ERRORS=$((ERRORS + 1))
                ;;
        esac
    done
done

# Check that all allowed files exist
for ITEM in "${ALLOWED[@]}"; do
    if [ -e "$SCRIPT_DIR/$ITEM" ]; then
        echo "[+] $ITEM -- OK"
    elif [[ "$ITEM" == */ ]]; then
        DIR_CONTENTS=$(find "$SCRIPT_DIR/$ITEM" -type f 2>/dev/null | head -1)
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
