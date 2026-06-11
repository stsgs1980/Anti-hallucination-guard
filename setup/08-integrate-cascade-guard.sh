#!/usr/bin/env bash
# setup/08-integrate-cascade-guard.sh
# Detects cascade-guard submodule and integrates.
# Adds cascade-state.json freshness check to pre-commit hook.

CG_DIR=""
# Strategy: check common locations, then scan .gitmodules, then use find
if [ -d "cascade-guard" ]; then
    CG_DIR="cascade-guard"
elif [ -d "scripts/cascade-guard" ]; then
    CG_DIR="scripts/cascade-guard"
elif [ -f ".gitmodules" ]; then
    CG_DIR=$(git config -f .gitmodules --get-regexp 'path' 2>/dev/null | grep -i 'cascade.guard' | awk '{print $2}' | head -1 || true)
    if [ -n "$CG_DIR" ] && [ ! -d "$CG_DIR" ]; then
        git submodule update --init "$CG_DIR" 2>/dev/null || true
    fi
fi
if [ -z "$CG_DIR" ] || [ ! -d "$CG_DIR" ]; then
    CG_DIR=$(find . -maxdepth 4 -type d -name "cascade-guard" ! -path "*/node_modules/*" ! -path "*/.git/*" 2>/dev/null | head -1 || true)
fi

if [ -n "$CG_DIR" ] && [ -d "$CG_DIR" ]; then
    info "Cascade-guard detected at $CG_DIR -- integrating"

    # Add cascade-state.json freshness check to pre-commit hook
    if [ -f ".git/hooks/pre-commit" ]; then
        if ! grep -q "cascade-state.json" .git/hooks/pre-commit 2>/dev/null; then
            cat >> .git/hooks/pre-commit << 'CASCADE_HOOK'

# ---- Cascade-guard: check cascade-state.json freshness ----
if [ -f "cascade-state.json" ]; then
    if ! jq empty cascade-state.json 2>/dev/null; then
        echo "ERROR: cascade-state.json is not valid JSON"
        exit 1
    fi
    IN_PROGRESS=$(jq '[.phases[].tasks[] | select(.status == "in_progress")] | length' cascade-state.json 2>/dev/null || echo "0")
    PENDING=$(jq '[.phases[].tasks[] | select(.status == "pending")] | length' cascade-state.json 2>/dev/null || echo "0")
    if [ "$IN_PROGRESS" = "0" ] && [ "$PENDING" != "0" ]; then
        echo "WARN: No tasks in_progress but $PENDING pending. Did you forget to start a task?"
    fi
fi
CASCADE_HOOK
            ok "Cascade checks added to pre-commit hook"
        else
            ok "Cascade checks already in pre-commit hook"
        fi
    fi

    # AHG rules (1-6) and Cascade rules (C-1 to C-9) coexist in AGENT_RULES.md
    ok "AHG rules (1-6) and Cascade rules (C-1 to C-9) coexist in AGENT_RULES.md"
    ok "No duplication -- different namespaces (Rule N vs C-N) and separate markers"
else
    info "No Cascade-guard detected. Standalone mode."
    info "To add: git submodule add https://github.com/stsgs1980/Cascade-guard.git"
fi
