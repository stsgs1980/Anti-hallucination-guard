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
echo "  ANTI-HALLUCINATION-GUARD -- Update"
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
    ok "Submodule is up to date ($LOCAL_HASH)"
    echo ""

    # Check if deployed hooks match the submodule version.
    # If hooks are stale (e.g. after git submodule update --remote
    # without re-running setup.sh), we MUST re-deploy.
    _HOOKS_STALE=0
    _PRE_COMMIT="$PROJECT_ROOT/.git/hooks/pre-commit"
    _PRE_PUSH="$PROJECT_ROOT/.git/hooks/pre-push"

    if [ ! -f "$_PRE_COMMIT" ] || [ ! -f "$_PRE_PUSH" ]; then
        _HOOKS_STALE=1
        warn "Git hooks are missing -- need setup.sh"
    else
        # Check if hooks contain the current AHG version marker
        _hook_ver=$(grep -oP 'v\d+\.\d+\.\d+' "$_PRE_COMMIT" 2>/dev/null | head -1 || true)
        _module_ver=$(grep -oP 'v\d+\.\d+\.\d+' "$MODULE_ROOT/AGENT_RULES.md" 2>/dev/null | tail -1 || true)
        if [ -n "$_module_ver" ] && [ "$_hook_ver" != "$_module_ver" ]; then
            _HOOKS_STALE=1
            warn "Hooks are stale ($_hook_ver) -- module is $_module_ver"
        fi
    fi

    # Check AGENT_RULES.md freshness
    if [ -f "$PROJECT_ROOT/AGENT_RULES.md" ]; then
        if ! grep -q "Rule 1[56]" "$PROJECT_ROOT/AGENT_RULES.md" 2>/dev/null; then
            _HOOKS_STALE=1
            warn "AGENT_RULES.md missing Rule 15/16 -- need setup.sh"
        fi
    fi

    if [ "$_HOOKS_STALE" -eq 1 ]; then
        info "Re-running setup.sh to update deployed files..."
        cd "$PROJECT_ROOT"
        bash "$MODULE_ROOT/setup.sh"
        ok "Deployed files updated"
    else
        info "No changes to pull. Hooks and files are current."
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

# ---- 2. Clean up obsolete files from previous versions ----
cd "$PROJECT_ROOT"

info "Checking for obsolete files from previous AHG versions..."

# v1.0 -> v2.0: check-hooks-integrity.sh renamed to check-hooks-verify.sh
if [ -f "$PROJECT_ROOT/scripts/check-hooks-integrity.sh" ]; then
    # Only remove if the new version exists (confirm v2.0 is deployed)
    if [ -f "$PROJECT_ROOT/scripts/check-hooks-verify.sh" ]; then
        rm -f "$PROJECT_ROOT/scripts/check-hooks-integrity.sh"
        ok "Removed obsolete: scripts/check-hooks-integrity.sh (replaced by check-hooks-verify.sh)"
    else
        warn "Old scripts/check-hooks-integrity.sh found but check-hooks-verify.sh not yet deployed"
        warn "Setup.sh will handle this -- continuing"
    fi
fi

# v1.0: old monolith check-hooks.sh (before split into snapshot/verify)
if [ -f "$PROJECT_ROOT/scripts/check-hooks.sh" ]; then
    if [ -f "$PROJECT_ROOT/scripts/check-hooks-snapshot.sh" ]; then
        rm -f "$PROJECT_ROOT/scripts/check-hooks.sh"
        ok "Removed obsolete: scripts/check-hooks.sh (replaced by snapshot/verify split)"
    fi
fi

# ---- 3. Re-run setup.sh ----
cd "$PROJECT_ROOT"

if [ -f "$MODULE_ROOT/setup.sh" ]; then
    info "Re-running setup.sh to update hooks and deployed files..."
    bash "$MODULE_ROOT/setup.sh"
    ok "Setup completed"
else
    warn "setup.sh not found at $MODULE_ROOT/setup.sh"
fi

# ---- 4. Generate cascade-state.json ----
cd "$MODULE_ROOT"

CASCADE_FILE="$PROJECT_ROOT/cascade-state.json"
REGISTRY_FILE="$MODULE_ROOT/registry.json"
PREV_HASH="$LOCAL_HASH"
CURR_HASH=$(git rev-parse HEAD)

# Read current AHG version from registry or README
AHG_VERSION="unknown"
if [ -f "$REGISTRY_FILE" ]; then
    AHG_VERSION=$(grep '"version"' "$REGISTRY_FILE" | head -1 | sed 's/.*: *"//;s/".*//')
fi

# Read previous cascade-state if exists (for delta)
PREV_VERSION=""
if [ -f "$CASCADE_FILE" ]; then
    PREV_VERSION=$(grep '"ahgVersion"' "$CASCADE_FILE" | head -1 | sed 's/.*: *"//;s/".*//' 2>/dev/null || echo "")
fi

# Build changed items list from git diff
CHANGED_ITEMS=""
if [ -f "$REGISTRY_FILE" ] && [ "$PREV_HASH" != "$CURR_HASH" ]; then
    CHANGED_FILES_LIST=$(git diff --name-only "$PREV_HASH" "$CURR_HASH" 2>/dev/null || echo "")
    CHANGED_ITEMS=$(echo "$CHANGED_FILES_LIST" | tr '\n' ' ')
fi

# Generate cascade-state.json
info "Generating cascade-state.json in project root..."
cat > "$CASCADE_FILE" << CASCEOF
{
  "ahgVersion": "$AHG_VERSION",
  "previousVersion": "${PREV_VERSION:-none}",
  "previousCommit": "$PREV_HASH",
  "currentCommit": "$CURR_HASH",
  "updatedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "changedFiles": "$CHANGED_ITEMS",
  "items": [
CASCEOF

# Add items from registry.json if available
if [ -f "$REGISTRY_FILE" ] && command -v python3 &>/dev/null; then
    python3 -c "
import json, sys
with open('$REGISTRY_FILE') as f:
    reg = json.load(f)
items = reg.get('items', {})
first = True
for iid, entry in items.items():
    if not first:
        print(',')
    first = False
    print(f'    {{\"id\": \"{iid}\", \"version\": \"{entry.get(\"version\",\"?\")}\", \"level\": \"{entry.get(\"level\",\"?\")}\", \"status\": \"active\"}}', end='')
print()
" >> "$CASCADE_FILE" 2>/dev/null || warn "python3 not available -- items section will be empty"
fi

# Close JSON
cat >> "$CASCADE_FILE" << CASCEOF
  ],
  "changedSinceLastUpdate": [
CASCEOF

# Add delta for changed items
if [ -n "$PREV_VERSION" ] && [ "$PREV_VERSION" != "$AHG_VERSION" ] && [ -f "$REGISTRY_FILE" ] && command -v python3 &>/dev/null; then
    python3 -c "
import json
with open('$REGISTRY_FILE') as f:
    reg = json.load(f)
items = reg.get('items', {})
first = True
for iid, entry in items.items():
    if not first:
        print(',')
    first = False
    breaking = entry.get('level') == 'critical'
    print(f'    {{\"id\": \"{iid}\", \"from\": \"{PREV_VERSION}\", \"to\": \"{entry.get(\"version\",\"?\")}\", \"breaking\": {str(breaking).lower()}}}', end='')
print()
" >> "$CASCADE_FILE" 2>/dev/null
fi

cat >> "$CASCADE_FILE" << CASCEOF
  ]
}
CASCEOF

ok "cascade-state.json generated at $CASCADE_FILE"

if [ "$PREV_VERSION" != "" ] && [ "$PREV_VERSION" != "$AHG_VERSION" ]; then
    echo ""
    warn "Version changed: $PREV_VERSION -> $AHG_VERSION"
    echo "  Check cascade-state.json for changed items and breaking changes."
fi

# ---- 5. Remind to commit the submodule update ----
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
