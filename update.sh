#!/usr/bin/env bash
# ============================================================
# anti-hallucination-guard / update.sh
# One-command update: pull latest + reinstall into project.
#
# Usage (from consumer project root):
#   bash anti-hallucination-guard/update.sh
#
# Or from inside the submodule:
#   cd anti-hallucination-guard && bash update.sh
#
# Idempotent: safe to run multiple times.
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Resolve module root (where this script lives = submodule dir)
MODULE_ROOT="$SCRIPT_DIR"

# Resolve consumer project root
# If we're a submodule, project root is one level up from module dir.
# Fallback: use git toplevel of the parent repo.
if [ -d "$MODULE_ROOT/../.git" ] || [ -f "$MODULE_ROOT/../.gitmodules" ]; then
    PROJECT_ROOT="$(cd "$MODULE_ROOT/.." && pwd)"
else
    PROJECT_ROOT="$(cd "$MODULE_ROOT" && git -C .. rev-parse --show-toplevel 2>/dev/null || echo "$MODULE_ROOT/..")"
    PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd)"
fi

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${CYAN}[UPDATE]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*"; }

echo ""
echo "============================================"
echo "  ANTI-HALLUCINATION-GUARD — Update"
echo "============================================"
echo ""
echo "Module dir:   $MODULE_ROOT"
echo "Project root: $PROJECT_ROOT"
echo ""

# ---- 1. Fetch and pull latest changes ----
cd "$MODULE_ROOT"

info "Fetching latest changes from origin..."
git fetch origin main 2>&1 || {
    err "git fetch failed. Check your network and remote URL."
    exit 1
}

LOCAL_HASH=$(git rev-parse HEAD)
REMOTE_HASH=$(git rev-parse origin/main 2>/dev/null || echo "unknown")

if [ "$LOCAL_HASH" = "$REMOTE_HASH" ]; then
    ok "Already up to date ($LOCAL_HASH)"
    echo ""
    echo "No changes to pull. Current version is latest."
    # Still offer to re-run setup.sh (in case hooks are missing)
    if [ -f "$MODULE_ROOT/setup.sh" ]; then
        echo ""
        read -rp "Re-run setup.sh anyway? (y/N): " answer
        if [ "$answer" = "y" ] || [ "$answer" = "Y" ]; then
            cd "$PROJECT_ROOT"
            bash "$MODULE_ROOT/setup.sh"
        fi
    fi
    exit 0
fi

info "Updating: $LOCAL_HASH -> $REMOTE_HASH"

# Show what changed
CHANGED_FILES=$(git log --oneline HEAD..origin/main)
echo ""
echo "New commits:"
echo "$CHANGED_FILES" | while read -r line; do
    echo "  $line"
done
echo ""

# Pull the changes
git pull origin main 2>&1 || {
    err "git pull failed. You may have local changes that conflict."
    err "Stash them with: git stash && git pull && git stash pop"
    exit 1
}

ok "Pulled latest changes"

# ---- 2. Re-run setup.sh ----
cd "$PROJECT_ROOT"

if [ -f "$MODULE_ROOT/setup.sh" ]; then
    info "Re-running setup.sh to update hooks and deployed files..."
    bash "$MODULE_ROOT/setup.sh"
    ok "Setup completed"
else
    warn "setup.sh not found at $MODULE_ROOT/setup.sh"
fi

# ---- 3. Remind to commit the submodule update ----
echo ""
echo "============================================"
echo "  Update Complete!"
echo "============================================"
echo ""
echo "The submodule is now at: $(cd "$MODULE_ROOT" && git rev-parse --short HEAD)"
echo ""
echo "Don't forget to commit the submodule pointer in your project:"
echo ""
echo "  cd $PROJECT_ROOT"
echo "  git add anti-hallucination-guard"
echo "  git commit -m \"update: anti-hallucination-guard -> $(cd "$MODULE_ROOT" && git rev-parse --short HEAD)\""
echo ""
