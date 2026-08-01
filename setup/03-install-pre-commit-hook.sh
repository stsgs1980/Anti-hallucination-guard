#!/usr/bin/env bash
# setup/03-install-pre-commit-hook.sh
# Installs pre-commit hook for worklog freshness checks.
# Uses append strategy to preserve existing hooks (e.g. from cascade-guard).
# Behavior:
#   - No hook exists       -> copy from module
#   - Hook with AHG marker -> update (overwrite AHG portion only)
#   - Foreign hook exists   -> append AHG checks (cat >>)

mkdir -p "$HOOK_DIR"

if [ -f "$HOOK_DIR/pre-commit" ]; then
    EXPECTED_MARKER="anti-hallucination-guard"
    if grep -q "$EXPECTED_MARKER" "$HOOK_DIR/pre-commit" 2>/dev/null; then
        # Our hook is already there -- update it
        warn "pre-commit hook already installed (ours) -- updating"
        cp "$HOOK_SRC" "$HOOK_DIR/pre-commit"
        chmod +x "$HOOK_DIR/pre-commit"
        ok "pre-commit hook updated"
    else
        # Foreign hook exists -- append our checks instead of overwriting
        warn "pre-commit hook already exists (foreign) -- appending AHG checks"
        cat >> "$HOOK_DIR/pre-commit" << 'PRECOMMIT_APPEND'

# ---- anti-hallucination-guard: worklog checks ----
# anti-hallucination-guard
WORKLOG="worklog.md"
MAX_AGE=600  # 10 minutes

if [ ! -f "$WORKLOG" ]; then
    echo ""
    echo "  ERROR: worklog.md not found!"
    echo "  Create the file and describe the work done."
    echo ""
    exit 1
fi

LAST_MODIFIED=$(stat -c %Y "$WORKLOG" 2>/dev/null || stat -f %m "$WORKLOG" 2>/dev/null)
NOW=$(date +%s)
DIFF=$((NOW - LAST_MODIFIED))

if [ "$DIFF" -gt "$MAX_AGE" ]; then
    echo ""
    echo "  ERROR: worklog.md not updated for over $((MAX_AGE/60)) minutes!"
    echo "  Last update: $((DIFF/60)) min ago"
    echo "  Update worklog.md before committing."
    echo ""
    exit 1
fi

SIZE=$(wc -c < "$WORKLOG")
if [ "$SIZE" -lt 50 ]; then
    echo ""
    echo "  ERROR: worklog.md is empty (less than 50 bytes)!"
    echo "  Describe the work done."
    echo ""
    exit 1
fi

BLOCK_COUNT=$(grep -c '^---$' "$WORKLOG" 2>/dev/null)
if [ "$BLOCK_COUNT" -lt 2 ]; then
    echo ""
    echo "  ERROR: worklog.md does not contain standard blocks!"
    echo "  Format: --- / Task ID / Work Log / Stage Summary / ---"
    echo ""
    exit 1
fi

echo "  OK: worklog.md is up to date ($BLOCK_COUNT blocks)"
PRECOMMIT_APPEND
        ok "AHG checks appended to existing pre-commit hook"
    fi
else
    cp "$HOOK_SRC" "$HOOK_DIR/pre-commit"
    chmod +x "$HOOK_DIR/pre-commit"
    ok "pre-commit hook installed"
fi

# Save integrity snapshot after hook installation
# This snapshot should be committed to git so that tampering is detectable
if [ -f "$PROJECT_ROOT/scripts/check-hooks-verify.sh" ]; then
    bash "$PROJECT_ROOT/scripts/check-hooks-snapshot.sh" --snapshot 2>/dev/null && \
        ok "Integrity snapshot created (commit .ahg-integrity.json to git)" || \
        warn "Could not create integrity snapshot (non-critical)"
elif [ -f "$PROJECT_ROOT/scripts/check-hooks-integrity.sh" ]; then
    bash "$PROJECT_ROOT/scripts/check-hooks-integrity.sh" --snapshot 2>/dev/null && \
        ok "Integrity snapshot created" || \
        warn "Could not create integrity snapshot (non-critical)"
fi

# Install post-checkout hook (stale submodule detection)
_PC_HOOK_SRC="$MODULE_ROOT/.git-hooks/post-checkout"
_PC_HOOK_DST="$HOOK_DIR/post-checkout"
if [ -f "$_PC_HOOK_SRC" ]; then
    if [ -f "$_PC_HOOK_DST" ]; then
        if grep -q "anti-hallucination-guard" "$_PC_HOOK_DST" 2>/dev/null; then
            cp "$_PC_HOOK_SRC" "$_PC_HOOK_DST"
            chmod +x "$_PC_HOOK_DST"
            ok "post-checkout hook updated"
        else
            warn "post-checkout hook exists (foreign) -- not overwriting"
        fi
    else
        cp "$_PC_HOOK_SRC" "$_PC_HOOK_DST"
        chmod +x "$_PC_HOOK_DST"
        ok "post-checkout hook installed (stale AHG detection)"
    fi
fi
